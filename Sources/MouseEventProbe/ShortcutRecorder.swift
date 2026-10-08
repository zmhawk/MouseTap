import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: ShortcutBinding?
    @Binding var isCapturing: Bool
    var onBeginCapture: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.isCapturing = isCapturing
        view.onCapture = { shortcut = $0 }
        view.onBeginCapture = onBeginCapture
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.shortcut = shortcut
        nsView.isCapturing = isCapturing
        nsView.onCapture = { shortcut = $0 }
        nsView.onBeginCapture = onBeginCapture
    }
}

final class ShortcutRecorderView: NSView {
    var shortcut: ShortcutBinding? { didSet { needsDisplay = true } }
    var isCapturing = false { didSet { needsDisplay = true } }
    var onCapture: ((ShortcutBinding) -> Void)?
    var onBeginCapture: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isCapturing = true
        onBeginCapture?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let title: String
        if isCapturing {
            title = "请按下快捷键…（Esc 取消）"
        } else {
            title = shortcut?.displayName ?? "点击录制快捷键"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = NSString(string: title)
        let size = text.size(withAttributes: attributes)
        let point = NSPoint(x: max(8, (bounds.width - size.width) / 2), y: (bounds.height - size.height) / 2)
        text.draw(at: point, withAttributes: attributes)
    }

}
