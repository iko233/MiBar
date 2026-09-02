import SwiftUI

@main
struct MiBarApp: App {
    @State private var store = LightStore()

    /// 创建仅驻留菜单栏的应用场景。
    var body: some Scene {
        MenuBarExtra {
            LightMenuView(store: store)
        } label: {
            Image(systemName: store.state.isOn ? "lightbulb.fill" : "lightbulb")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.state.isOn ? .yellow : .secondary)
                .accessibilityLabel("米家挂灯")
        }
        .menuBarExtraStyle(.window)
    }
}
