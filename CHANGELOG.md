# 更新日志 (Changelog)

> *“Simplicity is about subtracting the obvious and adding the meaningful.”*
> —— John Maeda, *The Laws of Simplicity*

所有关于 **MiBar** 项目的关键版本迭代、架构演进与功能更新均记录于此。

---

## [v1.1.0] - 2026-09-02

### ✨ 视觉与交互体验升级 (Visual & Interaction Enhancements)
- **快捷场景 Glass 拟态玻璃质感**：
  - 快捷场景预设按钮全面采用 `.ultraThinMaterial` 毛玻璃材质，通透轻盈。
  - 顶部增加高光反射反光层（Specular Highlight）与精致多色渐变描边。
  - 优化微交互体验，未选中时支持平滑 Hover 提亮与悬浮弹性微缩放，选中时呈现场景专属主题色浸润。
  - 移除多余阴影，保持极简纯净的 macOS 原生质感。

### 🔒 存储与权限体验优化 (Storage & User Experience)
- **Token 存储无感化（UserDefaults 隔离存储）**：
  - 针对非签名/本地构建环境下 Keychain 频繁弹出系统授权密码对话框的问题，将设备通信 Token 全面迁移至应用沙盒本地隔离存储（`UserDefaults`）。
  - 实现零密码干扰、静默读取与秒级保存，极大降低了用户的使用门槛。

### 🏗️ 架构与组件化解耦 (Modular Architecture Refactoring)
- **全面重构 `LightMenuView` 核心视图**：
  - 由原本近 900 行的单一庞大文件解耦为模块化微组件。
  - 提取独立组件：
    - `LightMenuHeaderView`：顶部品牌、呼吸连接灯与电源主开关总控。
    - `SceneGlassButton` & `LightMenuPresetsSection`：场景毛玻璃交互按钮与预设区块。
    - `LightMenuFooterView`：底部设置入口、状态刷新、关于及退出功能区。
    - `LightConfigurationView` & `CloudImportSectionView`：局域网参数配置与米家扫码导入模块。
    - `MiBarButtonStyles`：通用按钮风格（Primary / Secondary / Destructive）与 `MenuItemRow`。
  - `LightMenuView` 代码量锐减至约 140 行，架构更清晰，易于维护与扩展。

---

## [v1.0.0] - 2026-08-30

### 🚀 初始版本发布 (Initial Release)
- **macOS 原生菜单栏常驻**：适配 macOS 14+ / 26+ 原生毛玻璃弹出窗口。
- **局域网 miIO 直连**：基于 UDP 报文与 AES-128-CBC 加密，实现毫秒级超低延迟调光。
- **双维度平滑滑块**：高精度支持 1%~100% 亮度与 2700K~6500K 全光谱色温调节，支持触控板与滚轮微调。
- **四大经典情景预设**：一键切换夜间、休闲、阅读与专注模式。
- **米家扫码快速导入**：一键生成米家 OAuth 扫码登录，免抓包自动拉取挂灯 IP 与 Token。
- **关于与全局状态管理**：内置优雅的关于弹窗与全生命周期状态监听。
