import AppKit
import SwiftUI

/// 菜单底部操作栏组件（设置、刷新状态、关于、退出）
struct LightMenuFooterView: View {
    @Bindable var store: LightStore
    @Binding var isShowingAbout: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.25)
                .padding(.bottom, 7)

            MenuItemRow(
                title: "设置",
                icon: "gearshape",
                hasChevron: true
            ) {
                store.isEditingConfiguration = true
            }

            MenuItemRow(
                title: "刷新状态",
                icon: "arrow.clockwise"
            ) {
                Task {
                    await store.refresh()
                }
            }

            MenuItemRow(
                title: "关于 MiBar",
                icon: "info.circle"
            ) {
                isShowingAbout = true
            }

            MenuItemRow(
                title: "退出 MiBar",
                icon: "power"
            ) {
                NSApp.terminate(nil)
            }
        }
    }
}
