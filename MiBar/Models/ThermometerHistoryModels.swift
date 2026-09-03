import Foundation

/// 单条温湿度历史采样点数据模型。
struct ThermometerHistoryRecord: Codable, Identifiable, Sendable, Equatable {
    var id: String
    let timestamp: Date
    let deviceMAC: String
    let temperature: Double?
    let humidity: Double?
    let battery: Int?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        deviceMAC: String,
        temperature: Double?,
        humidity: Double?,
        battery: Int?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.deviceMAC = deviceMAC
        self.temperature = temperature
        self.humidity = humidity
        self.battery = battery
    }
}

/// 历史图表时间跨度筛选枚举。
enum HistoryTimeRange: String, CaseIterable, Sendable {
    case last1Hour = "1小时"
    case last24Hours = "24小时"
    case last7Days = "7天"
    case last30Days = "30天"

    var timeInterval: TimeInterval {
        switch self {
        case .last1Hour: return 3600
        case .last24Hours: return 86400
        case .last7Days: return 86400 * 7
        case .last30Days: return 86400 * 30
        }
    }

    var startDate: Date {
        Date().addingTimeInterval(-timeInterval)
    }
}

/// 历史统计摘要信息（极值与均值，供图表与趋势卡片使用）。
struct ThermometerHistoryStats: Sendable, Equatable {
    let minTemperature: Double?
    let maxTemperature: Double?
    let avgTemperature: Double?
    let minHumidity: Double?
    let maxHumidity: Double?
    let avgHumidity: Double?
    let count: Int

    static let empty = ThermometerHistoryStats(
        minTemperature: nil,
        maxTemperature: nil,
        avgTemperature: nil,
        minHumidity: nil,
        maxHumidity: nil,
        avgHumidity: nil,
        count: 0
    )
}
