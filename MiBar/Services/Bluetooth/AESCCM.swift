import Foundation
import CommonCrypto

/// 遵循 NIST SP 800-38C 与 RFC 3610 标准的 AES-CCM 认证解密器。
nonisolated enum AESCCM {
    /// 执行 AES-128 单块加密（ECB 模式）。
    private static func aes128Encrypt(block: [UInt8], key: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        var numBytes = 0
        _ = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES128),
            CCOptions(kCCOptionECBMode),
            key, key.count,
            nil,
            block, 16,
            &out, 16,
            &numBytes
        )
        return out
    }

    /// 使用 AES-CCM 解密密文并校验认证标签（MIC）。
    ///
    /// - Parameters:
    ///   - key: 16 字节（128 位）AES 密钥
    ///   - nonce: 7 到 13 字节的 Nonce（对于 MiBeacon v4/v5 为 12 字节）
    ///   - ciphertext: 加密的有效载荷
    ///   - tag: 认证标签（MIC），长度通常为 4、6、8 等偶数字节
    ///   - aad: 附加认证数据（Additional Authenticated Data，MiBeacon 通常为 0x11）
    /// - Returns: 解密后的明文数据；若标签校验失败或参数不合法则返回 nil。
    static func decryptAndVerify(
        key: [UInt8],
        nonce: [UInt8],
        ciphertext: [UInt8],
        tag: [UInt8],
        aad: [UInt8]
    ) -> [UInt8]? {
        guard key.count == 16 else { return nil }
        let q = 15 - nonce.count
        guard q >= 2 && q <= 8 else { return nil }
        let t = tag.count
        guard [4, 6, 8, 10, 12, 14, 16].contains(t) else { return nil }

        // 1. CTR 模式解密密文获取明文
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count)
        let numBlocks = (ciphertext.count + 15) / 16
        if numBlocks > 0 {
            for i in 1...numBlocks {
                var aBlock = [UInt8](repeating: 0, count: 16)
                aBlock[0] = UInt8(q - 1)
                for j in 0..<nonce.count {
                    aBlock[1 + j] = nonce[j]
                }
                let temp = i
                for j in (0..<q).reversed() {
                    aBlock[16 - 1 - j] = UInt8((temp >> (j * 8)) & 0xff)
                }
                let s = aes128Encrypt(block: aBlock, key: key)
                let start = (i - 1) * 16
                let end = min(start + 16, ciphertext.count)
                if start < ciphertext.count {
                    for k in start..<end {
                        plaintext[k] = ciphertext[k] ^ s[k - start]
                    }
                }
            }
        }

        // 2. CBC-MAC 校验标签计算
        var b0 = [UInt8](repeating: 0, count: 16)
        let hasAad = !aad.isEmpty
        let flags = (hasAad ? 0x40 : 0) | (((t - 2) / 2) << 3) | (q - 1)
        b0[0] = UInt8(flags)
        for j in 0..<nonce.count {
            b0[1 + j] = nonce[j]
        }
        let pLen = plaintext.count
        for j in (0..<q).reversed() {
            b0[16 - 1 - j] = UInt8((pLen >> (j * 8)) & 0xff)
        }

        var y = aes128Encrypt(block: b0, key: key)

        // 处理 AAD
        if hasAad {
            var aadData = [UInt8]()
            if aad.count < 0xff00 {
                aadData.append(UInt8((aad.count >> 8) & 0xff))
                aadData.append(UInt8(aad.count & 0xff))
            } else {
                aadData.append(0xff)
                aadData.append(0xfe)
                aadData.append(UInt8((aad.count >> 24) & 0xff))
                aadData.append(UInt8((aad.count >> 16) & 0xff))
                aadData.append(UInt8((aad.count >> 8) & 0xff))
                aadData.append(UInt8(aad.count & 0xff))
            }
            aadData.append(contentsOf: aad)
            while aadData.count % 16 != 0 {
                aadData.append(0)
            }
            for blk in 0..<(aadData.count / 16) {
                var block = [UInt8](repeating: 0, count: 16)
                for k in 0..<16 {
                    block[k] = y[k] ^ aadData[blk * 16 + k]
                }
                y = aes128Encrypt(block: block, key: key)
            }
        }

        // 处理 Plaintext
        var pData = plaintext
        while pData.count % 16 != 0 {
            pData.append(0)
        }
        if !pData.isEmpty {
            for blk in 0..<(pData.count / 16) {
                var block = [UInt8](repeating: 0, count: 16)
                for k in 0..<16 {
                    block[k] = y[k] ^ pData[blk * 16 + k]
                }
                y = aes128Encrypt(block: block, key: key)
            }
        }

        // 3. 计算预期的加密 Tag (S0 ^ Y)
        var a0 = [UInt8](repeating: 0, count: 16)
        a0[0] = UInt8(q - 1)
        for j in 0..<nonce.count {
            a0[1 + j] = nonce[j]
        }
        let s0 = aes128Encrypt(block: a0, key: key)
        var expectedTag = [UInt8](repeating: 0, count: t)
        for k in 0..<t {
            expectedTag[k] = y[k] ^ s0[k]
        }

        guard expectedTag == tag else { return nil }
        return plaintext
    }

    /// Data 版本的便捷解密方法。
    static func decryptAndVerify(
        key: Data,
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        aad: Data
    ) -> Data? {
        guard let decrypted = decryptAndVerify(
            key: Array(key),
            nonce: Array(nonce),
            ciphertext: Array(ciphertext),
            tag: Array(tag),
            aad: Array(aad)
        ) else {
            return nil
        }
        return Data(decrypted)
    }
}
