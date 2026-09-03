import Foundation

/// 米家智能温湿度计读数（支持增量分包合并）。
nonisolated struct ThermometerReading: Sendable, Equatable {
    var temperature: Double?
    var humidity: Double?
    var battery: Int?
    var timestamp: Date

    init(
        temperature: Double? = nil,
        humidity: Double? = nil,
        battery: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.temperature = temperature
        self.humidity = humidity
        self.battery = battery
        self.timestamp = timestamp
    }

    /// 与增量读数合并（保留未更新的已有字段）
    func merged(with incoming: ThermometerReading) -> ThermometerReading {
        ThermometerReading(
            temperature: incoming.temperature ?? self.temperature,
            humidity: incoming.humidity ?? self.humidity,
            battery: incoming.battery ?? self.battery,
            timestamp: incoming.timestamp
        )
    }

    /// 格式化温度显示，例如 "24.5°C"。
    var temperatureString: String {
        if let temperature {
            return String(format: "%.1f°C", temperature)
        }
        return "--.-°C"
    }

    /// 格式化湿度显示，例如 "55%"。
    var humidityString: String {
        if let humidity {
            return String(format: "%.0f%%", humidity)
        }
        return "--%"
    }

    /// 菜单栏紧凑摘要，例如 "24.5°C 55%"。
    var menuBarSummary: String {
        if temperature != nil && humidity != nil {
            return "\(temperatureString) \(humidityString)"
        } else if temperature != nil {
            return temperatureString
        } else if humidity != nil {
            return humidityString
        }
        return ""
    }

    /// 相对更新时间，例如 "刚刚更新"、"1 分钟前"。
    var relativeTimeString: String {
        let diff = max(0, Date().timeIntervalSince(timestamp))
        if diff < 15 {
            return "刚刚更新"
        } else if diff < 60 {
            return "\(Int(diff)) 秒前"
        } else if diff < 3600 {
            return "\(Int(diff / 60)) 分钟前"
        } else {
            return "\(Int(diff / 3600)) 小时前"
        }
    }
}

/// 温湿度计型号枚举。
nonisolated enum ThermometerModelType: String, Codable, Sendable, CaseIterable {
    case v3Mini = "米家智能温湿度计 3 mini"    // MJWSD06MMC, PID: 0x55B5
    case v3 = "米家智能温湿度计 3"          // MJWSD05MMC, PID: 0x2832, 0x4C47
    case v2 = "米家蓝牙温湿度计 2"            // LYWSD03MMC, PID: 0x031A
    case custom = "米家温湿度计"

    var shortName: String {
        switch self {
        case .v3Mini: return "3 mini"
        case .v3: return "3 代"
        case .v2: return "2 代"
        case .custom: return "温湿度计"
        }
    }

    var defaultModelCode: String {
        switch self {
        case .v3Mini: return "MJWSD06MMC"
        case .v3: return "MJWSD05MMC"
        case .v2: return "LYWSD03MMC"
        case .custom: return "BLE Sensor"
        }
    }

    static func from(productID: UInt16) -> ThermometerModelType {
        switch productID {
        case 0x55B5: return .v3Mini
        case 0x2832, 0x4C47: return .v3
        case 0x031A: return .v2
        default: return .custom
        }
    }

    static func from(modelString: String) -> ThermometerModelType {
        let lower = modelString.lowercased()
        if lower.contains("mjwsd06") || lower.contains("mini") {
            return .v3Mini
        } else if lower.contains("mjwsd05") || lower.contains("sensor_ht") {
            return .v3
        } else if lower.contains("lywsd03") {
            return .v2
        }
        return .custom
    }
}

