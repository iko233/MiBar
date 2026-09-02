import SwiftUI

/// MenuBarExtra 无法可靠弹出系统 alert / popover，改用窗口内自定义确认层。
struct MenuBarModal: View {
    let title: String
    let message: String
    let confirmTitle: String
    let isDestructive: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    /// 在菜单内容上方盖一层遮罩和确认卡片。
    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .background(.ultraThinMaterial.opacity(0.6))
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityLabel("关闭确认")

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if isDestructive {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered)

                    Spacer(minLength: 8)

                    if isDestructive {
                        Button(confirmTitle, role: .destructive, action: onConfirm)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    } else {
                        Button(confirmTitle, action: onConfirm)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                    }
                }
                .controlSize(.regular)
                .padding(.top, 4)

            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .padding(20)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
    }
}
