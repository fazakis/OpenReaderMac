import AppKit

/// Runs pasteboard IPC away from the UI thread. Only a requested Copy is observed;
/// this is not a clipboard monitor. No clipboard data is written to disk.
actor ClipboardCopyReader {
    private let name: String
    private var busy = false
    init(name: String = NSPasteboard.Name.general.rawValue) { self.name = name }

    func read(sourceIsCurrent: @escaping @Sendable () async -> Bool,
              copy: @escaping @Sendable () async throws -> Void,
              timeout: TimeInterval = 1.2) async throws -> String {
        while busy { try await Task.sleep(for: .milliseconds(20)) }
        try Task.checkCancellation()
        busy = true
        defer { busy = false }
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        let original = try ClipboardContents.capture(board)
        guard await sourceIsCurrent(), try original.matches(board) else { throw ClipboardCopyError.changed }
        try Task.checkCancellation()
        var dispatchError: Error?
        do { try await copy() }
        catch ClipboardCopyError.deliveryUncertain { dispatchError = ClipboardCopyError.deliveryUncertain }
        catch { throw error }
        // Even after cancellation, allow an already-dispatched Copy a bounded time
        // to finish so its clipboard change can be restored. No speech starts here.
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        var copied: ClipboardContents?
        while ContinuousClock.now < deadline {
            let count = board.changeCount
            if count != original.changeCount {
                // More than one new owner is ambiguous: never overwrite it.
                guard count == original.changeCount + 1, await sourceIsCurrent() else { throw ClipboardCopyError.changed }
                let candidate = try ClipboardContents.capture(board)
                if !candidate.items.isEmpty {
                    if let copied {
                        guard candidate == copied else { throw ClipboardCopyError.changed }
                        // Final compare immediately before restoring, without a suspension.
                        guard try copied.matches(board) else { throw ClipboardCopyError.changed }
                        try original.restore(to: board)
                        try Task.checkCancellation()
                        if let dispatchError { throw dispatchError }
                        guard let text = copied.plainText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw ClipboardCopyError.noText
                        }
                        guard text.count <= 500_000 else { throw ClipboardCopyError.tooLarge }
                        return text
                    }
                    copied = candidate
                }
            }
            await Self.cleanupDelay()
        }
        try Task.checkCancellation()
        if let dispatchError { throw dispatchError }
        throw ClipboardCopyError.timeout
    }

    private static func cleanupDelay() async {
        // Intentionally independent of task cancellation for clipboard cleanup only.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) { continuation.resume() }
        }
    }
}

enum ClipboardCopyError: LocalizedError {
    case changed, cannotPreserve, tooLarge, noText, timeout, restoreFailed, deliveryUncertain
    var errorDescription: String? {
        switch self {
        case .changed: return "The source or clipboard changed during Copy. Current clipboard contents were kept. Select the text again and retry."
        case .cannotPreserve: return "The current clipboard contains data that cannot be safely preserved. Copy the selected text yourself and choose Read clipboard."
        case .tooLarge: return "The clipboard is too large for automatic Copy. Copy a smaller selection yourself and choose Read clipboard."
        case .noText: return "The app’s Copy command returned no readable plain text. Your previous clipboard was restored. Use Read clipboard or choose a screen region explicitly."
        case .timeout: return "The app’s Copy command did not return text in time. Copy the selection yourself and choose Read clipboard."
        case .deliveryUncertain: return "The source app did not confirm its Copy command. Reading was stopped; copy the selection yourself and choose Read clipboard."
        case .restoreFailed: return "macOS could not restore every clipboard format. Reading was stopped."
        }
    }
}

struct ClipboardContents: Equatable, Sendable {
    struct Representation: Equatable, Sendable { let type: String; let data: Data }
    let changeCount: Int
    let items: [[Representation]]

    static func capture(_ board: NSPasteboard) throws -> Self {
        let count = board.changeCount
        let sourceItems = board.pasteboardItems ?? []
        guard sourceItems.count <= 32 else { throw ClipboardCopyError.tooLarge }
        var items: [[Representation]] = [], bytes = 0
        for item in sourceItems {
            guard item.types.count <= 128 else { throw ClipboardCopyError.tooLarge }
            var formats: [Representation] = []
            for type in item.types.sorted(by: { $0.rawValue < $1.rawValue }) {
                // Promised files may require the source application or block indefinitely.
                guard !type.rawValue.lowercased().contains("promise"), let data = item.data(forType: type) else {
                    throw ClipboardCopyError.cannotPreserve
                }
                bytes += data.count
                guard bytes <= 16 * 1024 * 1024 else { throw ClipboardCopyError.tooLarge }
                formats.append(Representation(type: type.rawValue, data: data))
            }
            items.append(formats)
        }
        guard count == board.changeCount else { throw ClipboardCopyError.changed }
        return Self(changeCount: count, items: items)
    }
    func matches(_ board: NSPasteboard) throws -> Bool {
        guard board.changeCount == changeCount else { return false }
        return try Self.capture(board) == self
    }
    func restore(to board: NSPasteboard) throws {
        let objects = items.map { formats in
            let item = NSPasteboardItem()
            for format in formats { item.setData(format.data, forType: NSPasteboard.PasteboardType(format.type)) }
            return item
        }
        board.clearContents()
        if !objects.isEmpty, !board.writeObjects(objects) { throw ClipboardCopyError.restoreFailed }
    }
    var plainText: String? {
        let parts = items.compactMap { formats -> String? in
            for type in [NSPasteboard.PasteboardType.string.rawValue, "public.utf16-plain-text", "public.plain-text", "NSStringPboardType"] {
                if let data = formats.first(where: { $0.type == type })?.data,
                   let text = String(data: data, encoding: type.contains("utf16") ? .utf16 : .utf8) { return text }
            }
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
