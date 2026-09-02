import Darwin
import Foundation
import os.log

private let logger = Logger(subsystem: "MiBar", category: "DatagramTransport")

enum DatagramTransportError: LocalizedError {
    case invalidAddress
    case socketFailure(String)
    case timeout

    /// 返回适合界面展示的 UDP 通信错误说明。
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "请输入有效的 IPv4 地址"
        case let .socketFailure(message):
            return "局域网通信失败：\(message)"
        case .timeout:
            return "挂灯没有响应，请检查 IP、token 和同一局域网"
        }
    }
}

enum DatagramTransport {
    /// 在后台线程执行一次 UDP 请求并等待单个响应。
    static func exchange(_ payload: Data, host: String, port: UInt16 = 54_321, timeout: TimeInterval = 3) async throws -> Data {
        logger.debug("🌐 [UDP] 准备发送数据到 \(host):\(port)，字节数: \(payload.count)")
        return try await Task.detached(priority: .userInitiated) {
            try exchangeBlocking(payload, host: host, port: port, timeout: timeout)
        }.value
    }

    /// 使用 POSIX socket 执行带接收超时的 UDP 往返。
    private static func exchangeBlocking(_ payload: Data, host: String, port: UInt16, timeout: TimeInterval) throws -> Data {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else {
            let err = socketError()
            logger.error("❌ [UDP] Socket 创建失败: \(err.localizedDescription)")
            throw err
        }
        defer { close(descriptor) }

        var receiveTimeout = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            let err = socketError()
            logger.error("❌ [UDP] 设置 SO_RCVTIMEO 失败: \(err.localizedDescription)")
            throw err
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard host.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            logger.error("❌ [UDP] 无效的目标 IPv4 地址: \(host)")
            throw DatagramTransportError.invalidAddress
        }

        let sent = payload.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        descriptor,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        guard sent == payload.count else {
            let err = socketError()
            logger.error("❌ [UDP] 发送失败，已发送 \(sent)/\(payload.count): \(err.localizedDescription)")
            throw err
        }

        var buffer = [UInt8](repeating: 0, count: 4_096)
        let received = recv(descriptor, &buffer, buffer.count, 0)
        if received < 0, errno == EAGAIN || errno == EWOULDBLOCK {
            logger.warning("⏱️ [UDP] 接收超时 (超过 \(timeout)s)，目标: \(host):\(port)")
            throw DatagramTransportError.timeout
        }
        guard received >= 0 else {
            let err = socketError()
            logger.error("❌ [UDP] 接收数据失败: \(err.localizedDescription)")
            throw err
        }
        logger.debug("✅ [UDP] 成功从 \(host) 收到 \(received) 字节响应")
        return Data(buffer.prefix(received))
    }

    /// 将当前 errno 转换为可读的 socket 错误。
    private static func socketError() -> DatagramTransportError {
        DatagramTransportError.socketFailure(String(cString: strerror(errno)))
    }
}

