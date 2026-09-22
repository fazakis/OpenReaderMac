import AppKit

// A text editor that supports ordinary Copy but intentionally withholds AX selection.
final class CopyOnlyTextView: NSTextView {
    override func accessibilitySelectedText() -> String? { nil }
    override func accessibilitySelectedTextRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    override func accessibilitySelectedTextRanges() -> [NSValue]? { nil }
    override func accessibilityChildren() -> [Any]? { [] }
}
@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
        main.addItem(appItem); main.addItem(editItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Copy Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
        window = NSWindow(contentRect: NSRect(x: 220, y: 200, width: 700, height: 300),
                          styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "OpenReader Copy Fixture"
        let text = CopyOnlyTextView(frame: NSRect(x: 0,y: 0,width: 700,height: 300))
        text.string = "Copy fallback fixture. Καλημέρα κόσμε."
        text.font = .systemFont(ofSize: 24); text.isEditable = false; text.isSelectable = true
        text.textContainerInset = NSSize(width: 22,height: 24)
        window.contentView = text; window.center(); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: 0,length: (text.string as NSString).length))
        NSApp.activate(ignoringOtherApps: true)
    }
}
@main enum CopySelectionFixture {
    static func main() {
        let app = NSApplication.shared, delegate = FixtureDelegate()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
