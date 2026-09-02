import CryptoKit
import Foundation
import Security

enum XiaomiCloudCryptoError: LocalizedError {
    case invalidBase64
    case invalidEndpoint
    case randomGenerationFailed(OSStatus)

    /// 返回适合界面展示的云端签名错误说明。
    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "小米云返回了无效的登录密钥"
        case .invalidEndpoint:
            return "无法生成小米云请求签名"
        case let .randomGenerationFailed(status):
            return "无法生成安全随机数（\(status)）"
        }
    }
}

enum XiaomiCloudCrypto {
    /// 执行小米云使用的 RC4-drop1024 对称变换。
    static func rc4(key: Data, data: Data) -> Data {
        guard !key.isEmpty else { return Data() }
        var state = Array(0...255)
        let keyBytes = [UInt8](key)
        var j = 0
        for i in 0..<256 {
            j = (j + state[i] + Int(keyBytes[i % keyBytes.count])) & 0xff
            state.swapAt(i, j)
        }

        var i = 0
        j = 0
        var output: [UInt8] = []
        output.reserveCapacity(data.count)
        let source = [UInt8](repeating: 0, count: 1_024) + [UInt8](data)
        for (offset, byte) in source.enumerated() {
            i = (i + 1) & 0xff
            j = (j + state[i]) & 0xff
            state.swapAt(i, j)
            let transformed = byte ^ UInt8(state[(state[i] + state[j]) & 0xff])
            if offset >= 1_024 { output.append(transformed) }
        }
        return Data(output)
    }

    /// 将 ssecurity 与 nonce 合并为请求使用的 signed nonce。
    static func signedNonce(ssecurity: String, nonce: String) throws -> String {
        guard let securityData = Data(base64Encoded: ssecurity),
              let nonceData = Data(base64Encoded: nonce)
        else {
            throw XiaomiCloudCryptoError.invalidBase64
        }
        return Data(SHA256.hash(data: securityData + nonceData)).base64EncodedString()
    }

    /// 生成 8 字节随机数加 4 字节分钟计数器组成的 nonce。
    static func nonce(now: Date = Date()) throws -> String {
        var random = [UInt8](repeating: 0, count: 8)
        let status = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        guard status == errSecSuccess else {
            throw XiaomiCloudCryptoError.randomGenerationFailed(status)
        }
        let minutes = UInt32(now.timeIntervalSince1970 / 60)
        var value = Data(random)
        value.appendBigEndian(minutes)
        return value.base64EncodedString()
    }

    /// 按字段顺序生成小米云 SHA-1 请求签名。
    static func signature(url: URL, signedNonce: String, fields: [(String, String)]) throws -> String {
        guard let markerRange = url.absoluteString.range(of: "/app/") else {
            throw XiaomiCloudCryptoError.invalidEndpoint
        }
        let suffix = url.absoluteString[markerRange.upperBound...]
        var parts = ["POST", "/\(suffix)"]
        parts.append(contentsOf: fields.map { "\($0.0)=\($0.1)" })
        parts.append(signedNonce)
        return Data(Insecure.SHA1.hash(data: Data(parts.joined(separator: "&").utf8))).base64EncodedString()
    }

    /// 使用 signed nonce 加密并进行 Base64 编码。
    static func seal(signedNonce: String, text: String) throws -> String {
        guard let key = Data(base64Encoded: signedNonce) else {
            throw XiaomiCloudCryptoError.invalidBase64
        }
        return rc4(key: key, data: Data(text.utf8)).base64EncodedString()
    }

    /// 对 Base64 响应执行 RC4 解密。
    static func unseal(signedNonce: String, text: String) throws -> Data {
        guard let key = Data(base64Encoded: signedNonce),
              let ciphertext = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw XiaomiCloudCryptoError.invalidBase64
        }
        return rc4(key: key, data: ciphertext)
    }

    /// application/x-www-form-urlencoded 中无需编码的字符，对齐 Python urllib.parse.quote。
    private static let formUnreservedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// 编码单个表单键或值，确保 Base64 里的 + / = 都变成百分号编码。
    private static func formEncodedComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: formUnreservedCharacters) ?? value
    }

    /// 按小米接口要求将字段编码成有序的 application/x-www-form-urlencoded 请求体。
    /// URLComponents 不会编码 +，小米服务端会把 + 当成空格，从而报 invalid signature。
    static func formEncodedData(_ fields: [(String, String)]) -> Data? {
        let query = fields.map { name, value in
            "\(formEncodedComponent(name))=\(formEncodedComponent(value))"
        }.joined(separator: "&")
        return query.data(using: .utf8)
    }
}
