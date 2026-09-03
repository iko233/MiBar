import Foundation
import CoreBluetooth
import OSLog
import SwiftUI

/// 统一管理米家温湿度计多设备状态、蓝牙监听生命周期与配置的 Store。
@Observable
@MainActor
final class ThermometerStore {
    private static let logger = Logger(subsystem: "com.extrastu.mibar", category: "ThermometerStore")

    var configuration: ThermometerConfiguration = ThermometerConfiguration()
    var readings: [String: ThermometerReading] = [:] // key: normalizedMAC
    var reading: ThermometerReading? // 主设备读数（兼容单设备引用）

    var isScanning: Bool = false
    var bluetoothState: CBManagerState = .unknown
    var statusText: String = "未配置"

    // 扫描雷达与云端设备池
    var discoveredBLEDevices: [DiscoveredBLEDevice] = []
    var cachedCloudThermometers: [CloudThermometerRecord] = []

    // 编辑状态
    var isEditingConfiguration: Bool = false
    var editingDeviceID: String? = nil // 若为 nil 则表示添加新设备
    var draftMAC: String = ""
    var draftBindKey: String = ""
    var draftName: String = ""
    var draftModelType: ThermometerModelType = .v3Mini

    /// 附近检测到的活跃温湿度计（用于辅助用户确认 MAC）
    var nearbyDetectedMAC: String?
    var nearbyDetectedName: String?
    var nearbyDetectedRSSI: Int?

    private let bluetoothService = BluetoothThermometerService()
    private var isStarted = false

    init() {
        self.configuration = LocalConfigStore.readThermometerConfig()
        self.cachedCloudThermometers = LocalConfigStore.readCachedCloudThermometers()
        syncDraftWithPrimary()
    }

    /// 快捷访问已配置的设备列表
    var devices: [ThermometerDevice] {
        configuration.devices
    }

    /// 当前的主设备
    var primaryDevice: ThermometerDevice? {
        configuration.primaryDevice
    }

    /// 获取特定设备的读数
    func reading(for device: ThermometerDevice) -> ThermometerReading? {
        readings[device.normalizedMAC]
    }

    /// 启动温湿度计蓝牙监听与状态监听。
    func start() {
        guard !isStarted else { return }
        isStarted = true

        Self.logger.info("🚀 [ThermometerStore] 启动温湿度计服务，当前有效设备数: \(self.configuration.devices.count, privacy: .public)")

        bluetoothService.onDeviceReadingUpdated = { [weak self] mac, newReading in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = self.readings[mac]
                let merged = (current ?? ThermometerReading()).merged(with: newReading)
                self.readings[mac] = merged
                if self.configuration.primaryDevice?.normalizedMAC == mac || self.reading == nil {
                    self.reading = merged
                    self.statusText = "已连接（刚刚更新）"
                }
                Self.logger.info("📊 [ThermometerStore] 收到 [MAC: \(mac, privacy: .public)] 读数: \(merged.temperatureString), \(merged.humidityString), 电量=\(merged.battery.map { "\($0)%" } ?? "无")")
            }
        }

