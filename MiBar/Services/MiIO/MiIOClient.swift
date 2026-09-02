import Foundation
import os.log

private let logger = Logger(subsystem: "MiBar", category: "MiIOClient")

nonisolated enum MiIOClientError: LocalizedError, Sendable {
    case commandFailed(code: Int, message: String?)
    case propertyMissing(String)

    /// 返回适合界面展示的设备命令错误说明。
    var errorDescription: String? {
        switch self {
        case let .commandFailed(code, message):
            return "挂灯拒绝了命令（\(code)）\(message.map { "：\($0)" } ?? "")"
        case let .propertyMissing(name):
            return "响应缺少属性：\(name)"
        }
    }
}

actor MiIOClient {
    private let host: String
    private let token: Data
    private var handshake: MiIOHandshake?
    private var requestID = Int.random(in: 1...9_000)

    /// 创建一个固定目标 IP 和设备 token 的本地 miIO 客户端。
    init(host: String, tokenHex: String) throws {
        guard let token = Data(hexString: tokenHex), token.count == 16 else {
            logger.error("❌ [MiIOClient] 初始化失败: Token 无效（需为 32 位十六进制字符串）")
            throw MiIOCryptoError.invalidToken
        }
        self.host = host
        self.token = token
        logger.info("📱 [MiIOClient] 已配置目标挂灯: IP=\(host), Token=\(tokenHex.prefix(6))...\(tokenHex.suffix(4))")
    }

    /// 读取挂灯开关、亮度和色温。
    func getState() async throws -> LightState {
        logger.debug("🔄 [MiIOClient] 正在获取挂灯状态 (get_properties)...")
        let response = try await send(
            method: "get_properties",
            params: [
                .init(did: "power", siid: 2, piid: 1, value: nil),
                .init(did: "brightness", siid: 2, piid: 2, value: nil),
                .init(did: "color-temperature", siid: 2, piid: 3, value: nil),
            ]
        )
        let isOn = try propertyValue(in: response, siid: 2, piid: 1, name: "开关").boolValue
        let brightness = try propertyValue(in: response, siid: 2, piid: 2, name: "亮度").intValue
        let colorTemperature = try propertyValue(in: response, siid: 2, piid: 3, name: "色温").intValue
        guard let isOn, let brightness, let colorTemperature else {
            logger.error("❌ [MiIOClient] 属性类型不匹配: isOn=\(String(describing: isOn)), brightness=\(String(describing: brightness)), colorTemp=\(String(describing: colorTemperature))")
            throw MiIOClientError.propertyMissing("状态类型不匹配")
        }
        let state = LightState(
            isOn: isOn,
            brightness: min(max(brightness, 1), 100),
            colorTemperature: min(max(colorTemperature, 2_700), 6_500)
        )
        logger.info("💡 [MiIOClient] 成功获取状态: 电源=\(state.isOn ? "开" : "关"), 亮度=\(state.brightness)%, 色温=\(state.colorTemperature)K")
        return state
    }

    /// 设置挂灯电源状态。
    func setPower(_ isOn: Bool) async throws {
        logger.info("⚡️ [MiIOClient] 设置电源: \(isOn ? "开启" : "关闭")")
        _ = try await setProperty(did: "set-power", piid: 1, value: .bool(isOn))
    }

    /// 设置 1 到 100 的挂灯亮度。
    func setBrightness(_ brightness: Int) async throws {
        let clamped = min(max(brightness, 1), 100)
        logger.info("☀️ [MiIOClient] 设置亮度: \(clamped)%")
        _ = try await setProperty(did: "set-brightness", piid: 2, value: .int(clamped))
    }

    /// 设置 2700K 到 6500K 的挂灯色温。
    func setColorTemperature(_ temperature: Int) async throws {
        let clamped = min(max(temperature, 2_700), 6_500)
        logger.info("🌡️ [MiIOClient] 设置色温: \(clamped)K")
        _ = try await setProperty(
            did: "set-color-temperature",
            piid: 3,
            value: .int(clamped)
        )
    }

    /// 写入 light 服务中的一个属性并验证设备返回码。
    @discardableResult
    private func setProperty(did: String, piid: Int, value: JSONValue) async throws -> MiIOResponse {
        let response = try await send(
            method: "set_properties",
            params: [.init(did: did, siid: 2, piid: piid, value: value)]
        )
        guard let result = response.result?.first else {
            logger.error("❌ [MiIOClient] 写入属性 \(did) 失败: 响应缺少 result")
            throw MiIOClientError.propertyMissing(did)
        }
        guard result.code == 0 else {
            let code = result.code ?? -1
            logger.error("❌ [MiIOClient] 写入属性 \(did) 被设备拒绝，错误代码: \(code)")
            throw MiIOClientError.commandFailed(code: code, message: nil)
        }
        return response
    }

    /// 发送命令；首次失败时重新握手并仅重试一次。
    private func send(method: String, params: [MiIOPropertyParameter]) async throws -> MiIOResponse {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let activeHandshake = try await ensureHandshake(force: attempt > 0)
                let reqID = nextRequestID()
                let request = MiIORequest(id: reqID, method: method, params: params)
                let payload = try JSONEncoder().encode(request)
                let elapsed = max(0, Date().timeIntervalSince(activeHandshake.receivedAt))
                let timestamp = activeHandshake.timestamp &+ UInt32(elapsed.rounded(.down)) &+ 1
                let packet = try MiIOPacket.buildCommand(
                    payload: payload,
                    token: token,
                    deviceID: activeHandshake.deviceID,
                    timestamp: timestamp
                )
                logger.debug("📤 [MiIOClient] 发送命令 (尝试 \(attempt + 1)): method=\(method), reqID=\(reqID), devID=\(activeHandshake.deviceID)")
                let responseData = try await DatagramTransport.exchange(packet, host: host)
                let response = try MiIOPacket.parseResponse(responseData, token: token)
                if let error = response.error {
                    logger.error("❌ [MiIOClient] 设备返回错误: code=\(error.code), msg=\(error.message ?? "")")
                    throw MiIOClientError.commandFailed(code: error.code, message: error.message)
                }
                logger.debug("📥 [MiIOClient] 成功收到命令响应: method=\(method)")
                return response
            } catch {
                lastError = error
                logger.warning("⚠️ [MiIOClient] 命令发送失败 (尝试 \(attempt + 1)): \(error.localizedDescription)")
                handshake = nil
            }
        }
        throw lastError ?? DatagramTransportError.timeout
    }

    /// 获取近期握手信息，超过 30 秒或强制刷新时重新握手。
    private func ensureHandshake(force: Bool) async throws -> MiIOHandshake {
        if !force,
           let handshake,
           Date().timeIntervalSince(handshake.receivedAt) < 30 {
            return handshake
        }
        logger.debug("🤝 [MiIOClient] 发起 UDP Hello 握手 -> \(self.host)")
        let data = try await DatagramTransport.exchange(MiIOPacket.hello, host: host)
        let freshHandshake = try MiIOPacket.parseHandshake(data)
        handshake = freshHandshake
        logger.info("🤝 [MiIOClient] 握手成功! deviceID=\(freshHandshake.deviceID), timestamp=\(freshHandshake.timestamp)")
        return freshHandshake
    }


    /// 生成 1 到 9999 循环使用的请求序号。
    private func nextRequestID() -> Int {
        requestID += 1
        if requestID >= 9_999 { requestID = 1 }
        return requestID
    }

    /// 从响应中找到指定 MIoT 属性并检查单项返回码。
    private func propertyValue(
        in response: MiIOResponse,
        siid: Int,
        piid: Int,
        name: String
    ) throws -> JSONValue {
        guard let result = response.result?.first(where: { $0.siid == siid && $0.piid == piid }) else {
            throw MiIOClientError.propertyMissing(name)
        }
        guard result.code == 0 else {
            throw MiIOClientError.commandFailed(code: result.code ?? -1, message: nil)
        }
        guard let value = result.value else {
            throw MiIOClientError.propertyMissing(name)
        }
        return value
    }
}
