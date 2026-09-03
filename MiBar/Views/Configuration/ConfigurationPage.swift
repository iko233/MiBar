import Foundation

/// 统一配置中心页面导航路由枚举。
enum ConfigurationPage: Hashable {
    /// 统一已连接设备列表
    case list
    /// 米家扫码与选择导入
    case scanImport
    /// 挂灯 1S 参数详情与移除
    case lightDetail
    /// 温湿度计参数详情与移除
    case thermometerDetail(mac: String)
}