/// 单个米家温湿度计设备定义。
nonisolated struct ThermometerDevice: Identifiable, Codable, Sendable, Equatable {
    var id: String { normalizedMAC }
    var name: String
    var mac: String
    var bindKey: String
    var modelType: ThermometerModelType
    var isPrimary: Bool

    init(
        name: String = "米家温湿度计",
        mac: String = "",
        bindKey: String = "",
        modelType: ThermometerModelType = .v3Mini,
        isPrimary: Bool = false
    ) {
        self.name = name
        self.mac = mac
        self.bindKey = bindKey
        self.modelType = modelType
        self.isPrimary = isPrimary
    }

    /// 规范化后的 12 字符大写 MAC 地址。
    var normalizedMAC: String {
        mac.uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
    }

    /// 标准冒号分隔格式化 MAC，如 "AA:BB:CC:DD:EE:FF"。
    var formattedMAC: String {
        let clean = normalizedMAC
        guard clean.count == 12 else { return mac }
        var parts: [String] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let start = clean.index(clean.startIndex, offsetBy: i)
            let end = clean.index(start, offsetBy: 2)
            parts.append(String(clean[start..<end]))
        }
        return parts.joined(separator: ":")
    }

    /// 规范化后的 32 字符小写 BindKey。
    var normalizedBindKey: String {
        bindKey.lowercased().filter { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// 是否有效。
    var isValid: Bool {
        normalizedMAC.count == 12 && normalizedBindKey.count == 32
    }
}

/// 米家智能温湿度计配置信息（支持多设备与向后兼容）。
nonisolated struct ThermometerConfiguration: Codable, Sendable, Equatable {
    var devices: [ThermometerDevice]
    var showInMenuBar: Bool
    var cycleInMenuBar: Bool

    init(
        devices: [ThermometerDevice] = [],
        showInMenuBar: Bool = true,
        cycleInMenuBar: Bool = false
    ) {
        self.devices = devices
        self.showInMenuBar = showInMenuBar
        self.cycleInMenuBar = cycleInMenuBar
    }

    /// 单设备向后兼容初始化
    init(
        mac: String = "",
        bindKey: String = "",
        name: String = "米家智能温湿度计 3 mini",
        showInMenuBar: Bool = true
    ) {
        self.showInMenuBar = showInMenuBar
        self.cycleInMenuBar = false
        if !mac.isEmpty || !bindKey.isEmpty {
            let type = ThermometerModelType.from(modelString: name)
            self.devices = [
                ThermometerDevice(name: name, mac: mac, bindKey: bindKey, modelType: type, isPrimary: true)
            ]
        } else {
            self.devices = []
        }
    }

    /// 当前主设备（用于在菜单栏优先显示）
    var primaryDevice: ThermometerDevice? {
        devices.first(where: { $0.isPrimary }) ?? devices.first
    }

    /// 兼容旧代码访问单设备属性
    var mac: String {
        get { primaryDevice?.mac ?? "" }
        set {
            if devices.isEmpty {
                devices.append(ThermometerDevice(mac: newValue, isPrimary: true))
            } else {
                devices[0].mac = newValue
            }
        }
    }

    var bindKey: String {
        get { primaryDevice?.bindKey ?? "" }
        set {
            if devices.isEmpty {
                devices.append(ThermometerDevice(bindKey: newValue, isPrimary: true))
            } else {
                devices[0].bindKey = newValue
            }
        }
    }

    var name: String {
        get { primaryDevice?.name ?? "米家智能温湿度计" }
        set {
            if devices.isEmpty {
                devices.append(ThermometerDevice(name: newValue, isPrimary: true))
            } else {
                devices[0].name = newValue
            }
        }
    }

    var normalizedMAC: String { primaryDevice?.normalizedMAC ?? "" }
    var formattedMAC: String { primaryDevice?.formattedMAC ?? "" }
    var normalizedBindKey: String { primaryDevice?.normalizedBindKey ?? "" }
    var isValid: Bool { devices.contains(where: { $0.isValid }) }
}

/// 本地 BLE 广播扫描到的周围米家温湿度计设备。
nonisolated struct DiscoveredBLEDevice: Identifiable, Sendable, Equatable {
    var id: String { mac }
    let mac: String // 12 位大写规范化 MAC
    let modelType: ThermometerModelType
    let modelCode: String
    var rssi: Int
    var lastSeen: Date

    /// 格式化为冒号分隔的 MAC 地址
    var formattedMAC: String {
        guard mac.count == 12 else { return mac }
        var parts: [String] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let start = mac.index(mac.startIndex, offsetBy: i)
            let end = mac.index(start, offsetBy: 2)
            parts.append(String(mac[start..<end]))
        }
        return parts.joined(separator: ":")
    }

    /// 信号等级（1 至 4 格）
    var signalLevel: Int {
        if rssi >= -50 { return 4 }
        else if rssi >= -65 { return 3 }
        else if rssi >= -80 { return 2 }
        else { return 1 }
    }

    /// 信号强弱中文描述
    var signalDescription: String {
        if rssi >= -50 { return "极强" }
        else if rssi >= -65 { return "良好" }
        else if rssi >= -80 { return "一般" }
        else { return "微弱" }
    }
}

/// 米家云端扫码提取并缓存的温湿度计设备凭据。
nonisolated struct CloudThermometerRecord: Codable, Sendable, Identifiable, Equatable {
    var id: String { did }
    let did: String
    let name: String
    let model: String
    let mac: String?
    let bindKey: String

    var normalizedMAC: String {
        (mac ?? "").uppercased().filter { ("0"..."9").contains($0) || ("A"..."F").contains($0) }
    }

    var formattedMAC: String {
        let clean = normalizedMAC
        guard clean.count == 12 else { return mac ?? "" }
        var parts: [String] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let start = clean.index(clean.startIndex, offsetBy: i)
            let end = clean.index(start, offsetBy: 2)
            parts.append(String(clean[start..<end]))
        }
        return parts.joined(separator: ":")
    }

    var modelType: ThermometerModelType {
        ThermometerModelType.from(modelString: model + name)
    }
}

