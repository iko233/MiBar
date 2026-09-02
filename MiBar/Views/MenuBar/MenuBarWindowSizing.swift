import AppKit
import SwiftUI

enum MenuBarWindowSizing {
    static let menuWidth: CGFloat = 280
    static let maxHeight: CGFloat = 620

    /// 将测量到的内容尺寸收敛到菜单栏弹窗允许的宽高。
    static func contentSize(fitting: CGSize) -> CGSize {
        CGSize(
            width: menuWidth,
            height: min(max(fitting.height, 1), maxHeight)
        )
    }

    /// 按新内容高度计算内容区域，并保持顶边不动以免弹窗脱离菜单栏。
    static func anchoredFrame(current: NSRect, contentSize: CGSize) -> NSRect {
        var frame = NSRect(origin: current.origin, size: contentSize)
        frame.origin.y = current.maxY - contentSize.height
        return frame
    }
}

struct MenuBarWindowSizeSync: NSViewRepresentable {
    var size: CGSize

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let target = MenuBarWindowSizing.contentSize(fitting: size)
        DispatchQueue.main.async {
            Self.resize(from: nsView, to: target)
        }
    }

    @MainActor
    private static func resize(
        from view: NSView,
        to target: CGSize
    ) {
        guard let window = view.window,
              target.width > 1,
              target.height > 1
        else {
            return
        }

        let currentSize = window.contentView?.bounds.size ?? .zero
        let widthChanged = abs(currentSize.width - target.width) > 1
        let heightChanged = abs(currentSize.height - target.height) > 1

        guard widthChanged || heightChanged else { return }

        // 保存窗口顶部位置，保证 MenuBarExtra 贴紧菜单栏并在高度变化时向下伸缩
        let top = window.frame.maxY

        // 允许窗口重新缩小，避免被 NSHostingView 之前撑大的 contentMinSize 约束挡住
        window.contentMinSize = NSSize(width: target.width, height: 1)

        // 让 AppKit 管理 content → window frame
        window.setContentSize(target)

        // MenuBarExtra 固定顶部，向下伸缩
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrameOrigin(frame.origin)
    }
}

