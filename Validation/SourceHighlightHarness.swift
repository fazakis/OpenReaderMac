// Compile with production Core/*.swift, Extraction.swift, SourceSelection.swift,
// WordHighlighter.swift. Does not change selection, focus, clipboard or documents.
import AppKit
import ApplicationServices

enum AppError: LocalizedError { case message(String); var errorDescription: String? { switch self { case .message(let s): return s } } }
@main struct SourceHighlightHarness {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        guard CommandLine.arguments.count > 1,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first else { fatalError("Specify source bundle ID") }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?, title: CFTypeRef?
        AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &window)
        if let window { AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) }
        guard (title as? String ?? "").localizedCaseInsensitiveContains("fixture") else { fatalError("Only the test fixture may be inspected") }
        let extractor = TextExtractor()
        let result = try await extractor.selection(SourceApp(pid: app.processIdentifier, name: app.localizedName ?? "App"))
        print("characters",result.text.utf16.count,"anchor",result.anchorID != nil, "source",result.source)
        guard let anchor = result.anchorID else { exit(2) }
        let regex = try NSRegularExpression(pattern: "[\\p{L}\\p{N}]+")
        let words = regex.matches(in: result.text, range: NSRange(location: 0,length: result.text.utf16.count))
        let highlighter = WordHighlighter()
        var success = 0
        for word in words {
            let text = (result.text as NSString).substring(with: word.range)
            let bounds = await extractor.wordBounds(anchorID: anchor, range: word.range, expected: text)
            if let bounds { success += 1; print(text,bounds) } else { print("MISSING",text) }
            if CommandLine.arguments.contains("--show"), let bounds {
                highlighter.show(quartzRects: bounds)
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        highlighter.hide()
        print("mapped",success,"of",words.count)
        if success != words.count { exit(3) }
    }
}
