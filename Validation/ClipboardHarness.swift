import AppKit

/// Tests the production transaction using named pasteboards, never the user's clipboard.
@main enum ClipboardHarness {
    static func main() async throws {
        let name = "OpenReaderClipboardTests-" + UUID().uuidString
        let pb = NSPasteboard(name: NSPasteboard.Name(name))
        defer { pb.releaseGlobally() }
        let reader = ClipboardCopyReader(name: name)
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1; print("PASS: \(name)")
        }
        func write(_ text: String) { pb.clearContents(); pb.setString(text, forType: .string) }
        func seedRich() throws -> ClipboardContents {
            pb.clearContents()
            let a = NSPasteboardItem(), b = NSPasteboardItem()
            a.setString("Original Καλημέρα 👩🏽‍💻", forType: .string)
            a.setData(Data([1,2,3,4]), forType: NSPasteboard.PasteboardType("org.openreader.fixture"))
            b.setString("second item", forType: .string)
            pb.writeObjects([a,b])
            return try ClipboardContents.capture(pb)
        }
        let original = try seedRich()
        let text = try await reader.read(sourceIsCurrent: { true }, copy: {
            let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("Selected text Καλημέρα 👩🏽‍💻", forType: .string)
        })
        check(text == "Selected text Καλημέρα 👩🏽‍💻", "Return only newly copied Unicode text")
        check(try ClipboardContents.capture(pb).items == original.items, "Restore multiple items and every captured format")
        pb.clearContents()
        _ = try await reader.read(sourceIsCurrent: { true }, copy: {
            let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("one", forType: .string)
        })
        check(pb.pasteboardItems?.isEmpty != false, "Restore an originally empty clipboard")
        write("existing text must never be read")
        let unchanged = pb.changeCount
        do { _ = try await reader.read(sourceIsCurrent: { true }, copy: {}, timeout: 0.15); check(false,"No-op Copy must time out") }
        catch ClipboardCopyError.timeout { check(pb.changeCount == unchanged, "No-op Copy leaves old clipboard untouched and unread") }
        write("original")
        do {
            _ = try await reader.read(sourceIsCurrent: { true }, copy: {
                let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("first copy", forType: .string)
                p.clearContents(); p.setString("newer clipboard", forType: .string)
            }); check(false,"Two ownership changes must fail")
        } catch ClipboardCopyError.changed { check(pb.string(forType: .string) == "newer clipboard", "Preserve a newer clipboard owner") }
        write("original")
        do {
            _ = try await reader.read(sourceIsCurrent: { true }, copy: {
                let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("copied", forType: .string)
                Task {
                    try await Task.sleep(for: .milliseconds(20))
                    p.setString("modified without ownership change", forType: .string)
                }
            }); check(false,"Changed data must fail")
        } catch ClipboardCopyError.changed { check(pb.string(forType: .string) == "modified without ownership change", "Detect data changes even with the same owner count") }
        write("original before cancelled copy")
        let cancelled = Task {
            try await reader.read(sourceIsCurrent: { true }, copy: {
                Task {
                    try await Task.sleep(for: .milliseconds(100))
                    let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("late copy", forType: .string)
                }
            })
        }
        try await Task.sleep(for: .milliseconds(30)); cancelled.cancel()
        do { _ = try await cancelled.value; check(false,"Cancelled reading must not return text") }
        catch is CancellationError { check(pb.string(forType: .string) == "original before cancelled copy", "Cancel speech while restoring an in-flight late Copy") }
        write("original before nontext")
        do {
            _ = try await reader.read(sourceIsCurrent: { true }, copy: {
                let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setData(Data([0,1,2]), forType: .png)
            }); check(false,"Nontext must fail")
        } catch ClipboardCopyError.noText { check(pb.string(forType: .string) == "original before nontext", "Restore clipboard when Copy returns no text") }
        write("original before focus change")
        let beforeFocus = pb.changeCount
        do { _ = try await reader.read(sourceIsCurrent: { false }, copy: { fatalError("Copy must not run") }); check(false,"Wrong source must fail") }
        catch ClipboardCopyError.changed { check(pb.changeCount == beforeFocus, "Do not dispatch Copy after source focus changes") }
        pb.clearContents(); pb.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"))
        let promised = pb.changeCount
        do { _ = try await reader.read(sourceIsCurrent: { true }, copy: { fatalError("Copy must not run") }); check(false,"Promised data must fail") }
        catch ClipboardCopyError.cannotPreserve { check(pb.changeCount == promised, "Refuse promised clipboard data before invoking Copy") }
        pb.clearContents(); pb.setData(Data(repeating: 0,count: 16*1024*1024+1), forType: NSPasteboard.PasteboardType("org.openreader.fixture"))
        let oversized = pb.changeCount
        do { _ = try await reader.read(sourceIsCurrent: { true }, copy: { fatalError("Copy must not run") }); check(false,"Oversized data must fail") }
        catch ClipboardCopyError.tooLarge { check(pb.changeCount == oversized, "Refuse an oversized clipboard before invoking Copy") }
        write("original before failed dispatch")
        let failed = pb.changeCount
        do { _ = try await reader.read(sourceIsCurrent: { true }, copy: { throw CancellationError() }); check(false,"Cancelled dispatch must fail") }
        catch is CancellationError { check(pb.changeCount == failed, "No clipboard changes when cancelled before dispatch") }
        write("original before ambiguous dispatch")
        do {
            _ = try await reader.read(sourceIsCurrent: { true }, copy: {
                let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("copied", forType: .string)
                throw ClipboardCopyError.deliveryUncertain
            }); check(false,"Ambiguous dispatch must fail")
        } catch ClipboardCopyError.deliveryUncertain { check(pb.string(forType: .string) == "original before ambiguous dispatch", "Restore an observed Copy even if delivery acknowledgement fails") }
        write("original before replacement reading")
        let previousReading = Task {
            try await reader.read(sourceIsCurrent: { true }, copy: {
                Task {
                    try await Task.sleep(for: .milliseconds(100))
                    let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("old reading", forType: .string)
                }
            })
        }
        try await Task.sleep(for: .milliseconds(30)); previousReading.cancel()
        let replacement = try await reader.read(sourceIsCurrent: { true }, copy: {
            let p = NSPasteboard(name: NSPasteboard.Name(name)); p.clearContents(); p.setString("replacement reading", forType: .string)
        })
        do { _ = try await previousReading.value; check(false,"Previous request must stay cancelled") }
        catch is CancellationError { check(replacement == "replacement reading", "Serialize a new reading behind cancelled Copy cleanup") }
        check(pb.string(forType: .string) == "original before replacement reading", "Preserve original clipboard across replacement requests")
        print("\(passed) native clipboard checks passed.")
    }
}
