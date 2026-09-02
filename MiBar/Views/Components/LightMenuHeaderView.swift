import SwiftUI

/// 菜单顶部标题与电源总控组件
struct LightMenuHeaderView: View {
    @Bindable var store: LightStore

    private var connectionColor: Color {
        store.isConnected ? .green : .secondary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MiBar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 5, height: 5)

                    Text(
                        store.isConnected
                            ? "米家显示器挂灯 1S"
                            : store.statusText
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            if store.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            } else {
                Toggle(
                    "电源",
                    isOn: Binding(
                        get: {
                            store.state.isOn
                        },
                        set: { value in
                            Task {
                                await store.setPower(value)
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }
}
