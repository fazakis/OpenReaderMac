import SwiftUI
import AppKit
import ApplicationServices

@MainActor final class ReaderModel: ObservableObject {
    var preferences = Preferences()
    let audio = AudioPlayback()
    let shortcuts = ShortcutManager()
    let extractor = TextExtractor()
    let selectionClipboard = ClipboardCopyReader()
    let tunnel = SSHTunnel()
    let region = RegionSelector()
    let wordHighlighter = WordHighlighter()
    private var selectionAnchor: UUID?
    private var selectionPID: pid_t?
    private var highlightTask: Task<Void, Never>?
    private var highlightRequest = UUID()
    @Published var wordHighlightStatus = "Sentence highlighting"

    @Published var chunks: [Sentence] = []
    @Published var originalText = ""
    @Published var inputText = ""
    @Published var source = "Ready to read"
    @Published var note = "Select text in another app and press ⌃⌥⌘R."
    @Published var status = "Ready"
    @Published var error: String?
    @Published var voices = ["af_alloy"]
    @Published var isConnecting = false
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var screenGranted = CGPreflightScreenCaptureAccess()
    @Published var ocrLanguages: [String] = []
    var showPlayer: (() -> Void)?
    var togglePlayer: (() -> Void)?
    var showReader: (() -> Void)?
    private var readingTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var requestID = UUID()
    private var lastExternal: SourceApp?
    private var cancellables: Set<AnyCancellable> = []
    init(registerShortcuts: Bool = true) {
        shortcuts.perform = { [weak self] in self?.perform($0) }
        if registerShortcuts {
            shortcuts.register(preferences.shortcuts)
            preferences.$shortcuts.dropFirst().sink { [weak self] in self?.shortcuts.register($0) }.store(in: &cancellables)
        }
        preferences.$speed.sink { [weak self] in self?.audio.setSpeed($0) }.store(in: &cancellables)
        preferences.$volume.sink { [weak self] in self?.audio.setVolume($0) }.store(in: &cancellables)
        preferences.$connection.removeDuplicates().dropFirst().sink { [weak self] _ in self?.stop(); self?.tunnel.close(); self?.status = "Connection or voice changed. Press Play to restart." }.store(in: &cancellables)
        preferences.$automaticCopyFallback.removeDuplicates().dropFirst().sink { [weak self] _ in self?.stop() }.store(in: &cancellables)
        audio.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        shortcuts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Coalesce the two published timing fields before consulting their final values.
        audio.$currentWord.combineLatest(audio.$wordChunk)
            .debounce(for: .milliseconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateSourceHighlight(replace: true) }.store(in: &cancellables)
        // Refresh geometry during scrolling, zooming and paused playback too.
        Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateSourceHighlight(replace: false) }.store(in: &cancellables)
        preferences.$highlightWords.dropFirst().sink { [weak self] enabled in
            if !enabled { self?.highlightTask?.cancel(); self?.wordHighlighter.hide() }
        }.store(in: &cancellables)
        audio.didFinish = { [weak self] in self?.status = "Finished" }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink { [weak self] notification in
            self?.wordHighlighter.hide()
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastExternal = SourceApp(pid: app.processIdentifier, name: app.localizedName ?? "Application")
        }.store(in: &cancellables)
        if let a = NSWorkspace.shared.frontmostApplication, a.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternal = SourceApp(pid: a.processIdentifier, name: a.localizedName ?? "Application") }
        Task { ocrLanguages = (try? await extractor.languages()) ?? [] }
    }
    private func updateSourceHighlight(replace: Bool) {
        if replace { highlightTask?.cancel(); highlightTask = nil }
        guard audio.isActive, let range = audio.currentWord, preferences.highlightWords,
              chunks.indices.contains(audio.wordChunk), NSMaxRange(range) <= (chunks[audio.wordChunk].text as NSString).length else {
            wordHighlighter.hide(); return
        }
        guard let anchor = selectionAnchor, let pid = selectionPID else {
            wordHighlightStatus = "Words in reader · source word positions unavailable"; wordHighlighter.hide(); return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { wordHighlighter.hide(); return }
        guard highlightTask == nil else { return }
        let chunk = audio.wordChunk
        let offset = chunks.prefix(chunk).reduce(0) { $0 + ($1.text as NSString).length }
        let globalRange = NSRange(location: offset+range.location, length: range.length)
        let expected = (chunks[chunk].text as NSString).substring(with: range)
        let request = UUID(); highlightRequest = request
        highlightTask = Task {
            let bounds = await extractor.wordBounds(anchorID: anchor, range: globalRange, expected: expected)
            guard request == highlightRequest, !Task.isCancelled else { return }
            highlightTask = nil
            guard audio.isActive, audio.currentWord == range, audio.wordChunk == chunk,
                  preferences.highlightWords, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            if let bounds {
                wordHighlighter.show(quartzRects: bounds)
                wordHighlightStatus = "Word highlighting in source · verified Kokoro timing"
            } else {
                wordHighlighter.hide()
                wordHighlightStatus = "Words in reader · source word is offscreen or unavailable"
            }
        }
    }
    func refreshPermissions() { accessibilityGranted = AXIsProcessTrusted(); screenGranted = CGPreflightScreenCaptureAccess() }
    func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openPrivacy("Accessibility")
    }
    func requestScreen() { CGRequestScreenCaptureAccess(); openPrivacy("ScreenCapture") }
    func openPrivacy(_ pane: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")!) }
    private func sourceApp() throws -> SourceApp {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { return SourceApp(pid: app.processIdentifier, name: app.localizedName ?? "Application") }
        if let lastExternal { return lastExternal }
        throw AppError.message("Focus the application you want to read, then use the global shortcut.")
    }
    func perform(_ action: String) {
        switch action {
        case "selection", "window": extract(mode: action)
        case "region": selectRegion()
        case "clipboard":
            guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "The clipboard contains no text."; showPlayer?(); return }
            accept(ExtractedText(text: text, source: "Clipboard", note: "Explicit clipboard command"))
        case "play": if audio.isActive { audio.togglePause() } else if !chunks.isEmpty { play(from: min(audio.currentChunk, chunks.count-1)) } else { showReader?() }
        case "stop": stop()
        case "previous": navigate(-1)
        case "next": navigate(1)
        case "slower": preferences.speed = max(0.5, ((preferences.speed-0.1)*10).rounded()/10)
        case "faster": preferences.speed = min(3, ((preferences.speed+0.1)*10).rounded()/10)
        case "player": togglePlayer?()
        default: break
        }
    }
    func pasteAndRead() { accept(ExtractedText(text: inputText, source: "Pasted text", note: "Original wording · No rewriting")) }
    private func extract(mode: String) {
        do {
            let captured = try sourceApp() // Capture PID before opening any UI.
            stop(); status = "Extracting from \(captured.name)…"; let id = requestID
            extractionTask = Task {
                do {
                    let result: ExtractedText
                    if mode == "selection" {
                        do { result = try await extractor.selection(captured) }
                        catch let missing as SelectionUnavailable {
                            guard preferences.automaticCopyFallback, let token = missing.copyToken else { throw missing }
                            try Task.checkCancellation()
                            guard id == requestID, NSWorkspace.shared.frontmostApplication?.processIdentifier == captured.pid else {
                                throw AppError.message("Return to the source app and use the Read selection shortcut to allow Copy fallback.")
                            }
                            status = "Reading selection with Copy…"
                            try await extractor.prepareSelectionCopy(token)
                            let extractor = self.extractor
                            let text = try await selectionClipboard.read(sourceIsCurrent: {
                                await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == captured.pid }
                            }, copy: { try await extractor.performSelectionCopy(token) })
                            result = ExtractedText(text: text, source: captured.name, note: "Selected text · Copy fallback · Word highlighting in reader only")
                        }
                    }
                    else {
                        let (accessible, target) = try await extractor.activeWindow(captured)
                        if let accessible { result = accessible }
                        else {
                            let image = try await ScreenReader.captureWindow(target)
                            result = try await extractor.recognize(image, language: preferences.ocrLanguage, source: captured.name)
                        }
                    }
                    guard id == requestID, !Task.isCancelled else { return }; selectionPID = captured.pid; accept(result)
                } catch { if id == requestID && !Task.isCancelled { self.error = error.localizedDescription; status = "Reading needs attention"; showPlayer?() } }
            }
        } catch { self.error = error.localizedDescription; showPlayer?() }
    }
    private func selectRegion() {
        stop(); refreshPermissions()
        guard screenGranted else { error = "Enable Screen Recording in Settings, then select a region again."; showPlayer?(); return }
        let id = requestID
        region.begin { [weak self] rect, displayID in
            guard let self else { return }
            self.extractionTask = Task {
                do {
                    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
                    for app in apps {
                        if await self.extractor.secureFieldIntersects(pid: app.processIdentifier, rect: rect) { throw AppError.message("The region intersects a secure text field. Choose a region without it.") }
                    }
                    try Task.checkCancellation()
                    let image = try await ScreenReader.captureRegion(rect, displayID: displayID)
                    let text = try await self.extractor.recognize(image, language: self.preferences.ocrLanguage, source: "Screen region")
                    guard id == self.requestID, !Task.isCancelled else { return }; self.accept(text)
                } catch { if id == self.requestID && !Task.isCancelled { self.error = error.localizedDescription; self.showPlayer?() } }
            }
        }
    }
    func accept(_ text: ExtractedText) {
        stop(); error = nil
        guard text.text.count <= 500_000 else { error = "This reading exceeds the app’s 500,000-character bound. Select a smaller passage."; return }
        selectionAnchor = text.anchorID; wordHighlightStatus = "Sentence highlighting until valid word timing arrives"
        originalText = text.text; chunks = Segmenter.split(text.text); source = text.source; note = text.note
        showPlayer?()
        guard !chunks.isEmpty else { error = "Enter or select some text first."; return }
        if Segmenter.containsGreek(text.text) {
            status = "Greek speech unavailable"
            error = "Your verified Kokoro service has no Greek language pipeline or Greek voice. The original text is preserved in the reader. Greek and mixed Greek/English speech are disabled rather than mispronounced, translated, or sent to another provider."
            showReader?(); return
        }
        play(from: 0)
    }
    func connect() {
        guard !isConnecting else { return }; isConnecting = true; error = nil
        Task {
            defer { isConnecting = false }
            do {
                let c = preferences.connection; try await tunnel.ensure(c)
                let fetched = try await SpeechBackend(connection: c, token: SecretStore.read(SecretStore.key(for: c.serverURL))).voices()
                guard c == preferences.connection else { return }
                voices = fetched; status = "Connected · Kokoro · \(voices.count) voices"
                if !voices.contains(c.voice) { error = "The selected voice is unavailable. Choose one from the live voice list." }
            } catch { self.error = error.localizedDescription; status = "Connection failed" }
        }
    }
    func play(from index: Int) {
        guard chunks.indices.contains(index) else { return }
        guard !Segmenter.containsGreek(originalText) else { error = "Greek speech is unsupported by your verified Kokoro service."; return }
        stop(); error = nil; status = "Connecting…"
        let c = preferences.connection, segments = chunks, id = requestID
        readingTask = Task {
            do {
                try await tunnel.ensure(c); try Task.checkCancellation()
                let backend = SpeechBackend(connection: c, token: SecretStore.read(SecretStore.key(for: c.serverURL)))
                let available = try await backend.voices(); try Task.checkCancellation()
                guard id == requestID else { return }
                voices = available
                guard voices.contains(c.voice) else { throw AppError.message("The configured voice is not in the live backend voice list.") }
                let epoch = try audio.begin(at: index); status = "Reading"
                for i in index..<segments.count {
                    // One streamed request at a time; no more than one following chunk is prefetched.
                    while audio.currentChunk < i-1 || audio.pendingFrames >= 24_000*8 || audio.isPaused {
                        try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(50))
                    }
                    try Task.checkCancellation()
                    if preferences.highlightWords {
                        try await backend.captioned(text: segments[i].text) { [weak self] data, words in
                            guard let self else { throw CancellationError() }
                            for offset in stride(from: 0, to: data.count, by: 8192) {
                                try Task.checkCancellation()
                                let piece = data.subdata(in: offset..<min(offset+8192,data.count))
                                try await self.audio.append(piece, chunk: i, epoch: epoch, words: offset == 0 ? words : nil)
                            }
                        }
                    } else {
                        try await backend.stream(text: segments[i].text) { [weak self] data in
                            guard let self else { throw CancellationError() }
                            try await self.audio.append(data, chunk: i, epoch: epoch)
                        }
                    }
                }
                guard id == requestID else { return }; audio.finish(epoch: epoch)
            } catch {
                guard id == requestID, !Task.isCancelled else { return }
                audio.stop(); self.error = error.localizedDescription; status = "Playback stopped"
            }
        }
    }
    func navigate(_ direction: Int) {
        guard !chunks.isEmpty else { return }
        let current = min(audio.currentChunk, chunks.count-1), sid = chunks[current].sentenceID
        let target = direction > 0 ? chunks.firstIndex { $0.sentenceID > sid } : chunks.firstIndex { $0.sentenceID == max(0, sid-1) }
        if let target { play(from: target) }
    }
    func stop() {
        requestID = UUID(); readingTask?.cancel(); extractionTask?.cancel(); readingTask = nil; extractionTask = nil
        highlightRequest = UUID(); highlightTask?.cancel(); highlightTask = nil; wordHighlighter.hide(); audio.stop(); region.cancel(); status = "Stopped"
    }
    func shortcut(_ id: String) -> String { preferences.shortcuts.first { $0.id == id }?.label ?? "" }
}
import Combine
