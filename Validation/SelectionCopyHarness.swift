import AppKit
import ApplicationServices

@main enum SelectionCopyHarness {
    @MainActor static func main() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        setbuf(stdout, nil)
        guard AXIsProcessTrusted() else { print("Test process needs Accessibility access."); exit(2) }
        print("Waiting for OpenReader Copy Fixture to be foreground…")
        let focusDeadline = ContinuousClock.now.advanced(by: .seconds(180))
        while NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "org.openreader.CopyFixture", ContinuousClock.now < focusDeadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "org.openreader.CopyFixture" else {
            print("The fixture did not become foreground; live test not performed."); exit(2)
        }
        let board = NSPasteboard.general
        let original = try ClipboardContents.capture(board)
        let model = ReaderModel(registerShortcuts: false, automaticallyPlay: false)
        guard model.preferences.automaticCopyFallback else { print("Fresh default was not enabled"); exit(3) }
        model.perform("selection")
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while model.originalText.isEmpty, model.error == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let expected = "Copy fallback fixture. Καλημέρα κόσμε."
        guard model.originalText == expected, model.note.contains("Copy fallback") else {
            print("FAIL: automatic fallback", model.error ?? model.status); model.stop(); exit(4)
        }
        guard try ClipboardContents.capture(board).items == original.items else {
            print("FAIL: original clipboard not restored"); model.stop(); exit(5)
        }
        print("PASS: production Read selection automatically used the real source Copy command")
        print("PASS: original clipboard items and formats restored")
        print("PASS: original Unicode text preserved and reader-only highlighting reported")
        // Extraction-only mode keeps the fixture independent of backend language support.
        guard model.status == "Text ready" else { print("FAIL: unexpected synthesis path"); exit(6) }
        model.stop(); model.originalText = ""; model.error = nil
        model.preferences.automaticCopyFallback = false
        defer { UserDefaults.standard.removeObject(forKey: "automaticCopyFallback") }
        let disabledCount = board.changeCount
        model.perform("selection")
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while model.error == nil, ContinuousClock.now < secondDeadline { try await Task.sleep(for: .milliseconds(50)) }
        guard model.originalText.isEmpty, model.error != nil, board.changeCount == disabledCount else {
            print("FAIL: disabled fallback copied or read text"); model.stop(); exit(7)
        }
        model.stop()
        print("PASS: disabling fallback prevents Copy and leaves clipboard unchanged")
    }
}
