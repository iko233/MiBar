import AppKit
import SwiftUI

/// 统一设备管理与配置中心入口容器视图
/// 根据设备配置状态与内部导航状态动态呈现统一设备列表、米家扫码导入、挂灯详情或温湿度计详情。
struct LightConfigurationView: View {
    @Bindable var store: LightStore
    @Bindable var thermometerStore: ThermometerStore
    @Binding var isConfirmingClearConfiguration: Bool

    @State private var currentPage: ConfigurationPage? = nil

    /// 是否已配置了任何设备（挂灯或温湿度计）
    private var hasAnyConfiguredDevice: Bool {
        store.isLightConfigured || !thermometerStore.devices.isEmpty
    }

    /// 当前激活的页面状态
    private var activePage: ConfigurationPage {
        if let targetMAC = store.targetDetailDeviceMAC {
            return .thermometerDetail(mac: targetMAC)
        }
        if let currentPage {
            return currentPage
        }
        return hasAnyConfiguredDevice ? .list : .scanImport
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch activePage {
            case .list:
                UnifiedDeviceListView(
                    store: store,
                    thermometerStore: thermometerStore,
                    onNavigate: { newPage in
                        currentPage = newPage
                    },
                    onFinish: {
                        store.isEditingConfiguration = false
                    }
                )

            case .scanImport:
                UnifiedScanImportView(
                    store: store,
                    thermometerStore: thermometerStore,
                    canGoBack: hasAnyConfiguredDevice,
                    onBack: {
                        currentPage = .list
                    },
                    onDeviceAdded: {
                        currentPage = .list
                    }
                )

            case .lightDetail:
                LightDetailView(
                    store: store,
                    onBack: {
                        currentPage = .list
                    },
                    onDeviceRemoved: {
                        currentPage = hasAnyConfiguredDevice ? .list : .scanImport
                    }
                )

            case .thermometerDetail(let mac):
                ThermometerDetailView(
                    mac: mac,
                    store: thermometerStore,
                    onBack: {
                        store.targetDetailDeviceMAC = nil
                        currentPage = .list
                    },
                    onDeviceRemoved: {
                        store.targetDetailDeviceMAC = nil
                        currentPage = hasAnyConfiguredDevice ? .list : .scanImport
                    }
                )
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: activePage)
    }
}

