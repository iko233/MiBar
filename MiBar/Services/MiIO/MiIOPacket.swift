import Foundation

enum MiIOPacketError: LocalizedError {
    case malformedPacket
    case invalidChecksum
    case invalidResponse

    /// 返回适合界面展示的数据包错误说明。
    var errorDescription: String? {
        switch self {
        case .malformedPacket:
            return "挂灯返回了无效的 miIO 数据包"
        case .invalidChecksum:
            return "响应校验失败，请检查设备 token"
        case .invalidResponse:
            return "无法解析挂灯响应"
        }
    }
}

enum MiIOPacket {
    static let hello = Data(hexString: "21310020ffffffffffffffffffffffffffffffffffffffffffffffffffffffff")!

    /// 解析 32 字节握手响应中的设备 ID 和设备时间。
    static func parseHandshake(_ data: Data, receivedAt: Date = Date()) throws -> MiIOHandshake {
        guard data.count >= 32,
              data.readUInt16(at: 0) == 0x2131,
              data.readUInt16(at: 2) == 32,
              let deviceID = data.readUInt32(at: 8),
              let timestamp = data.readUInt32(at: 12)
        else {
            throw MiIOPacketError.malformedPacket
        }
        return MiIOHandshake(deviceID: deviceID, timestamp: timestamp, receivedAt: receivedAt)
    }

    /// 生成带校验和与加密负载的 miIO 命令数据包。
    static func buildCommand(payload: Data, token: Data, deviceID: UInt32, timestamp: UInt32) throws -> Data {
        var terminatedPayload = payload
        terminatedPayload.append(0)
        let encrypted = try MiIOCrypto.encrypt(terminatedPayload, token: token)
        guard encrypted.count <= Int(UInt16.max) - 32 else { throw MiIOPacketError.malformedPacket }

        var header = Data()
        header.appendBigEndian(UInt16(0x2131))
        header.appendBigEndian(UInt16(32 + encrypted.count))
        header.appendBigEndian(UInt32(0))
        header.appendBigEndian(deviceID)
        header.appendBigEndian(timestamp)

        let checksum = MiIOCrypto.md5(header + token + encrypted)
        return header + checksum + encrypted
    }

    /// 校验、解密并解析 miIO 命令响应。
    static func parseResponse(_ data: Data, token: Data) throws -> MiIOResponse {
        guard data.count >= 32,
              data.readUInt16(at: 0) == 0x2131,
              let declaredLength = data.readUInt16(at: 2),
              Int(declaredLength) == data.count
        else {
            throw MiIOPacketError.malformedPacket
        }

        let header = data.subdata(in: 0..<16)
        let receivedChecksum = data.subdata(in: 16..<32)
        let encrypted = data.subdata(in: 32..<data.count)
        guard MiIOCrypto.md5(header + token + encrypted) == receivedChecksum else {
            throw MiIOPacketError.invalidChecksum
        }

        var plaintext = try MiIOCrypto.decrypt(encrypted, token: token)
        while plaintext.last == 0 { plaintext.removeLast() }
        do {
            return try JSONDecoder().decode(MiIOResponse.self, from: plaintext)
        } catch {
            throw MiIOPacketError.invalidResponse
        }
    }
}
