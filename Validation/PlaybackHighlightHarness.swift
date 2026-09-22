// Runs the real ReaderModel, backend, audio engine and source overlay without
// registering another set of global shortcuts or changing the installed app.
import AppKit
import ApplicationServices
@main struct PlaybackHighlightHarness {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        var source: NSRunningApplication?
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if let front = NSWorkspace.shared.frontmostApplication, ["com.google.Chrome", "com.apple.Preview"].contains(front.bundleIdentifier ?? "") {
                let ax = AXUIElementCreateApplication(front.processIdentifier)
                var window: CFTypeRef?, title: CFTypeRef?
                AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &window)
                if let window { AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) }
                if (title as? String ?? "").localizedCaseInsensitiveContains("fixture") { source = front; break }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        guard let source else { print("No fixture came to the foreground"); exit(1) }
        print("Testing foreground fixture in", source.localizedName ?? "App")
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        let model = ReaderModel(registerShortcuts: false)
        if let saved = UserDefaults(suiteName: "gr.fazakis.OpenReaderMac") {
            model.preferences.connection = Connection.load(from: saved)
        }
        model.preferences.speed = 0.5
        model.perform("selection")
        let start = Date(); var words = Set<String>(), overlays = Set<String>(), paused = false, resumed = false
        while Date().timeIntervalSince(start) < 90 {
            try await Task.sleep(for: .milliseconds(50))
            if let error = model.error { print("FAILED",error); model.stop(); exit(2) }
            if let range = model.audio.currentWord, model.chunks.indices.contains(model.audio.wordChunk) {
                let key = "\(model.audio.wordChunk):\(range.location):\(range.length)"
                words.insert(key)
                if !model.wordHighlighter.visibleRectangles.isEmpty { overlays.insert(key) }
                if !paused, overlays.count >= 3 {
                    model.perform("play"); paused = true
                    let before = model.audio.renderedSampleTime
                    try await Task.sleep(for: .seconds(2))
                    let stable = before == model.audio.renderedSampleTime
                    print("paused retains position",stable,"overlay",!model.wordHighlighter.visibleRectangles.isEmpty)
                    model.perform("play"); resumed = true
                }
            }
            if model.status == "Finished" { break }
        }
        print("source",source.localizedName ?? "unknown","timed words",words.count,"overlaid words",overlays.count,"resumed",resumed,"status",model.status)
        print("overlay hidden on finish",model.wordHighlighter.visibleRectangles.isEmpty)
        model.stop(); model.tunnel.close()
        guard !words.isEmpty, overlays.count == words.count, model.wordHighlighter.visibleRectangles.isEmpty else { exit(3) }
    }
}
