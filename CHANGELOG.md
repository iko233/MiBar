# 更新日志 (Changelog)

> *“Simplicity is about subtracting the obvious and adding the meaningful.”*
> —— John Maeda, *The Laws of Simplicity*

所有关于 **MiBar** 项目的关键版本迭代、架构演进与功能更新均记录于此。

---

## [v1.5.0] - 2026-09-03

> *“To design is much more than simply to assemble, to order, or even to edit: it is to add value and meaning, to illuminate, to simplify, to clarify, to modify, to dignify, to dramatize, to persuade, and perhaps even to amuse.”*
> —— Paul Rand

### 🔄 统一设备管理中心重构与 MiBeacon v5 增量分包解析
- **彻底废除 Tab 分栏，重构为全流程单流式统一设备中心 (Unified Device Hub)**：
  - 无设备时：直接呈现「米家扫码快速导入」界面与清晰扫码指引，扫码后列出账号下所有挂灯与温湿度计，支持选择性勾选或点击「添加」。
  - 有设备时：直接展示统一「已连接设备列表」，一站式呈现挂灯与各温湿度计的实时状态与指标。
  - 二级详情导航：点击列表中的任意设备 item 即可进入其专属「详情配置」页面，随时修改参数、重命名、切换菜单栏主设备或安全移除设备。
- **MiBeacon v5 协议对象补全与分包增量合并引擎 (Incremental Merging Engine)**：
  - 深度支持米家智能温湿度计 3 mini (MJWSD06MMC) 专属对象：`0x4801`（4 字节 IEEE 浮点温度）、`0x4802`（1 字节湿度）、`0x4803`（电量）。
  - 实现读数增量合并引擎（`merged(with:)`）：解决 3 mini 为极致省电交替单发湿度包与温度包的硬件机制，任意数据包到达均能瞬间点亮读数，温湿度平滑融合呈现。

---

## [v1.4.0] - 2026-09-03

> *“The invisible things of the world are discovered through the things that are made.”*
> —— Saint Paul

### 📡 全面转向扫描发现：BLE 广播雷达与米家云端凭证池对齐 (Scan-to-Add)
- **全面摒弃手动复制粘贴流程**：
  - 遵循“添加设备都应从扫描获取信息”的交互准则，彻底告别繁琐的 12 位 MAC 与 32 位 Hex BindKey 手工查找输入。
- **本地 BLE 被动广播雷达扫描 (Nearby Radar)**：
  - 实时捕获 Mac 蓝牙有效覆盖范围内的所有米家温湿度计广播（`MJWSD06MMC`、`MJWSD05MMC`、`LYWSD03MMC`）。
  - 按信号强度（RSSI）动态排序，优先置顶近场强信号设备，展示信号等级、型号徽标与 MAC 地址。
- **米家扫码云端凭证池缓存与秒级自动匹配**：
  - 扫码登录米家账号时，自动拉取并本地安全持久化账号下所有温湿度计的 16 字节 BindKey。
  - 附近雷达扫描到设备时，自动与云端凭据进行 MAC 对齐：命中即点亮 **「一键添加」** 按钮，点击瞬间完成配对并开启解密。
  - 同步列出米家账号已同步但尚未激活的温湿度计，支持直接一键添加。
- **配置面板雷达交互与折叠备用输入**：
  - 配置页升级为动态扫描列表，保留折叠式高级手动输入供极客与离线测试场景备用。

---

## [v1.3.0] - 2026-09-03

> *“Architecture is the learned game, correct and magnificent, of forms assembled in the light.”*
> —— Le Corbusier, *Towards an Architecture*

### 🌡️ 多产品架构演进：米家智能温湿度计 3 mini (MJWSD06MMC) 与双列环境看板
- **原生支持米家智能温湿度计 3 mini (MJWSD06MMC)**：
  - 精准识别 PID `0x55B5`，自动匹配其 MiBeacon v5 协议帧。
  - 支持多设备广播解密路由与 Nonce 动态匹配，兼顾携带 MAC 与省略 MAC 的省电广播帧。
- **主面板双列紧凑毛玻璃环境看板 (Dual Compact Glass Cards)**：
  - 针对多设备场景，主控制面板自适应演进：单设备展示大胶囊，2 台设备自适应呈现左右等宽 1:1 双列并排玻璃卡片。
  - 完美复用 280pt 窗口宽度，不额外增加纵向高度，视觉极简且空间利用率极高。
- **多设备管理中心与自动发现 (Device Management Hub)**：
  - 设置页面支持多设备卡片堆叠列表、设置菜单栏主设备、自定义名称与独立密钥管理。
  - 引入“附近新设备智能捕获”横幅，捕获到附近活跃温湿度计即可一键快捷添加。
  - 数据模型无缝平滑迁移，全向后兼容旧版单设备配置。

---

## [v1.2.0] - 2026-09-03

> *“Temperature is merely the average kinetic energy of molecules, but comfort is the subtle harmony of mind and matter.”*
> —— Carlo Rovelli, *The Order of Time*

### 🌡️ 米家智能温湿度计 3 (MJWSD05MMC) 接入与状态栏显示
- **macOS 本地 BLE 广播被动监听**：
  - 基于 `CoreBluetooth`（`CBCentralManager`）实现纯本地低功耗扫描，无需建立持久 GATT 蓝牙连接，不损耗温湿度计纽扣电池寿命。
  - 自动捕获 `0xFE95`（MiBeacon）广播帧，秒级解析温度、湿度与剩余电量。
- **纯 Swift 原生 AES-CCM 认证解密引擎**：
  - 严格遵循 NIST SP 800-38C 与 RFC 3610 标准，基于 CommonCrypto `CCCrypt`（AES-128-ECB）实现轻量级 AES-CCM 认证解密与 4 字节 MIC 完整性校验。
- **米家扫码自动同步与手动配置双轨支持**：
  - 扫码登录米家账号时，自动检索名下绑定的温湿度计并静默提取 16 字节 BindKey（BeaconKey）。
  - 设置面板提供 MAC 与 32 位 Hex BindKey 手动填写与显示/隐藏切换。
- **macOS 菜单栏常驻与控制面板融合呈现**：
  - 顶部状态栏支持紧凑温湿度呈现（例如：`💡 24.2°C 56%`）。
  - 挂灯控制面板顶部新增温湿度毛玻璃交互卡片，支持悬停高光、一键直达温湿度计配置。
- **配置面板分段选项卡与仪表盘交互重构 (UI / UX Overhaul)**：
  - 设置页面新增「挂灯 1S」与「温湿度计 3」圆角分段选择器（Segmented Tab Bar），告别长页面拥挤布局。
  - 温湿度计专属仪表盘卡片：大字号温湿度指标卡、蓝牙状态呼吸灯、电量与更新时间相对显示、手动重新扫描。
  - 输入体验优化：支持剪贴板一键粘贴 MAC / BindKey、实时密钥字符计数校验（32/32）与智能同步指引。

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
