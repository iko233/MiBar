import Foundation

/// 本地设备配置与 Token 存储管理（基于本地 UserDefaults 存储，避免每次弹出 macOS 钥匙串授权密码对话框）
nonisolated enum LocalConfigStore {
    private static let tokenKey = "deviceToken"
    private static let hostKey = "deviceHost"

    /// 读取保存在本地的设备 token。
    static func readToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    /// 新增或更新保存在本地的设备 token。
    static func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    /// 删除保存在本地的设备 token。
    static func deleteToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private static let thermometerConfigKey = "thermometerConfig"

    /// 读取保存在本地的温湿度计配置（含旧版单设备自动迁移）。
    static func readThermometerConfig() -> ThermometerConfiguration {
        guard let data = UserDefaults.standard.data(forKey: thermometerConfigKey) else {
            return ThermometerConfiguration()
        }
        if let config = try? JSONDecoder().decode(ThermometerConfiguration.self, from: data) {
            return config
        }
        // 兼容迁移旧版单配置
        struct OldThermometerConfig: Decodable {
            var mac: String?
            var bindKey: String?
            var name: String?
            var showInMenuBar: Bool?
        }
        if let oldConfig = try? JSONDecoder().decode(OldThermometerConfig.self, from: data),
           let mac = oldConfig.mac, !mac.isEmpty {
            let migrated = ThermometerConfiguration(
                mac: mac,
                bindKey: oldConfig.bindKey ?? "",
                name: oldConfig.name ?? "米家智能温湿度计",
                showInMenuBar: oldConfig.showInMenuBar ?? true
            )
            saveThermometerConfig(migrated)
            return migrated
        }
        return ThermometerConfiguration()
    }

    /// 保存温湿度计配置。
    static func saveThermometerConfig(_ config: ThermometerConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: thermometerConfigKey)
        }
    }

    /// 删除温湿度计配置。
    static func deleteThermometerConfig() {
        UserDefaults.standard.removeObject(forKey: thermometerConfigKey)
    }

    private static let cloudThermometersKey = "cloudThermometerRecords"

    /// 读取已缓存的米家账号温湿度计凭据列表。
    static func readCachedCloudThermometers() -> [CloudThermometerRecord] {
        guard let data = UserDefaults.standard.data(forKey: cloudThermometersKey),
              let list = try? JSONDecoder().decode([CloudThermometerRecord].self, from: data) else {
            return []
        }
        return list
    }

    /// 保存米家账号温湿度计凭据缓存。
    static func saveCachedCloudThermometers(_ records: [CloudThermometerRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: cloudThermometersKey)
        }
    }
}

/// 兼容别名
typealias KeychainStore = LocalConfigStore

