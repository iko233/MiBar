import Foundation

/// 小米二维码登录挑战。
nonisolated struct XiaomiQRChallenge: Sendable {
    let imageData: Data
    let loginURL: URL
    let pollingURL: URL
    let timeout: TimeInterval
}

/// 小米云短期登录会话，仅在内存中使用。
nonisolated struct XiaomiCloudSession: Sendable {
    let userID: String
    let ssecurity: String
    let serviceToken: String
}

/// 小米云设备列表中的必要字段。
nonisolated struct XiaomiCloudDevice: Decodable, Sendable, Identifiable, Equatable {
    let did: String
    let name: String
    let model: String
    let token: String
    let localIP: String
    let mac: String?

    var id: String { did }

    private enum CodingKeys: String, CodingKey {
        case did, name, model, token, mac
        case localIP = "localip"
        case localIp
        case ip
    }

    /// 供测试和云端导入直接构造设备记录。
    init(did: String, name: String, model: String, token: String, localIP: String, mac: String? = nil) {
        self.did = did
        self.name = name
        self.model = model
        self.token = token
        self.localIP = localIP
        self.mac = mac
    }

    /// 兼容 did 为数字、localip 为 null，以及 localIp / ip 两种字段名。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        did = Self.decodeFlexibleString(from: container, key: .did, fallback: "")
        guard !did.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .did,
                in: container,
                debugDescription: "设备缺少 did"
            )
        }
        name = Self.decodeFlexibleString(from: container, key: .name, fallback: did)
        model = Self.decodeFlexibleString(from: container, key: .model, fallback: "")
        token = Self.decodeFlexibleString(from: container, key: .token, fallback: "")
        mac = Self.decodeOptionalString(from: container, key: .mac)
        localIP = Self.decodeLocalIP(from: container)
    }

    /// 按优先级读取局域网 IP，忽略 JSON null 和空字符串。
    private static func decodeLocalIP(from container: KeyedDecodingContainer<CodingKeys>) -> String {
        for key in [CodingKeys.localIP, .localIp, .ip] {
            let value = decodeFlexibleString(from: container, key: key, fallback: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return ""
    }

    /// 将字符串或整数 JSON 字段读成字符串，缺失和 null 时返回兜底值。
    private static func decodeFlexibleString(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys,
        fallback: String
    ) -> String {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return String(value)
        }
        return fallback
    }

    /// 读取可选字符串，把 JSON null 当成缺失。
    private static func decodeOptionalString(
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        let value = try? container.decode(String.self, forKey: key)
        return value?.isEmpty == false ? value : nil
    }
}

/// 小米二维码端点返回的挑战信息。
nonisolated struct XiaomiQRPayload: Decodable, Sendable {
    let qr: URL
    let loginURL: URL
    let pollingURL: URL
    let timeout: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case qr, timeout
        case loginURL = "loginUrl"
        case pollingURL = "lp"
    }
}

/// 扫码确认后返回的账户会话字段。
nonisolated struct XiaomiAuthorizationPayload: Decodable, Sendable {
    let userID: String
    let ssecurity: String
    let location: URL

    private enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case ssecurity, location
    }

    /// 兼容小米将 userId 返回为数字或字符串的两种响应格式。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringValue = try? container.decode(String.self, forKey: .userID) {
            userID = stringValue
        } else {
            userID = String(try container.decode(Int64.self, forKey: .userID))
        }
        ssecurity = try container.decode(String.self, forKey: .ssecurity)
        location = try container.decode(URL.self, forKey: .location)
    }
}

/// 小米设备列表响应的最小结构。
nonisolated struct XiaomiDeviceListEnvelope: Decodable, Sendable {
    let result: ResultPayload?

    /// 小米设备列表响应中的 result。
    nonisolated struct ResultPayload: Decodable, Sendable {
        let list: [XiaomiCloudDevice]?
    }
}