        bluetoothService.onStateChanged = { [weak self] state, scanning in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.bluetoothState = state
                self.isScanning = scanning
                self.updateStatusText()
                Self.logger.info("📶 [ThermometerStore] 蓝牙状态更新: state=\(state.rawValue, privacy: .public), 正在扫描=\(scanning, privacy: .public)")
            }
        }

        bluetoothService.onNearbyDeviceDetected = { [weak self] mac, name, rssi in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rssi > -70 {
                    self.nearbyDetectedMAC = mac
                    self.nearbyDetectedName = name
                    self.nearbyDetectedRSSI = rssi
                }
            }
        }

        bluetoothService.onDiscoveredDevicesUpdated = { [weak self] list in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.discoveredBLEDevices = list
            }
        }

        bluetoothService.start()
        if configuration.isValid {
            bluetoothService.updateConfiguration(configuration)
        }
        updateStatusText()
    }

    // MARK: - 扫描添加核心逻辑 (Scan-to-Add)

    /// 检查某个 MAC 地址是否在云端已获取到对应 BindKey。
    func matchCloudRecord(for mac: String) -> CloudThermometerRecord? {
        let clean = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        return cachedCloudThermometers.first { $0.normalizedMAC == clean }
    }

    /// 从蓝牙扫描雷达直接一键添加设备。
    func addFromDiscoveredBLE(_ bleDev: DiscoveredBLEDevice) {
        let cleanMAC = bleDev.mac
        let cloudRec = matchCloudRecord(for: cleanMAC)
        let bindKey = cloudRec?.bindKey ?? ""
        let name = (cloudRec?.name.isEmpty == false ? cloudRec?.name : nil) ?? bleDev.modelType.rawValue

        let isFirst = configuration.devices.isEmpty
        let newDev = ThermometerDevice(
            name: name,
            mac: cleanMAC,
            bindKey: bindKey,
            modelType: bleDev.modelType,
            isPrimary: isFirst
        )

        var updated = configuration.devices
        if let idx = updated.firstIndex(where: { $0.normalizedMAC == cleanMAC }) {
            updated[idx] = newDev
        } else {
            updated.append(newDev)
        }

        configuration.devices = updated
        LocalConfigStore.saveThermometerConfig(configuration)
        bluetoothService.updateConfiguration(configuration)

        if bindKey.isEmpty {
            // 云端未匹配到密钥，引导到编辑页快速输入或扫码
            beginEditing(device: newDev)
        } else {
            isEditingConfiguration = false
            editingDeviceID = nil
        }
        updateStatusText()
        Self.logger.info("✨ [ThermometerStore] 从扫描雷达添加设备: \(name) [\(cleanMAC)], 密钥是否已就绪: \(!bindKey.isEmpty)")
    }

    /// 从云端设备列表直接添加设备。
    func addFromCloudRecord(_ record: CloudThermometerRecord) {
        let cleanMAC = record.normalizedMAC
        let newDev = ThermometerDevice(
            name: record.name,
            mac: cleanMAC,
            bindKey: record.bindKey,
            modelType: record.modelType,
            isPrimary: configuration.devices.isEmpty
        )

        var updated = configuration.devices
        if let idx = updated.firstIndex(where: { $0.normalizedMAC == cleanMAC }) {
            updated[idx] = newDev
        } else {
            updated.append(newDev)
        }

        configuration.devices = updated
        LocalConfigStore.saveThermometerConfig(configuration)
        bluetoothService.updateConfiguration(configuration)
        isEditingConfiguration = false
        editingDeviceID = nil
        updateStatusText()
        Self.logger.info("✨ [ThermometerStore] 从云端同步列表直接添加: \(record.name) [\(cleanMAC)]")
    }

    /// 更新云端扫码提取的所有温湿度计凭据。
    func updateCloudThermometers(_ records: [CloudThermometerRecord]) {
        self.cachedCloudThermometers = records
        LocalConfigStore.saveCachedCloudThermometers(records)

        // 自动用提取到的 BindKey 补齐本地已添加但无密钥的设备
        var hasChanges = false
        var updated = configuration.devices
        for idx in updated.indices {
            if updated[idx].bindKey.isEmpty,
               let match = records.first(where: { $0.normalizedMAC == updated[idx].normalizedMAC }) {
                updated[idx].bindKey = match.bindKey
                if updated[idx].name == updated[idx].modelType.rawValue && !match.name.isEmpty {
                    updated[idx].name = match.name
                }
                hasChanges = true
            }
        }
        if hasChanges {
            configuration.devices = updated
            LocalConfigStore.saveThermometerConfig(configuration)
            bluetoothService.updateConfiguration(configuration)
        }
    }

    /// 兼容旧版单一设备导入
    func importFromCloud(device: XiaomiCloudDevice, bindKey: String) {
        let rec = CloudThermometerRecord(
            did: device.did,
            name: device.name,
            model: device.model,
            mac: device.mac,
            bindKey: bindKey
        )
        var list = cachedCloudThermometers
        if let idx = list.firstIndex(where: { $0.did == rec.did }) {
            list[idx] = rec
        } else {
            list.append(rec)
        }
        updateCloudThermometers(list)
        addFromCloudRecord(rec)
    }

    // MARK: - 设备管理

    /// 设为主显示设备。
    func setPrimaryDevice(mac: String) {
        let clean = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        for idx in configuration.devices.indices {
            configuration.devices[idx].isPrimary = (configuration.devices[idx].normalizedMAC == clean)
        }
        LocalConfigStore.saveThermometerConfig(configuration)
        reading = readings[clean]
        Self.logger.info("⭐️ [ThermometerStore] 设为主设备: \(clean, privacy: .public)")
    }

    /// 删除指定设备。
    func deleteDevice(mac: String) {
        let clean = mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        configuration.devices.removeAll { $0.normalizedMAC == clean }
        readings.removeValue(forKey: clean)

        if configuration.primaryDevice == nil, let first = configuration.devices.first {
            setPrimaryDevice(mac: first.normalizedMAC)
        } else if configuration.devices.isEmpty {
            reading = nil
        }

        LocalConfigStore.saveThermometerConfig(configuration)
        bluetoothService.updateConfiguration(configuration)
        updateStatusText()
        Self.logger.info("🗑️ [ThermometerStore] 已删除设备: \(clean, privacy: .public)")
    }

    /// 保存用户手动配置或修改的温湿度计信息。
    func saveDraftConfiguration() {
        let cleanMAC = draftMAC.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
        let cleanKey = draftBindKey.lowercased().filter { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draftModelType.rawValue : draftName

        var updatedDevices = configuration.devices

        if let editingID = editingDeviceID, let idx = updatedDevices.firstIndex(where: { $0.normalizedMAC == editingID }) {
            updatedDevices[idx].name = name
            updatedDevices[idx].mac = cleanMAC
            updatedDevices[idx].bindKey = cleanKey
            updatedDevices[idx].modelType = draftModelType
        } else {
            let isFirst = updatedDevices.isEmpty
            let newDev = ThermometerDevice(
                name: name,
                mac: cleanMAC,
                bindKey: cleanKey,
                modelType: draftModelType,
                isPrimary: isFirst
            )
            if let existingIdx = updatedDevices.firstIndex(where: { $0.normalizedMAC == cleanMAC }) {
                updatedDevices[existingIdx] = newDev
            } else {
                updatedDevices.append(newDev)
            }
        }

        configuration.devices = updatedDevices
        LocalConfigStore.saveThermometerConfig(configuration)
        bluetoothService.updateConfiguration(configuration)

        isEditingConfiguration = false
        editingDeviceID = nil
        updateStatusText()

        Self.logger.info("💾 [ThermometerStore] 已保存温湿度计: MAC=\(cleanMAC, privacy: .public), 当前设备总数=\(self.configuration.devices.count)")
    }

    /// 开始添加新设备（切换至扫描/添加视图）。
    func beginAddingNewDevice() {
        editingDeviceID = nil
        draftMAC = ""
        draftBindKey = ""
        draftName = ""
        draftModelType = .v3Mini
        isEditingConfiguration = true
    }

    /// 开始编辑已有设备。
    func beginEditing(device: ThermometerDevice) {
        editingDeviceID = device.normalizedMAC
        draftMAC = device.formattedMAC
        draftBindKey = device.bindKey
        draftName = device.name
        draftModelType = device.modelType
        isEditingConfiguration = true
    }

    func beginEditing() {
        if let primary = primaryDevice {
            beginEditing(device: primary)
        } else {
            beginAddingNewDevice()
        }
    }

    /// 清空所有温湿度计配置。
    func clearConfiguration() {
        configuration = ThermometerConfiguration()
        readings.removeAll()
        reading = nil
        draftMAC = ""
        draftBindKey = ""
        draftName = ""
        editingDeviceID = nil

        LocalConfigStore.deleteThermometerConfig()
        bluetoothService.updateConfiguration(configuration)
        updateStatusText()

        Self.logger.info("🗑️ [ThermometerStore] 已清除全部温湿度计配置")
    }

    /// 取消编辑。
    func cancelEditing() {
        isEditingConfiguration = false
        editingDeviceID = nil
    }

    /// 从系统剪贴板一键粘贴 MAC 地址并清洗。
    func pasteMACFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            draftMAC = string.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.logger.debug("📋 [ThermometerStore] 从剪贴板粘贴 MAC")
        }
    }

    /// 从系统剪贴板一键粘贴 BindKey。
    func pasteBindKeyFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            draftBindKey = string.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.logger.debug("📋 [ThermometerStore] 从剪贴板粘贴 BindKey")
        }
    }

    /// 格式化附近检测到的设备 MAC 地址。
    var formattedNearbyMAC: String {
        guard let clean = nearbyDetectedMAC, clean.count == 12 else { return nearbyDetectedMAC ?? "" }
        var parts: [String] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let start = clean.index(clean.startIndex, offsetBy: i)
            let end = clean.index(start, offsetBy: 2)
            parts.append(String(clean[start..<end]))
        }
        return parts.joined(separator: ":")
    }

    /// 一键将检测到的附近设备 MAC 应用到当前草稿。
    func useDetectedNearbyMAC() {
        guard !formattedNearbyMAC.isEmpty else { return }
        draftMAC = formattedNearbyMAC
        if let detectedName = nearbyDetectedName, !detectedName.isEmpty {
            draftModelType = ThermometerModelType.from(modelString: detectedName)
            if draftName.isEmpty {
                draftName = draftModelType.rawValue
            }
        }
        isEditingConfiguration = true
        Self.logger.info("🎯 [ThermometerStore] 已一键填入附近检测到的 MAC: \(self.formattedNearbyMAC, privacy: .public)")
    }

    /// 重新启动蓝牙监听以刷新数据。
    func restartScanning() {
        Self.logger.info("🔄 [ThermometerStore] 手动触发重新扫描")
        bluetoothService.stop()
        if configuration.isValid {
            bluetoothService.updateConfiguration(configuration)
        }
        updateStatusText()
    }

    private func syncDraftWithPrimary() {
        if let primary = primaryDevice {
            draftMAC = primary.formattedMAC
            draftBindKey = primary.bindKey
            draftName = primary.name
            draftModelType = primary.modelType
        }
    }

    private func updateStatusText() {
        guard configuration.isValid else {
            statusText = "未配置"
            return
        }

        switch bluetoothState {
        case .poweredOff:
            statusText = "蓝牙已关闭"
        case .unauthorized:
            statusText = "蓝牙权限未授予"
        case .unsupported:
            statusText = "设备不支持蓝牙"
        case .poweredOn:
            if !readings.isEmpty {
                statusText = "已连接（\(readings.count) 台在线）"
            } else {
                statusText = "正在搜索温湿度计广播…"
            }
        default:
            statusText = "蓝牙初始化中…"
        }
    }
}
