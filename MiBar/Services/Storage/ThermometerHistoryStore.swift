import Foundation
import OSLog

/// 温湿度历史采样数据持久化与缓存存储器
/// 将各设备的温湿度读数持久化存储至 ~/Library/Application Support/MiBar/History/ 供后续图表与趋势分析使用。
@MainActor
final class ThermometerHistoryStore: Sendable {
    static let shared = ThermometerHistoryStore()

    private static let logger = Logger(subsystem: "com.mibar.app", category: "ThermometerHistoryStore")

    /// 最小记录节流间隔（默认 60 秒，避免高频广播导致文件膨胀）
    private let throttleInterval: TimeInterval = 60
    /// 单设备保留的最大采样点数（默认 5000 点，约可保存 1~2 个月的细粒度历史）
    private let maxRecordsPerDevice: Int = 5000
    /// 数据最大保留天数（30 天）
    private let maxRetentionDays: Double = 30

    /// 内存缓存：[NormalizedMAC: [ThermometerHistoryRecord]]
    private var memoryCache: [String: [ThermometerHistoryRecord]] = [:]
    /// 各设备最近一次入库记录的时间戳
    private var lastRecordedTime: [String: Date] = [:]

    /// 存储根目录
    private let historyDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.historyDirectory = appSupport.appendingPathComponent("MiBar/History", isDirectory: true)
        ensureDirectoryExists()
    }

    // MARK: - 写入与采样入库

    /// 记录一条设备温湿度读数（带去重、节流与增量合并逻辑）。
    func record(reading: ThermometerReading, for mac: String) {
        let cleanMAC = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        guard !cleanMAC.isEmpty else { return }
        guard reading.temperature != nil || reading.humidity != nil else { return }

        let now = Date()
        var records = getOrLoadRecords(for: cleanMAC)
        let lastTime = lastRecordedTime[cleanMAC] ?? records.last?.timestamp

        // 节流处理：若距离上一采样点小于 60 秒，则增量补全最新点的空缺指标，不新增点
        if let lastTime, now.timeIntervalSince(lastTime) < throttleInterval, !records.isEmpty {
            let lastIndex = records.count - 1
            var updated = records[lastIndex]
            var hasChange = false

            if updated.temperature == nil, let temp = reading.temperature {
                updated = ThermometerHistoryRecord(
                    id: updated.id,
                    timestamp: updated.timestamp,
                    deviceMAC: cleanMAC,
                    temperature: temp,
                    humidity: updated.humidity,
                    battery: updated.battery ?? reading.battery
                )
                hasChange = true
            }
            if updated.humidity == nil, let hum = reading.humidity {
                updated = ThermometerHistoryRecord(
                    id: updated.id,
                    timestamp: updated.timestamp,
                    deviceMAC: cleanMAC,
                    temperature: updated.temperature,
                    humidity: hum,
                    battery: updated.battery ?? reading.battery
                )
                hasChange = true
            }

            if hasChange {
                records[lastIndex] = updated
                memoryCache[cleanMAC] = records
                scheduleSave(for: cleanMAC, records: records)
            }
            return
        }

        // 新增独立采样点
        let newRecord = ThermometerHistoryRecord(
            timestamp: now,
            deviceMAC: cleanMAC,
            temperature: reading.temperature,
            humidity: reading.humidity,
            battery: reading.battery
        )

        records.append(newRecord)
        lastRecordedTime[cleanMAC] = now

        // 超量清理与过期截断
        let cutoffDate = now.addingTimeInterval(-maxRetentionDays * 86400)
        records = records.filter { $0.timestamp >= cutoffDate }
        if records.count > maxRecordsPerDevice {
            records = Array(records.suffix(maxRecordsPerDevice))
        }

        memoryCache[cleanMAC] = records
        scheduleSave(for: cleanMAC, records: records)

        Self.logger.debug("📈 [HistoryStore] 记录 [\(cleanMAC)] 历史点: Temp=\(reading.temperatureString), Hum=\(reading.humidityString), 累计点数: \(records.count)")
    }

    // MARK: - 查询接口

    /// 获取指定设备的历史记录（支持按时间范围筛选）。
    func history(for mac: String, range: HistoryTimeRange? = nil) -> [ThermometerHistoryRecord] {
        let cleanMAC = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        let allRecords = getOrLoadRecords(for: cleanMAC)

        guard let range else { return allRecords }
        let start = range.startDate
        return allRecords.filter { $0.timestamp >= start }
    }

    /// 计算指定设备在某时间范围内的极值与均值统计数据。
    func stats(for mac: String, range: HistoryTimeRange? = nil) -> ThermometerHistoryStats {
        let records = history(for: mac, range: range)
        guard !records.isEmpty else { return .empty }

        let temps = records.compactMap { $0.temperature }
        let hums = records.compactMap { $0.humidity }

        let minTemp = temps.min()
        let maxTemp = temps.max()
        let avgTemp = temps.isEmpty ? nil : (temps.reduce(0, +) / Double(temps.count))

        let minHum = hums.min()
        let maxHum = hums.max()
        let avgHum = hums.isEmpty ? nil : (hums.reduce(0, +) / Double(hums.count))

        return ThermometerHistoryStats(
            minTemperature: minTemp,
            maxTemperature: maxTemp,
            avgTemperature: avgTemp,
            minHumidity: minHum,
            maxHumidity: maxHum,
            avgHumidity: avgHum,
            count: records.count
        )
    }

    /// 获取某设备的最近一条历史采样点。
    func latestRecord(for mac: String) -> ThermometerHistoryRecord? {
        let cleanMAC = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        return getOrLoadRecords(for: cleanMAC).last
    }

    /// 清除指定设备的历史记录。
    func clearHistory(for mac: String) {
        let cleanMAC = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        memoryCache.removeValue(forKey: cleanMAC)
        lastRecordedTime.removeValue(forKey: cleanMAC)

        let fileURL = fileURL(for: cleanMAC)
        try? FileManager.default.removeItem(at: fileURL)
        Self.logger.info("🗑️ [HistoryStore] 已清除设备 [\(cleanMAC)] 历史数据")
    }

    // MARK: - 持久化与文件 I/O

    private func getOrLoadRecords(for mac: String) -> [ThermometerHistoryRecord] {
        if let cached = memoryCache[mac] {
            return cached
        }
        let file = fileURL(for: mac)
        guard FileManager.default.fileExists(atPath: file.path) else {
            memoryCache[mac] = []
            return []
        }
        do {
            let data = try Data(contentsOf: file)
            let decoded = try JSONDecoder().decode([ThermometerHistoryRecord].self, from: data)
            memoryCache[mac] = decoded
            return decoded
        } catch {
            Self.logger.error("❌ [HistoryStore] 读取历史文件失败: \(error.localizedDescription, privacy: .public)")
            memoryCache[mac] = []
            return []
        }
    }

    private func scheduleSave(for mac: String, records: [ThermometerHistoryRecord]) {
        let file = fileURL(for: mac)
        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(records)
                try data.write(to: file, options: .atomic)
            } catch {
                Self.logger.error("❌ [HistoryStore] 保存历史数据失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fileURL(for mac: String) -> URL {
        historyDirectory.appendingPathComponent("history_\(mac).json")
    }

    private func ensureDirectoryExists() {
        if !FileManager.default.fileExists(atPath: historyDirectory.path) {
            try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        }
    }
}
