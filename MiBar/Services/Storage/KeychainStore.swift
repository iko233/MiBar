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
}

/// 兼容别名
typealias KeychainStore = LocalConfigStore

