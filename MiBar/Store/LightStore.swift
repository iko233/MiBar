import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "MiBar", category: "LightStore")

@MainActor
@Observable
final class LightStore {
    var host: String
    var tokenHex: String
    var state = LightState()
    var statusText = "尚未连接"
    var isConnected = false
    var isWorking = false
    var isEditingConfiguration: Bool
    var qrImageData: Data?
    var qrLoginURL: URL?
    var cloudDevices: [XiaomiCloudDevice] = []
    var scannedCloudThermometers: [CloudThermometerRecord] = []
    var cloudLoginStatus = ""
    var isCloudLoginActive = false
    var onThermometerDiscovered: (@MainActor (XiaomiCloudDevice, String) -> Void)?
    var onCloudThermometersDiscovered: (@MainActor ([CloudThermometerRecord]) -> Void)?

    /// 是否已配置挂灯
    var isLightConfigured: Bool {
        !host.isEmpty && !tokenHex.isEmpty
    }

    /// 外部指定跳转进入详情页的温湿度计 MAC
    var targetDetailDeviceMAC: String? = nil

    enum ConfigurationTab: String, CaseIterable, Identifiable {
        case light = "挂灯 1S"
        case thermometer = "温湿度计 3"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .light: return "lightbulb"
            case .thermometer: return "thermometer.medium"
            }
        }
    }

    var selectedConfigurationTab: ConfigurationTab = .light

    private var client: MiIOClient?
    private var activeOperations = 0
    private var brightnessTask: Task<Void, Never>?
    private var temperatureTask: Task<Void, Never>?
    private var brightnessRevision = 0
    private var temperatureRevision = 0
    private var cloudLoginTask: Task<Void, Never>?
    private var cloudLoginGeneration = 0

    /// 从本机偏好设置恢复设备配置。
    init() {
        let savedHost = UserDefaults.standard.string(forKey: "deviceHost") ?? ""
        let savedToken = LocalConfigStore.readToken() ?? ""
        host = savedHost
        tokenHex = savedToken
        isEditingConfiguration = savedHost.isEmpty || savedToken.isEmpty
        logger.info("🚀 [LightStore] 初始化: 读取到已存 IP='\(savedHost)', Token已读取=\(!savedToken.isEmpty), 进入配置页=\(self.isEditingConfiguration)")
        if !savedHost.isEmpty, !savedToken.isEmpty {
            do {
                client = try MiIOClient(host: savedHost, tokenHex: savedToken)
                logger.info("✅ [LightStore] 成功创建 MiIOClient: IP=\(savedHost)")
            } catch {
                logger.error("❌ [LightStore] 创建 MiIOClient 失败: \(error.localizedDescription)")
            }
        }
    }

    /// 判断当前 IP 和 token 是否已完整填写。
    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && tokenHex.trimmingCharacters(in: .whitespacesAndNewlines).count == 32
    }

    /// 菜单首次展示时读取一次真实设备状态。
    func start() async {
        guard isConfigured else {
            logger.info("ℹ️ [LightStore] 设备尚未完整配置，跳过初次连接刷新")
            return
        }
        logger.info("🔄 [LightStore] 启动并初次刷新设备状态...")
        await refresh()
    }


    /// 校验并保存 IP/token，随后立即验证连接。
    func saveConfiguration() async {
        logger.info("💾 [LightStore] 正在保存配置: host='\(self.host)', token长度=\(self.tokenHex.count)")
        do {
            try applyConfiguration(host: host, token: tokenHex)
            await refresh()
        } catch {
            logger.error("❌ [LightStore] 保存配置失败: \(error.localizedDescription)")
            show(error)
        }
    }

    /// 把 IP/token 写入内存和本地偏好设置，不立刻访问局域网。
    func applyConfiguration(host rawHost: String, token rawToken: String) throws {
        let normalizedHost = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        host = normalizedHost
        tokenHex = normalizedToken
        if normalizedHost.isEmpty {
            client = nil
            isEditingConfiguration = true
            if Data(hexString: normalizedToken)?.count == 16 {
                LocalConfigStore.saveToken(normalizedToken)
            }
            logger.info("ℹ️ [LightStore] 配置已清空或 IP 为空")
            return
        }
        let newClient = try MiIOClient(host: normalizedHost, tokenHex: normalizedToken)
        LocalConfigStore.saveToken(normalizedToken)
        UserDefaults.standard.set(normalizedHost, forKey: "deviceHost")
        client = newClient
        isEditingConfiguration = false
        logger.info("✅ [LightStore] 成功写入新配置到本地存储: host=\(normalizedHost)")
    }

    /// 删除本机保存的 IP/token，方便重新扫码或手工配置。
    func clearConfiguration() {
        logger.info("🗑️ [LightStore] 正在清除本机配置...")
        cancelCloudQRLogin()
        brightnessTask?.cancel()
        temperatureTask?.cancel()
        host = ""
        tokenHex = ""
        client = nil
        isConnected = false
        isWorking = false
        activeOperations = 0
        state = LightState()
        isEditingConfiguration = true
        cloudLoginStatus = ""
        UserDefaults.standard.removeObject(forKey: "deviceHost")
        LocalConfigStore.deleteToken()
        statusText = "已删除本机配置"
        logger.info("✅ [LightStore] 已成功清除本地配置")
    }

    /// 导入用户选中的挂灯 IP/token 并交给现有配置流程保存。
    func importCloudDevice(_ device: XiaomiCloudDevice) async {
        guard device.model == "yeelink.light.lamp22" else { return }
        logger.info("📥 [LightStore] 导入云端挂灯: name=\(device.name), IP=\(device.localIP)")
        qrImageData = nil
        qrLoginURL = nil
        cloudDevices = []
        do {
            try applyConfiguration(host: device.localIP, token: device.token)
            if device.localIP.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cloudLoginStatus = "已导入 \(device.name) 的 token，请填写 IP 后保存"
                return
            }
            cloudLoginStatus = "已导入 \(device.name)"
            await refresh()
        } catch {
            host = device.localIP
            tokenHex = device.token
            isEditingConfiguration = true
            cloudLoginStatus = "已填入 \(device.name) 的 IP 和 token，请点击保存并连接"
            logger.error("❌ [LightStore] 导入云端挂灯失败: \(error.localizedDescription)")
            show(error)
        }
    }

    /// 启动原生小米二维码登录并等待设备导入。
    func startCloudQRLogin() {
        logger.info("📲 [LightStore] 启动米家二维码扫码登录流程...")
        cloudLoginTask?.cancel()
        cloudLoginGeneration += 1
        let generation = cloudLoginGeneration
        qrImageData = nil
        qrLoginURL = nil
        cloudDevices = []
        cloudLoginStatus = "正在向小米获取二维码…"
        isCloudLoginActive = true
        cloudLoginTask = Task { [weak self] in
            await self?.performCloudQRLogin(generation: generation)
        }
    }

    /// 取消当前二维码登录并清除短期会话界面。
    func cancelCloudQRLogin() {
        logger.info("🚫 [LightStore] 取消米家二维码登录")
        cloudLoginGeneration += 1
        cloudLoginTask?.cancel()
        cloudLoginTask = nil
        qrImageData = nil
        qrLoginURL = nil
        cloudDevices = []
        cloudLoginStatus = "扫码登录已取消"
        isCloudLoginActive = false
    }

    /// 从挂灯刷新电源、亮度和色温状态。
    func refresh() async {
        guard let client else {
            isEditingConfiguration = true
            statusText = "请先填写设备配置"
            logger.warning("⚠️ [LightStore] 尝试刷新但客户端未初始化 (client == nil)")
            return
        }
        logger.info("🔄 [LightStore] 开始刷新挂灯状态...")
        beginOperation(message: "正在连接…")
        defer { endOperation() }
        do {
            state = try await client.getState()
            isConnected = true
            statusText = "已通过局域网连接"
            logger.info("✅ [LightStore] 挂灯连接成功并已同步状态")
        } catch {
            logger.error("❌ [LightStore] 刷新挂灯失败: \(error.localizedDescription)")
            show(error)
        }
    }


    /// 切换挂灯电源，并只在设备确认后更新界面状态。
    func setPower(_ isOn: Bool) async {
        guard let client else { return }
        beginOperation(message: isOn ? "正在开灯…" : "正在关灯…")
        defer { endOperation() }
        do {
            try await client.setPower(isOn)
            state.isOn = isOn
            isConnected = true
            statusText = isOn ? "挂灯已开启" : "挂灯已关闭"
        } catch {
            show(error)
        }
    }

    /// 防抖安排亮度写入，避免拖动滑块时持续轰炸设备。
    func scheduleBrightness(_ value: Int) {
        let clamped = min(max(value, 1), 100)
        state.brightness = clamped
        brightnessRevision += 1
        let revision = brightnessRevision
        brightnessTask?.cancel()
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await self?.commitBrightness(clamped, revision: revision)
        }
    }

    /// 防抖安排色温写入，避免拖动滑块时持续轰炸设备。
    func scheduleColorTemperature(_ value: Int) {
        let clamped = min(max(value, 2_700), 6_500)
        state.colorTemperature = clamped
        temperatureRevision += 1
        let revision = temperatureRevision
        temperatureTask?.cancel()
        temperatureTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await self?.commitColorTemperature(clamped, revision: revision)
        }
    }

    /// 一键应用场景预设（色温与亮度），并在挂灯未开启时自动开灯。
    func applyPreset(colorTemperature: Int, brightness: Int) {
        scheduleColorTemperature(colorTemperature)
        scheduleBrightness(brightness)
        if !state.isOn {
            Task { await setPower(true) }
        }
    }

    /// 将最终亮度写入设备，并阻止旧任务覆盖新状态。
    private func commitBrightness(_ value: Int, revision: Int) async {
        guard revision == brightnessRevision, let client else { return }
        beginOperation(message: "正在调整亮度…")
        defer { endOperation() }
        do {
            try await client.setBrightness(value)
            guard revision == brightnessRevision else { return }
            isConnected = true
            statusText = "亮度 \(value)%"
        } catch {
            guard revision == brightnessRevision else { return }
            show(error)
        }
    }

    /// 将最终色温写入设备，并阻止旧任务覆盖新状态。
    private func commitColorTemperature(_ value: Int, revision: Int) async {
        guard revision == temperatureRevision, let client else { return }
        beginOperation(message: "正在调整色温…")
        defer { endOperation() }
        do {
            try await client.setColorTemperature(value)
            guard revision == temperatureRevision else { return }
            isConnected = true
            statusText = "色温 \(value)K"
        } catch {
            guard revision == temperatureRevision else { return }
            show(error)
        }
    }

    /// 移除当前挂灯设备配置
    func removeLightDevice() {
        host = ""
        tokenHex = ""
        UserDefaults.standard.removeObject(forKey: "deviceHost")
        LocalConfigStore.deleteToken()
        client = nil
        isConnected = false
        statusText = "未配置"
        logger.info("🗑️ [LightStore] 已移除挂灯设备配置")
    }

    /// 完成二维码展示、授权轮询与挂灯设备筛选。
    private func performCloudQRLogin(generation: Int) async {
        let cloudClient = XiaomiCloudClient()
        do {
            let challenge = try await cloudClient.requestChallenge()
            guard generation == cloudLoginGeneration else { return }
            qrImageData = challenge.imageData
            qrLoginURL = challenge.loginURL
            cloudLoginStatus = "请使用米家 App 扫码并确认登录"

            let cloudSession = try await cloudClient.waitForAuthorization(challenge)
            guard generation == cloudLoginGeneration else { return }
            cloudLoginStatus = "授权成功，正在读取设备…"

            let devices = try await cloudClient.fetchDevices(using: cloudSession)
            guard generation == cloudLoginGeneration else { return }
            let lightBars = devices.filter {
                $0.model == "yeelink.light.lamp22"
                    && Data(hexString: $0.token)?.count == 16
            }
            guard !lightBars.isEmpty else { throw XiaomiCloudError.deviceNotFound }

            qrImageData = nil
            qrLoginURL = nil
            let reachable = lightBars.filter { !$0.localIP.isEmpty }
            cloudDevices = reachable.isEmpty ? lightBars : reachable
            if !cloudDevices.isEmpty {
                cloudLoginStatus = "已获取到设备列表，请选择要添加的设备"
            }

            // 检查米家账号下是否有米家温湿度计，若有则同步提取其 BeaconKey
            let thermometers = devices.filter { $0.isThermometer }
            if !thermometers.isEmpty {
                logger.info("☁️ 云端共发现 \(thermometers.count) 个温湿度计相关设备，开始逐一查询 BeaconKey...")
                var discoveredList: [(device: XiaomiCloudDevice, bindKey: String)] = []
                var records: [CloudThermometerRecord] = []
                for thermometer in thermometers {
                    logger.info("  -> 扫描到温湿度计: [\(thermometer.name, privacy: .public)] (did: \(thermometer.did), model: \(thermometer.model, privacy: .public), MAC: \(thermometer.mac ?? "未提供", privacy: .public))")
                    do {
                        if let beaconKey = try await cloudClient.fetchBeaconKey(did: thermometer.did, using: cloudSession),
                           !beaconKey.isEmpty {
                            logger.info("  ✅ 成功获取 [\(thermometer.name, privacy: .public)] 的 BeaconKey")
                            discoveredList.append((thermometer, beaconKey))
                            records.append(CloudThermometerRecord(
                                did: thermometer.did,
                                name: thermometer.name,
                                model: thermometer.model,
                                mac: thermometer.mac,
                                bindKey: beaconKey
                            ))
                        }
                    } catch {
                        logger.warning("  ⚠️ 获取温湿度计 [\(thermometer.name, privacy: .public)] BeaconKey 失败：\(error.localizedDescription, privacy: .public)")
                    }
                }
                if !records.isEmpty {
                    self.scannedCloudThermometers = records
                    LocalConfigStore.saveCachedCloudThermometers(records)
                    onCloudThermometersDiscovered?(records)
                }
                if let first = discoveredList.first {
                    onThermometerDiscovered?(first.device, first.bindKey)
                }
            }
        } catch {
            guard generation == cloudLoginGeneration else { return }
            qrImageData = nil
            qrLoginURL = nil
            cloudLoginStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        if generation == cloudLoginGeneration {
            isCloudLoginActive = false
            cloudLoginTask = nil
        }
    }

    /// 记录一个正在执行的设备操作。
    private func beginOperation(message: String) {
        activeOperations += 1
        isWorking = true
        statusText = message
    }

    /// 结束一个设备操作，并维护准确的忙碌状态。
    private func endOperation() {
        activeOperations = max(0, activeOperations - 1)
        isWorking = activeOperations > 0
    }

    /// 将底层错误转换为菜单中的连接状态。
    private func show(_ error: Error) {
        isConnected = false
        statusText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
