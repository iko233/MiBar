import CommonCrypto
import CryptoKit
import Foundation

nonisolated enum MiIOCryptoError: LocalizedError, Sendable {
    case invalidToken
    case cryptFailed(CCCryptorStatus)

    /// 返回适合界面展示的加解密错误说明。
    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "设备 token 必须是 32 位十六进制字符串"
        case let .cryptFailed(status):
            return "miIO 加解密失败（\(status)）"
        }
    }
}

nonisolated enum MiIOCrypto {
    /// 计算 miIO 校验和及密钥派生所需的 MD5。
    static func md5(_ data: Data) -> Data {
        Data(Insecure.MD5.hash(data: data))
    }

    /// 根据 16 字节设备 token 派生 AES 密钥和 IV。
    static func keyAndIV(token: Data) throws -> (key: Data, iv: Data) {
        guard token.count == 16 else { throw MiIOCryptoError.invalidToken }
        let key = md5(token)
        return (key, md5(key + token))
    }

    /// 使用 miIO 的 AES-128-CBC + PKCS#7 规则加密负载。
    static func encrypt(_ plaintext: Data, token: Data) throws -> Data {
        let material = try keyAndIV(token: token)
        return try crypt(operation: CCOperation(kCCEncrypt), input: plaintext, key: material.key, iv: material.iv)
    }

    /// 使用 miIO 的 AES-128-CBC + PKCS#7 规则解密负载。
    static func decrypt(_ ciphertext: Data, token: Data) throws -> Data {
        let material = try keyAndIV(token: token)
        return try crypt(operation: CCOperation(kCCDecrypt), input: ciphertext, key: material.key, iv: material.iv)
    }

    /// 调用 CommonCrypto 完成一次 AES-CBC 运算。
    private static func crypt(operation: CCOperation, input: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBuffer in
            input.withUnsafeBytes { inputBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            kCCKeySizeAES128,
                            ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            inputBuffer.count,
                            outputBuffer.baseAddress,
                            outputBuffer.count,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw MiIOCryptoError.cryptFailed(status) }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}
