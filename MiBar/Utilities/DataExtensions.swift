import Foundation

extension Data {
    /// 从偶数长度的十六进制字符串创建二进制数据。
    init?(hexString: String) {
        let normalized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }
        self.init(bytes)
    }

    /// 将二进制数据输出为小写十六进制字符串。
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// 追加一个大端序 16 位整数。
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    /// 追加一个大端序 32 位整数。
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    /// 从指定位置读取大端序 16 位整数。
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, count >= offset + 2 else { return nil }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    /// 从指定位置读取大端序 32 位整数。
    func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, count >= offset + 4 else { return nil }
        return (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}
