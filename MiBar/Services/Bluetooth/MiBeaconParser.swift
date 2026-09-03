import Foundation
import OSLog

/// 小米 MiBeacon 协议与温湿度传感器数据解析器。
nonisolated enum MiBeaconParser {
    private static let logger = Logger(subsystem: "com.extrastu.mibar", category: "MiBeaconParser")

    /// 从任意 MiBeacon 广播帧中提取设备 MAC 地址与 ProductID（若数据帧包含 MAC）。
    static func extractDeviceInfo(from serviceData: Data) -> (mac: String, productID: UInt16)? {
        guard serviceData.count >= 11 else { return nil }
        let frameControl = UInt16(serviceData[0]) | (UInt16(serviceData[1]) << 8)
        let macInclude = (frameControl & (1 << 4)) != 0
        guard macInclude else { return nil }
        let productID = UInt16(serviceData[2]) | (UInt16(serviceData[3]) << 8)
        let macReversed = serviceData[5..<11]
        let macBytes = Array(macReversed.reversed())
        let macHex = macBytes.map { String(format: "%02X", $0) }.joined()
        return (macHex, productID)
    }

    /// 在已配置的多设备中查找匹配并解密 MiBeacon 载荷。
    ///
    /// - Parameters:
    ///   - serviceData: 0xFE95 广播数据
    ///   - candidateDevices: 待匹配的设备字典，Key 为 12 位规范化 MAC 地址，Value 为 16 字节 BindKey
    /// - Returns: 成功解析的设备 MAC 与读数
    static func parseMulti(
        serviceData: Data,
        candidateDevices: [String: Data]
    ) -> (mac: String, reading: ThermometerReading)? {
        guard !candidateDevices.isEmpty else { return nil }

        // 1. 如果数据帧自带 MAC，直接匹配该设备
        if let (packetMAC, _) = extractDeviceInfo(from: serviceData) {
            if let bindKey = candidateDevices[packetMAC],
               let (reading, _) = parse(serviceData: serviceData, expectedMAC: packetMAC, bindKey: bindKey) {
                return (packetMAC, reading)
            }
            return nil
        }

        // 2. 如果数据帧未带 MAC（如省电广播包），遍历所有候选设备尝试解密
        for (candidateMAC, bindKey) in candidateDevices {
            if let (reading, _) = parse(serviceData: serviceData, expectedMAC: candidateMAC, bindKey: bindKey) {
                return (candidateMAC, reading)
            }
        }
        return nil
    }

    /// 解析小米 BLE 广播中的 MiBeacon (0xFE95) 载荷。
    ///
    /// - Parameters:
    ///   - serviceData: 0xFE95 对应的原始数据
    ///   - expectedMAC: 期望匹配的目标设备 MAC（若提供，用于比对及在数据包未包含 MAC 时构造 Nonce）
    ///   - bindKey: 16 字节解密密钥
    /// - Returns: 解密并提取出的传感器读数。
    static func parse(
        serviceData: Data,
        expectedMAC: String?,
        bindKey: Data?
    ) -> (reading: ThermometerReading, packetMAC: String?)? {
        guard serviceData.count >= 5 else {
            Self.logger.debug("MiBeacon 数据长度过短（\(serviceData.count) 字节 < 5）")
            return nil
        }

        let frameControl = UInt16(serviceData[0]) | (UInt16(serviceData[1]) << 8)
        let isEncrypted = (frameControl & (1 << 3)) != 0
        let macInclude = (frameControl & (1 << 4)) != 0
        let capabilityInclude = (frameControl & (1 << 5)) != 0
        let objectInclude = (frameControl & (1 << 6)) != 0
        let isMesh = (frameControl & (1 << 7)) != 0
        let version = Int(frameControl >> 12)

        let productID = UInt16(serviceData[2]) | (UInt16(serviceData[3]) << 8)
        let productIDBytes = serviceData[2...3]
        let frameCounter = serviceData[4]

        // 仅处理 MiBeacon v2+ 非 Mesh 且含有测量对象的数据包
        guard !isMesh, version >= 2, objectInclude else {
            Self.logger.debug("忽略非目标数据包: isMesh=\(isMesh), ver=\(version), hasObject=\(objectInclude), productID=0x\(String(format: "%04X", productID))")
            return nil
        }

        var offset = 5
        var packetMACString: String?
        var macReversedData: Data?

        if macInclude {
            guard serviceData.count >= offset + 6 else {
                Self.logger.debug("数据包标记包含 MAC 但长度不足")
                return nil
            }
            let macReversed = serviceData[offset..<(offset + 6)]
            macReversedData = Data(macReversed)
            let macBytes = Array(macReversed.reversed())
            let macHex = macBytes.map { String(format: "%02X", $0) }.joined()
            packetMACString = macHex
            offset += 6

            // 如果指定了期望 MAC，进行严格比对
            if let expected = expectedMAC?.uppercased().filter({ ("0"..."9").contains($0) || ("A"..."F").contains($0) }),
               !expected.isEmpty,
               macHex != expected {
                Self.logger.debug("广播 MAC (\(macHex)) 与目标 MAC (\(expected)) 不匹配，跳过")
                return nil
            }
        } else if let expected = expectedMAC?.uppercased().filter({ ("0"..."9").contains($0) || ("A"..."F").contains($0) }),
                  expected.count == 12 {
            // 数据包本身未携带 MAC，使用配置的 MAC 地址计算反转字节构造 Nonce
            var bytes = [UInt8]()
            for i in stride(from: 0, to: 12, by: 2) {
                let start = expected.index(expected.startIndex, offsetBy: i)
                let end = expected.index(start, offsetBy: 2)
                if let b = UInt8(expected[start..<end], radix: 16) {
                    bytes.append(b)
                }
            }
            macReversedData = Data(bytes.reversed())
        }

        if capabilityInclude {
            guard serviceData.count >= offset + 1 else { return nil }
            let cap = serviceData[offset]
            offset += 1
            if (cap & 0x20) != 0 {
                guard serviceData.count >= offset + 1 else { return nil }
                offset += 1
            }
        }

        var plaintext: Data

        if isEncrypted {
            // 加密数据包必须有密钥与 MAC 用于构建 Nonce
            guard let key = bindKey, key.count == 16 else {
                Self.logger.warning("广播为加密模式，但未提供 16 字节 BindKey (keyCount=\(bindKey?.count ?? 0))")
                return nil
            }
            guard let macReversed = macReversedData, macReversed.count == 6 else {
                Self.logger.warning("无法构造解密 Nonce：缺少 MAC 地址")
                return nil
            }
            // 加密数据至少需要密文（>=1字节） + 3 字节计数器 + 4 字节 MIC
            guard serviceData.count >= offset + 7 else {
                Self.logger.debug("加密数据包长度异常（小于 offset+7）")
                return nil
            }

            let cipherEnd = serviceData.count - 7
            guard cipherEnd >= offset else { return nil }

            let ciphertext = serviceData[offset..<cipherEnd]
            let counter = serviceData[cipherEnd..<(serviceData.count - 4)]
            let tag = serviceData[(serviceData.count - 4)...]

            // 构造 12 字节 AES-CCM Nonce: macReversed(6) + productID(2) + frameCounter(1) + counter(3)
            var nonce = Data()
            nonce.append(macReversed)
            nonce.append(productIDBytes)
            nonce.append(frameCounter)
            nonce.append(counter)

            guard nonce.count == 12 else {
                Self.logger.error("Nonce 构造失败，长度=\(nonce.count) != 12")
                return nil
            }

            let aad = Data([0x11])
            guard let decrypted = AESCCM.decryptAndVerify(
                key: key,
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag,
                aad: aad
            ) else {
                let nonceHex = nonce.map { String(format: "%02X", $0) }.joined()
                let tagHex = tag.map { String(format: "%02X", $0) }.joined()
                Self.logger.error("❌ AES-CCM 解密验证失败：MIC 标签未匹配 (Nonce=\(nonceHex), Tag=\(tagHex))，请检查 BindKey 是否准确")
                return nil
            }
            plaintext = decrypted
            Self.logger.debug("🔓 广播解密成功，明文字节数=\(plaintext.count)")
        } else {
            guard serviceData.count > offset else { return nil }
            plaintext = serviceData[offset...]
        }

        // 解析 Payload 中的对象定义
        var temp: Double?
        var hum: Double?
        var bat: Int?

        var pOffset = plaintext.startIndex
        while pOffset + 3 <= plaintext.endIndex {
            let objID = UInt16(plaintext[pOffset]) | (UInt16(plaintext[pOffset + 1]) << 8)
            let objLen = Int(plaintext[pOffset + 2])
            pOffset += 3

            guard pOffset + objLen <= plaintext.endIndex else { break }
            let val = plaintext[pOffset..<(pOffset + objLen)]
            pOffset += objLen

            switch objID {
            case 0x1004, 0x4801, 0x4C01: // 温度
                if val.count >= 4 {
                    let u32 = UInt32(val[val.startIndex]) | (UInt32(val[val.startIndex + 1]) << 8) | (UInt32(val[val.startIndex + 2]) << 16) | (UInt32(val[val.startIndex + 3]) << 24)
                    temp = Double(Float(bitPattern: u32))
                    Self.logger.debug("📊 解析到温度对象 0x\(String(format: "%04X", objID)): \(temp ?? 0)°C (4B float)")
                } else if val.count >= 2 {
                    let raw = Int16(bitPattern: UInt16(val[val.startIndex]) | (UInt16(val[val.startIndex + 1]) << 8))
                    temp = Double(raw) / 10.0
                    Self.logger.debug("📊 解析到温度对象 0x\(String(format: "%04X", objID)): \(temp ?? 0)°C (2B int)")
                }
            case 0x1006, 0x4802, 0x4C02: // 湿度
                if val.count == 1 {
                    hum = Double(val[val.startIndex])
                    Self.logger.debug("📊 解析到湿度对象 0x\(String(format: "%04X", objID)): \(hum ?? 0)% (1B)")
                } else if val.count >= 2 {
                    let raw = UInt16(val[val.startIndex]) | (UInt16(val[val.startIndex + 1]) << 8)
                    hum = Double(raw) / 10.0
                    Self.logger.debug("📊 解析到湿度对象 0x\(String(format: "%04X", objID)): \(hum ?? 0)% (2B)")
                }
            case 0x100D, 0x4804, 0x4C08: // 复合温湿度
                if val.count >= 4 {
                    let rawT = Int16(bitPattern: UInt16(val[val.startIndex]) | (UInt16(val[val.startIndex + 1]) << 8))
                    let rawH = UInt16(val[val.startIndex + 2]) | (UInt16(val[val.startIndex + 3]) << 8)
                    temp = Double(rawT) / 10.0
                    hum = Double(rawH) / 10.0
                    Self.logger.debug("📊 解析到复合温湿度对象 0x\(String(format: "%04X", objID)): \(temp ?? 0)°C, \(hum ?? 0)%")
                }
            case 0x100A, 0x4803, 0x4C03: // 电池电量 (1 byte, %)
                if let first = val.first {
                    bat = Int(first)
                    Self.logger.debug("📊 解析到电池电量对象 0x\(String(format: "%04X", objID)): \(bat ?? 0)%")
                }
            default:
                Self.logger.debug("📊 遇到未处理的 MiBeacon 对象: 0x\(String(format: "%04X", objID)), 长度=\(objLen)")
            }
        }

        // 只要解析到了温度、湿度或电量中的任意一个，就构成有效读数
        guard temp != nil || hum != nil || bat != nil else {
            Self.logger.debug("数据包未包含任何已知的传感器数值")
            return nil
        }

        let reading = ThermometerReading(
            temperature: temp,
            humidity: hum,
            battery: bat,
            timestamp: Date()
        )
        Self.logger.info("✅ 成功解析数据包: 温度=\(reading.temperatureString), 湿度=\(reading.humidityString), 电量=\(bat.map { "\($0)%" } ?? "无")")
        return (reading, packetMACString)
    }
}
