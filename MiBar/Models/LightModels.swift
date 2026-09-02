import Foundation

/// 挂灯当前可控状态。
nonisolated struct LightState: Sendable, Equatable {
    var isOn = false
    var brightness = 50
    var colorTemperature = 4_000
}

/// MIoT 请求和响应使用的 JSON 值。
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case null

    /// 按具体 JSON 基础类型解码，避免把布尔值误判为数字。
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "不支持的 JSON 值")
            )
        }
    }

    /// 将枚举值编码回 MIoT 接受的 JSON 基础类型。
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    /// 返回布尔值，类型不匹配时返回 nil。
    var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    /// 返回整数值，并兼容无小数部分的浮点数。
    var intValue: Int? {
        switch self {
        case let .int(value):
            return value
        case let .double(value):
            return Int(value)
        default:
            return nil
        }
    }
}

/// 单个 MIoT 属性参数。
nonisolated struct MiIOPropertyParameter: Encodable, Sendable {
    let did: String
    let siid: Int
    let piid: Int
    let value: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case did, siid, piid, value
    }

    /// 编码参数，并在读取属性时省略不存在的 value 字段。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(did, forKey: .did)
        try container.encode(siid, forKey: .siid)
        try container.encode(piid, forKey: .piid)
        try container.encodeIfPresent(value, forKey: .value)
    }
}

/// miIO 命令请求体。
nonisolated struct MiIORequest: Encodable, Sendable {
    let id: Int
    let method: String
    let params: [MiIOPropertyParameter]
}

/// MIoT 单个属性响应。
nonisolated struct MiIOPropertyResult: Decodable, Sendable {
    let did: String?
    let siid: Int?
    let piid: Int?
    let code: Int?
    let value: JSONValue?
}

/// miIO 错误响应。
nonisolated struct MiIOResponseError: Decodable, Sendable {
    let code: Int
    let message: String?
}

/// miIO 命令响应体。
nonisolated struct MiIOResponse: Decodable, Sendable {
    let id: Int?
    let result: [MiIOPropertyResult]?
    let error: MiIOResponseError?
}

/// 握手返回的设备标识和时钟。
nonisolated struct MiIOHandshake: Sendable {
    let deviceID: UInt32
    let timestamp: UInt32
    let receivedAt: Date
}
