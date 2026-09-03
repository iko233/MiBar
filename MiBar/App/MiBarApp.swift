import SwiftUI

@main
struct MiBarApp: App {
    @State private var store = LightStore()
    @State private var thermometerStore = ThermometerStore()

    /// 创建仅驻留菜单栏的应用场景。
    var body: some Scene {
        MenuBarExtra {
            LightMenuView(store: store, thermometerStore: thermometerStore)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.state.isOn ? "lightbulb.fill" : "lightbulb")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(store.state.isOn ? .yellow : .secondary)

                if thermometerStore.configuration.showInMenuBar,
                   let reading = thermometerStore.reading {
                    Text(reading.menuBarSummary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
            .task { [weak thermometerStore] in
                store.onCloudThermometersDiscovered = { [weak thermometerStore] records in
                    thermometerStore?.updateCloudThermometers(records)
                }
                store.onThermometerDiscovered = { [weak thermometerStore] device, key in
                    thermometerStore?.importFromCloud(device: device, bindKey: key)
                }
            }
            .accessibilityLabel("米家挂灯与温湿度")
        }
        .menuBarExtraStyle(.window)
    }
}
