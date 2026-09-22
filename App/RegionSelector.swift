import AppKit

@MainActor final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect, CGDirectDisplayID) -> Void)?
    func begin(completion: @escaping (CGRect, CGDirectDisplayID) -> Void) {
        cancel(); self.completion = completion
        for screen in NSScreen.screens {
            let window = RegionPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver; window.backgroundColor = .clear; window.isOpaque = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.hasShadow = false
            let view = RegionView(frame: CGRect(origin: .zero, size: screen.frame.size)); view.screen = screen
            view.selected = { [weak self] local in
                guard let self else { return }
                let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
                let global = CaptureGeometry.quartzRect(local: local, screenFrame: screen.frame, primaryTop: primaryTop)
                let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
                let callback = self.completion; self.cancel(); callback?(global, id)
            }
            view.cancelled = { [weak self] in self?.cancel() }
            window.contentView = view; windows.append(window); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        }
    }
    func cancel() { windows.forEach { $0.orderOut(nil) }; windows.removeAll(); completion = nil }
}
private final class RegionPanel: NSPanel { override var canBecomeKey: Bool { true } }
private final class RegionView: NSView {
    var screen: NSScreen?
    var selected: ((CGRect) -> Void)?
    var cancelled: (() -> Void)?
    private var start: CGPoint?
    private var area = CGRect.zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill(); bounds.fill()
        if !area.isEmpty { NSColor.white.withAlphaComponent(0.15).setFill(); area.fill(); NSColor.systemCyan.setStroke(); let path = NSBezierPath(rect: area); path.lineWidth = 2; path.stroke() }
        let text = "Drag a rectangle on this display • Escape to cancel"
        text.draw(at: NSPoint(x: 24, y: bounds.height-60), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white])
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }; let p = convert(event.locationInWindow, from: nil)
        area = CGRect(x: min(p.x,start.x), y: min(p.y,start.y), width: abs(p.x-start.x), height: abs(p.y-start.y)).intersection(bounds); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); if area.width > 3 && area.height > 3 { selected?(area) } else { cancelled?() } }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancelled?() } }
}
