import AppKit

@MainActor final class WordHighlighter {
    private var panels: [NSPanel] = []
    private(set) var visibleRectangles: [CGRect] = []
    func show(quartzRects: [CGRect]) {
        guard !quartzRects.isEmpty, quartzRects.count <= 8,
              quartzRects.allSatisfy({ $0.width > 0 && $0.height > 0 && $0.width < 1500 && $0.height < 150 }) else { hide(); return }
        while panels.count < quartzRects.count {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating; p.backgroundColor = .clear; p.isOpaque = false
            p.ignoresMouseEvents = true; p.hasShadow = false; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; p.isReleasedWhenClosed = false
            let view = NSView(); view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.4).cgColor
            view.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.95).cgColor
            view.layer?.borderWidth = 2; view.layer?.cornerRadius = 3
            view.setAccessibilityElement(false); p.contentView = view
            panels.append(p)
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for (index, panel) in panels.enumerated() {
            guard quartzRects.indices.contains(index) else { panel.orderOut(nil); continue }
            let rect = quartzRects[index]
            panel.setFrame(CGRect(x: rect.minX-2, y: top-rect.maxY-1, width: rect.width+4, height: rect.height+2), display: true)
            panel.orderFrontRegardless()
        }
        visibleRectangles = quartzRects
    }
    func hide() { panels.forEach { $0.orderOut(nil) }; visibleRectangles = [] }
}
