import Foundation
import CoreBluetooth
import OSLog

/// 基于 CoreBluetooth 的后台 BLE 广播监听服务（用于无感接收温湿度计数据）。
final class BluetoothThermometerService: NSObject, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.extrastu.mibar", category: "BluetoothThermometer")

    /// 小米官方 MiBeacon BLE 广播 Service Data UUID (0xFE95)。
    static let miBeaconServiceUUID = CBUUID(string: "FE95")

    private let queue = DispatchQueue(label: "com.extrastu.mibar.ble", qos: .utility)
    private var centralManager: CBCentralManager?
    private var isScanning = false

    private var targetConfig: ThermometerConfiguration?
    private var targetDevicesMap: [String: Data] = [:]
    private var discoveredDevicesMap: [String: DiscoveredBLEDevice] = [:]

    var onReadingUpdated: (@Sendable (ThermometerReading) -> Void)?
    var onDeviceReadingUpdated: (@Sendable (String, ThermometerReading) -> Void)?
    var onDiscoveredDevicesUpdated: (@Sendable ([DiscoveredBLEDevice]) -> Void)?
    var onStateChanged: (@Sendable (CBManagerState, Bool) -> Void)?
    var onNearbyDeviceDetected: (@Sendable (String, String, Int) -> Void)?

    override init() {
        super.init()
    }

    /// 启动蓝牙服务并初始化 CBCentralManager。
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.centralManager == nil {
                Self.logger.info("🚀 [BLE] 初始化 CBCentralManager...")
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [CBCentralManagerOptionShowPowerAlertKey: true]
                )
            }
        }
    }

    /// 更新目标温湿度计配置并开始/重启监听。
    func updateConfiguration(_ config: ThermometerConfiguration) {
        queue.async { [weak self] in
            guard let self else { return }
            self.targetConfig = config

            var newMap: [String: Data] = [:]
            for dev in config.devices where dev.isValid {
                if let keyData = Data(hexString: dev.normalizedBindKey), keyData.count == 16 {
                    newMap[dev.normalizedMAC] = keyData
                }
            }
            self.targetDevicesMap = newMap

            Self.logger.info("⚙️ [BLE] 目标温湿度计配置已更新: 共 \(config.devices.count, privacy: .public) 台设备 (有效解密设备 \(newMap.count, privacy: .public) 台)")
            for (mac, _) in newMap {
                Self.logger.info("   -> 监听设备 MAC: \(mac, privacy: .public)")
            }

            self.startScanningIfNeeded()
        }
    }

    /// 停止扫描。
    func stop() {
        queue.async { [weak self] in
            self?.stopScanning()
        }
    }

    private func startScanningIfNeeded() {
        guard let central = centralManager else {
            Self.logger.warning("⚠️ [BLE] CBCentralManager 尚未创建")
            return
        }

        guard central.state == .poweredOn else {
            Self.logger.notice("⏳ [BLE] 蓝牙尚未处于 poweredOn 状态 (当前状态: \(self.stateDescription(central.state)))，等待状态变更")
            return
        }

        guard !isScanning else {
            Self.logger.debug("ℹ️ [BLE] 当前已处于扫描状态，无需重复启动")
            return
        }

        isScanning = true
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        Self.logger.info("📡 [BLE] 已开启全局低功耗广播扫描 (被动监听 0xFE95 广播帧)")
        notifyState()
    }

    private func stopScanning() {
        if isScanning {
            centralManager?.stopScan()
            isScanning = false
            Self.logger.info("🛑 [BLE] 已停止蓝牙广播扫描")
            notifyState()
        }
    }

    private func notifyState() {
        let state = centralManager?.state ?? .unknown
        let scanning = isScanning
        onStateChanged?(state, scanning)
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown (正在初始化)"
        case .resetting: return "resetting (蓝牙连接重置中)"
        case .unsupported: return "unsupported (此 Mac 不支持 BLE)"
        case .unauthorized: return "unauthorized (缺少蓝牙访问权限，请在系统设置-隐私中检查)"
        case .poweredOff: return "poweredOff (系统蓝牙已关闭，请打开蓝牙)"
        case .poweredOn: return "poweredOn (正常运行)"
        @unknown default: return "未知状态 (\(state.rawValue))"
        }
    }
}

extension BluetoothThermometerService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let desc = stateDescription(central.state)
        Self.logger.info("🔄 [BLE] 蓝牙状态更新: \(desc, privacy: .public)")
        notifyState()

        if central.state == .poweredOn {
            startScanningIfNeeded()
        } else {
            isScanning = false
            notifyState()
            if central.state == .unauthorized {
                Self.logger.error("❌ [BLE] 权限被拒绝！请确认已在 macOS「系统设置」->「隐私与安全性」->「蓝牙」中允许 MiBar 访问蓝牙。")
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // 查找 0xFE95 Service Data
        guard let serviceDataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let miBeaconData = serviceDataDict[Self.miBeaconServiceUUID] else {
            return
        }

        let hexPayload = miBeaconData.map { String(format: "%02X", $0) }.joined()
        Self.logger.debug("📥 [BLE] 收到 0xFE95 广播帧: 设备=\(peripheral.name ?? "Unknown"), RSSI=\(RSSI)dBm, 长度=\(miBeaconData.count)B, Hex=\(hexPayload)")

        if let (detectedMAC, pid) = MiBeaconParser.extractDeviceInfo(from: miBeaconData) {
            let mType = ThermometerModelType.from(productID: pid)
            let mCode = peripheral.name ?? mType.defaultModelCode
            onNearbyDeviceDetected?(detectedMAC, mCode, RSSI.intValue)

            let discoveredDev = DiscoveredBLEDevice(
                mac: detectedMAC,
                modelType: mType,
                modelCode: mCode,
                rssi: RSSI.intValue,
                lastSeen: Date()
            )
            discoveredDevicesMap[detectedMAC] = discoveredDev
            let sortedList = Array(discoveredDevicesMap.values).sorted { $0.rssi > $1.rssi }
            onDiscoveredDevicesUpdated?(sortedList)
        }

        guard !targetDevicesMap.isEmpty else {
            Self.logger.debug("⚠️ [BLE] 忽略 MiBeacon: 尚未配置任何有效的温湿度计")
            return
        }

        // 多设备路由解析与解密
        if let (matchedMAC, reading) = MiBeaconParser.parseMulti(
            serviceData: miBeaconData,
            candidateDevices: targetDevicesMap
        ) {
            Self.logger.info("🎉 [BLE] 成功提取 [MAC: \(matchedMAC, privacy: .public)] 读数！室温: \(reading.temperatureString, privacy: .public), 湿度: \(reading.humidityString, privacy: .public), 电量: \(reading.battery.map { "\($0)%" } ?? "无", privacy: .public), RSSI: \(RSSI, privacy: .public)dBm")
            onDeviceReadingUpdated?(matchedMAC, reading)
            onReadingUpdated?(reading)
        }
    }
}
