import Foundation
import OSLog

nonisolated enum XiaomiCloudError: LocalizedError, Sendable {
    case invalidResponse(String)
    case httpFailure(Int)
    case qrExpired
    case loginCancelled
    case missingServiceToken
    case deviceNotFound

    /// 返回适合界面展示的小米云错误说明。
    var errorDescription: String? {
        switch self {
        case let .invalidResponse(message):
            return "小米云响应异常：\(message)"
        case let .httpFailure(status):
            return "小米云请求失败（HTTP \(status)）"
        case .qrExpired:
            return "二维码已过期，请重新扫码"
        case .loginCancelled:
            return "扫码登录已取消"
        case .missingServiceToken:
            return "小米云没有返回登录凭据"
        case .deviceNotFound:
            return "账号中没有找到米家智能显示器挂灯 1S"
        }
    }
}

actor XiaomiCloudClient {
    private static let loginEndpoint = URL(string: "https://account.xiaomi.com/longPolling/loginUrl")!
    private static let logger = Logger(subsystem: "com.extrastu.mibar", category: "XiaomiCloud")
    private let session: URLSession
    private let deviceListEndpoint: URL
    private let userAgent: String

    /// 创建只在内存中保存 Cookie 和登录会话的客户端，并允许测试注入会话和设备端点。
    init(
        session injectedSession: URLSession? = nil,
        deviceListEndpoint: URL = URL(string: "https://api.io.mi.com/app/home/device_list")!
    ) {
        self.deviceListEndpoint = deviceListEndpoint
        if let injectedSession {
            session = injectedSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = true
            configuration.httpCookieAcceptPolicy = .always
            configuration.timeoutIntervalForRequest = 25
            session = URLSession(configuration: configuration)
        }
        userAgent = Self.makeUserAgent()
    }

    /// 请求二维码图片、登录链接和轮询地址。
    func requestChallenge() async throws -> XiaomiQRChallenge {
        var components = URLComponents(url: Self.loginEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "_qrsize", value: "480"),
            .init(name: "qs", value: "%3Fsid%3Dxiaomiio%26_json%3Dtrue"),
            .init(name: "callback", value: "https://sts.api.io.mi.com/sts"),
            .init(name: "_hasLogo", value: "false"),
            .init(name: "sid", value: "xiaomiio"),
            .init(name: "serviceParam", value: ""),
            .init(name: "_locale", value: "en_GB"),
            .init(name: "_dc", value: String(Int(Date().timeIntervalSince1970 * 1_000))),
        ]
        guard let url = components.url else {
            throw XiaomiCloudError.invalidResponse("二维码地址无效")
        }

        Self.logger.info("二维码申请开始，URL=\(Self.redactedURL(url), privacy: .public)")

        let payload: XiaomiQRPayload = try await guardedJSON(from: url)
        let (imageData, response) = try await session.data(from: payload.qr)
        try validate(response)
        Self.logger.info("二维码图片获取成功，host=\(payload.qr.host ?? "-", privacy: .public)，bytes=\(imageData.count, privacy: .public)")
        Self.logger.info("登录地址 host=\(payload.loginURL.host ?? "-", privacy: .public)，轮询地址 host=\(payload.pollingURL.host ?? "-", privacy: .public)，timeout=\(payload.timeout ?? 300, privacy: .public)")
        return XiaomiQRChallenge(
            imageData: imageData,
            loginURL: payload.loginURL,
            pollingURL: payload.pollingURL,
            timeout: payload.timeout ?? 300
        )
    }

    /// 等待用户在米家 App 中确认二维码并换取短期云会话。
    func waitForAuthorization(_ challenge: XiaomiQRChallenge) async throws -> XiaomiCloudSession {
        let deadline = Date().addingTimeInterval(challenge.timeout)
        var pollCount = 0
        var lastStatus: Int?
        Self.logger.info("二维码授权轮询开始，URL=\(Self.redactedURL(challenge.pollingURL), privacy: .public)")
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: challenge.pollingURL)
                request.timeoutInterval = 15
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw XiaomiCloudError.invalidResponse("登录轮询缺少 HTTP 状态")
                }
                pollCount += 1
                if httpResponse.statusCode != lastStatus || pollCount % 20 == 0 {
                    Self.logger.info("授权轮询第 \(pollCount, privacy: .public) 次，HTTP=\(httpResponse.statusCode, privacy: .public)，body=\(Self.bodyPreview(data), privacy: .public)")
                }
                lastStatus = httpResponse.statusCode
                if httpResponse.statusCode == 200 {
                    let authorization: XiaomiAuthorizationPayload = try decodeGuardedJSON(data)
                    Self.logger.info("授权响应已解析，STS location=\(Self.redactedURL(authorization.location), privacy: .public)")
                    let serviceToken = try await fetchServiceToken(from: authorization.location)
                    Self.logger.info("serviceToken Cookie 获取成功")
                    return XiaomiCloudSession(
                        userID: authorization.userID,
                        ssecurity: authorization.ssecurity,
                        serviceToken: serviceToken
                    )
                }
                try await Task.sleep(for: .milliseconds(300))
            } catch is CancellationError {
                throw XiaomiCloudError.loginCancelled
            } catch let error as URLError where error.code == .timedOut {
                continue
            } catch let error as URLError where error.code == .cancelled {
                throw XiaomiCloudError.loginCancelled
            }
        }
        throw XiaomiCloudError.qrExpired
    }

    /// 使用已授权会话读取中国大陆区域的设备列表。
    func fetchDevices(using cloudSession: XiaomiCloudSession) async throws -> [XiaomiCloudDevice] {
        let endpoint = deviceListEndpoint
        Self.logger.info("设备列表请求开始，endpoint=\(Self.redactedURL(endpoint), privacy: .public)，userId=\(cloudSession.userID, privacy: .public)")
        let plainData = #"{"getVirtualModel":true,"getHuamiDevices":1,"get_split_device":false,"support_smart_home":true}"#
        let nonce = try XiaomiCloudCrypto.nonce()
        let signedNonce = try XiaomiCloudCrypto.signedNonce(
            ssecurity: cloudSession.ssecurity,
            nonce: nonce
        )

        var plainFields = [("data", plainData)]
        plainFields.append(("rc4_hash__", try XiaomiCloudCrypto.signature(
            url: endpoint,
            signedNonce: signedNonce,
            fields: plainFields
        )))
        var sealedFields: [(String, String)] = []
        for (name, value) in plainFields {
            sealedFields.append((name, try XiaomiCloudCrypto.seal(signedNonce: signedNonce, text: value)))
        }
        let requestSignature = try XiaomiCloudCrypto.signature(
            url: endpoint,
            signedNonce: signedNonce,
            fields: sealedFields
        )

        let requestFields = sealedFields + [
            ("signature", requestSignature),
            ("ssecurity", cloudSession.ssecurity),
            ("_nonce", nonce),
        ]
        guard let body = XiaomiCloudCrypto.formEncodedData(requestFields) else {
            throw XiaomiCloudError.invalidResponse("设备列表请求体无效")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("PROTOCAL-HTTP2", forHTTPHeaderField: "x-xiaomi-protocal-flag-cli")
        request.setValue("ENCRYPT-RC4", forHTTPHeaderField: "MIOT-ENCRYPT-ALGORITHM")
        request.setValue(
            cookieHeader(for: cloudSession),
            forHTTPHeaderField: "Cookie"
        )
        Self.logger.info("设备列表请求发送，POST 表单字段=\(requestFields.map(\.0).joined(separator: ","), privacy: .public)，bodyBytes=\(body.count, privacy: .public)")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.info("设备列表响应，HTTP=\(httpResponse.statusCode, privacy: .public)，body=\(Self.bodyPreview(data), privacy: .public)")
        } else {
            Self.logger.error("设备列表响应不是 HTTP，URL=\(Self.redactedURL(endpoint), privacy: .public)")
        }
        try validate(response)
        guard let encodedResponse = String(data: data, encoding: .utf8) else {
            throw XiaomiCloudError.invalidResponse("设备列表不是文本")
        }
        let decrypted = try XiaomiCloudCrypto.unseal(
            signedNonce: signedNonce,
            text: encodedResponse
        )
        Self.logger.info("设备列表响应解密成功，bytes=\(decrypted.count, privacy: .public)")
        let envelope = try JSONDecoder().decode(XiaomiDeviceListEnvelope.self, from: decrypted)
        let devices = envelope.result?.list ?? []
        Self.logger.info("设备列表解析成功，count=\(devices.count, privacy: .public)")
        return devices
    }

    /// 从 STS 跳转结果的临时 Cookie 中读取 serviceToken。
    private func fetchServiceToken(from location: URL) async throws -> String {
        Self.logger.info("STS 请求开始，URL=\(Self.redactedURL(location), privacy: .public)")
        var request = URLRequest(url: location)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        let cookieStorage = session.configuration.httpCookieStorage
        let responseURL = response.url ?? location
        let scopedCookies = (cookieStorage?.cookies(for: responseURL) ?? [])
            + (responseURL == location ? [] : (cookieStorage?.cookies(for: location) ?? []))
        if let httpResponse = response as? HTTPURLResponse {
            let cookieNames = scopedCookies.map(\.name).joined(separator: ",")
            Self.logger.info("STS 响应，HTTP=\(httpResponse.statusCode, privacy: .public)，最终 URL=\(Self.redactedURL(responseURL), privacy: .public)，Cookie names=\(cookieNames.isEmpty ? "<none>" : cookieNames, privacy: .public)，body=\(Self.bodyPreview(data), privacy: .public)")
        }
        if let token = scopedCookies
            .first(where: { $0.name == "serviceToken" && !$0.value.isEmpty })?
            .value {
            return token
        }
        if let token = cookieStorage?.cookies?
            .first(where: { $0.name == "serviceToken" && !$0.value.isEmpty })?
            .value {
            return token
        }
        try validate(response)
        throw XiaomiCloudError.missingServiceToken
    }

    /// 请求并解析带有小米 JSON 防劫持前缀的响应。
    private func guardedJSON<T: Decodable & Sendable>(from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            Self.logger.info("JSON 响应，URL=\(Self.redactedURL(url), privacy: .public)，HTTP=\(httpResponse.statusCode, privacy: .public)，body=\(Self.bodyPreview(data), privacy: .public)")
        }
        try validate(response)
        return try decodeGuardedJSON(data)
    }

    /// 去除固定前缀后解码 JSON。
    private func decodeGuardedJSON<T: Decodable & Sendable>(_ data: Data) throws -> T {
        guard var text = String(data: data, encoding: .utf8) else {
            throw XiaomiCloudError.invalidResponse("登录响应不是 UTF-8")
        }
        text = text.replacingOccurrences(of: "&&&START&&&", with: "")
        guard let cleaned = text.data(using: .utf8) else {
            throw XiaomiCloudError.invalidResponse("登录响应无法转换")
        }
        do {
            return try JSONDecoder().decode(T.self, from: cleaned)
        } catch {
            Self.logger.error("JSON 解码失败，body=\(Self.bodyPreview(data), privacy: .public)，error=\(error.localizedDescription, privacy: .public)")
            throw XiaomiCloudError.invalidResponse("登录字段缺失")
        }
    }

    /// 验证 URLSession 返回了成功的 HTTP 状态。
    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw XiaomiCloudError.invalidResponse("缺少 HTTP 状态")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error("HTTP 请求失败，status=\(httpResponse.statusCode, privacy: .public)，URL=\(Self.redactedURL(httpResponse.url), privacy: .public)")
            throw XiaomiCloudError.httpFailure(httpResponse.statusCode)
        }
    }

    /// 删除 URL 查询参数中的票据，保留主机和路径用于定位问题。
    private static func redactedURL(_ url: URL?) -> String {
        guard let url else { return "<nil>" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? "<invalid-url>"
        }
        components.queryItems = components.queryItems?.map {
            URLQueryItem(name: $0.name, value: "<redacted>")
        }
        return components.url?.absoluteString ?? (url.host ?? "<invalid-url>")
    }

    /// 生成有限长度且已脱敏的响应正文预览，便于从 Xcode 控制台判断失败阶段。
    private static func bodyPreview(_ data: Data) -> String {
        guard var text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return data.isEmpty ? "<empty>" : "<non-utf8 bytes=\(data.count)>"
        }
        text = text.replacingOccurrences(of: "[\\r\\n\\t]+", with: " ", options: .regularExpression)
        let patterns = [
            "(\\\"(?:psecurity|passToken|ssecurity|serviceToken|yetAnotherServiceToken|token|userId)\\\"\\s*:\\s*)\\\"[^\\\"]*\\\"",
            "(\\\"nonce\\\"\\s*:\\s*)[0-9]+",
            "((?:ticket|sign|k|followup)=)[^&\\\" ]+",
        ]
        let replacements = [
            "$1\"<redacted>\"",
            "$1<redacted>",
            "$1<redacted>",
        ]
        for (pattern, replacement) in zip(patterns, replacements) {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let limit = 1_200
        if text.count > limit {
            return String(text.prefix(limit)) + "…"
        }
        return text
    }

    /// 构造设备列表请求所需的 Cookie 头。
    private func cookieHeader(for cloudSession: XiaomiCloudSession) -> String {
        [
            "userId=\(cloudSession.userID)",
            "yetAnotherServiceToken=\(cloudSession.serviceToken)",
            "serviceToken=\(cloudSession.serviceToken)",
            "locale=en_GB",
            "channel=MI_APP_STORE",
        ].joined(separator: "; ")
    }

    /// 生成与米家 Android 客户端格式兼容的 User-Agent。
    private static func makeUserAgent() -> String {
        let suffix = String((0..<13).map { _ in "ABCDE".randomElement()! })
        return "Android-7.1.1-1.0.0-ONEPLUS A3010-136-\(suffix) APP/xiaomi.smarthome APPV/62830"
    }
}
