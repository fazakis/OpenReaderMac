import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

struct SourceApp: Sendable {
    let pid: pid_t
    let name: String
}
struct ExtractedText: Sendable {
    let text: String
    let source: String
    let note: String
    var anchorID: UUID? = nil
}
struct WindowTarget: Sendable {
    let pid: pid_t
    let title: String
    let frame: CGRect
}

actor TextExtractor {
    private var anchor: (UUID, SourceSelection)?
    private var copyTarget: SelectionCopyTarget?
    func wordBounds(anchorID: UUID, range: NSRange, expected: String) -> [CGRect]? {
        guard let (id, source) = anchor, id == anchorID else { return nil }
        return source.bounds(range: range, expected: expected)
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(parent, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    private func string(_ e: AXUIElement, _ attr: String) -> String { value(e, attr) as? String ?? "" }
    private func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = value(e, kAXPositionAttribute), let s = value(e, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    private func isSecure(_ e: AXUIElement) -> Bool {
        string(e, kAXSubroleAttribute) == kAXSecureTextFieldSubrole || string(e, kAXRoleAttribute) == "AXSecureTextField"
    }
    private func app(_ source: SourceApp) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw AppError.message("Accessibility access is required. Enable OpenReader Mac in System Settings → Privacy & Security → Accessibility, then retry. You can also explicitly read the clipboard or choose a region.") }
        guard source.pid != ProcessInfo.processInfo.processIdentifier else { throw AppError.message("Focus the source application first, then use a global reading shortcut.") }
        let app = AXUIElementCreateApplication(source.pid); AXUIElementSetMessagingTimeout(app, 0.25); return app
    }
    private func readFocus(_ app: AXUIElement) -> SelectionFocusRead<AXUIElement> {
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &raw)
        if result == .noValue { return .noValue }
        guard result == .success else { return .failed(result.rawValue) }
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .failed(AXError.failure.rawValue) }
        return .found(raw as! AXUIElement)
    }
    private func selectionFocus(_ app: AXUIElement, source: SourceApp) async throws -> AXUIElement {
        let initial = readFocus(app)
        let chromeIDs = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"]
        let isChrome = NSRunningApplication(processIdentifier: source.pid)?.bundleIdentifier.map { chromeIDs.contains($0) } ?? false
        var result = initial
        if isChrome, case .noValue = initial, let window = element(app, kAXFocusedWindowAttribute) {
            let document = string(window, kAXDocumentAttribute), title = string(window, kAXTitleAttribute)
            let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.25)
            do {
                result = try await SelectionFocusRecovery.recover(initial: initial, eligible: true, initialize: {
                    // Chrome activates native accessibility when its application role is read.
                    var role: CFTypeRef?
                    return AXUIElementCopyAttributeValue(app, kAXRoleAttribute as CFString, &role) == .success
                }, read: { self.readFocus(app) }, contextIsCurrent: {
                    guard let front = self.element(system, kAXFocusedApplicationAttribute) else { return false }
                    var pid: pid_t = 0
                    guard AXUIElementGetPid(front, &pid) == .success, pid == source.pid,
                          let current = self.element(app, kAXFocusedWindowAttribute), CFEqual(current, window) else { return false }
                    return (document.isEmpty || self.string(current, kAXDocumentAttribute) == document)
                        && (title.isEmpty || self.string(current, kAXTitleAttribute) == title)
                })
            } catch SelectionFocusRecoveryError.sourceChanged {
                throw AppError.message("The source app, window, or document changed while Chrome initialized accessibility. Return to the selection and retry.")
            }
        }
        try Task.checkCancellation()
        switch result {
        case .found(let focused): return focused
        case .noValue:
            throw AppError.message("\(source.name) has not exposed its focused selection. Keep its document foreground, select text, and retry. You can also copy it and use Read clipboard, or choose a screen region.")
        case .failed(let code):
            throw AppError.message("Could not query \(source.name)’s accessibility focus (error \(code)). Check Accessibility access for the installed OpenReader app, then retry.")
        }
    }
    func selection(_ source: SourceApp) async throws -> ExtractedText {
        try Task.checkCancellation()
        anchor = nil; copyTarget = nil
        let app = try app(source)
        let focused = try await selectionFocus(app, source: source)
        var ancestor: AXUIElement? = focused
        for _ in 0..<50 {
            guard let item = ancestor else { break }
            if isSecure(item) { throw AppError.message("Secure text fields are never read.") }
            ancestor = element(item, kAXParentAttribute)
        }
        copyTarget = try? SelectionCopyTarget(app: app)
        let (text, positions) = try SourceSelection.capture(focused: focused, window: element(app, kAXFocusedWindowAttribute), pid: source.pid)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SelectionUnavailable(source: source.name, copyToken: copyTarget?.token) }
        let id = positions.map { positions -> UUID in
            let id = UUID(); anchor = (id, positions); return id
        }
        return ExtractedText(text: text, source: source.name, note: id == nil ? "Selected text · Word positions unavailable in this view" : "Selected text · Source word highlighting available", anchorID: id)
    }
    func prepareSelectionCopy(_ token: UUID) throws {
        guard let copyTarget, copyTarget.token == token else { throw CancellationError() }
        try copyTarget.prepare()
    }
    func performSelectionCopy(_ token: UUID) throws {
        guard let copyTarget, copyTarget.token == token else { throw CancellationError() }
        try copyTarget.perform()
    }
    func activeWindow(_ source: SourceApp) throws -> (ExtractedText?, WindowTarget) {
        let app = try app(source)
        guard let window = element(app, kAXFocusedWindowAttribute), let bounds = frame(window) else { throw AppError.message("The source application does not expose its active window. Choose a screen region explicitly.") }
        let target = WindowTarget(pid: source.pid, title: string(window, kAXTitleAttribute), frame: bounds)
        var entries: [(String, CGRect)] = [], secure = false, visited = 0
        let deadline = Date().addingTimeInterval(3)
        func walk(_ e: AXUIElement, clip: CGRect, depth: Int) {
            guard depth < 35, visited < 4000, Date() < deadline, !Task.isCancelled else { return }; visited += 1
            let box = frame(e) ?? clip
            guard box.intersects(clip) else { return }
            if isSecure(e) { secure = true; return }
            let role = string(e, kAXRoleAttribute)
            let children = value(e, kAXVisibleChildrenAttribute) as? [AXUIElement] ?? value(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let nextClip = role == kAXScrollAreaRole ? box.intersection(clip) : clip
            if role == kAXTextAreaRole || role == kAXTextFieldRole {
                // Restrict large editors to the visible range; do not read offscreen documents.
                if let range = value(e, kAXVisibleCharacterRangeAttribute) {
                    var result: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(e, kAXStringForRangeParameterizedAttribute as CFString, range, &result) == .success, let text = result as? String, !text.isEmpty { entries.append((text, box)); return }
                }
                if children.isEmpty && clip.contains(box) {
                    let text = string(e, kAXValueAttribute)
                    if !text.isEmpty && text.count <= 1500 { entries.append((text, box)); return }
                }
            } else if role == kAXStaticTextRole && children.isEmpty && clip.contains(box) {
                let text = string(e, kAXValueAttribute)
                if !text.isEmpty { entries.append((text, box)); return }
            }
            for child in children { walk(child, clip: nextClip, depth: depth+1) }
        }
        walk(window, clip: bounds, depth: 0)
        if secure { throw AppError.message("The active window contains a secure field. Choose a region that excludes it; this window will not be captured.") }
        // Keep AX document order. Only collapse duplicate representations at the same position.
        var seen: Set<String> = []
        let text = entries.filter { seen.insert("\($0.0)|\(Int($0.1.minX))|\(Int($0.1.minY))").inserted }.map(\.0).joined(separator: "\n")
        return (text.isEmpty ? nil : ExtractedText(text: text, source: source.name, note: "Visible window text · Accessibility"), target)
    }
    func secureFieldIntersects(pid: pid_t, rect: CGRect) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.1)
        var visits = 0
        func walk(_ e: AXUIElement, depth: Int) -> Bool {
            visits += 1; guard visits < 1500, depth < 25 else { return false }
            if isSecure(e), let box = frame(e), box.intersects(rect) { return true }
            return (value(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains { walk($0, depth: depth+1) }
        }
        return walk(app, depth: 0)
    }
    func languages() throws -> [String] { try VNRecognizeTextRequest().supportedRecognitionLanguages() }
    func recognize(_ image: CGImage, language: String, source: String) throws -> ExtractedText {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let available = try request.supportedRecognitionLanguages()
        let wanted = language == "mixed" ? ["en", "el"] : [language]
        let supported = wanted.compactMap { code in available.first { $0 == code || $0.hasPrefix(code + "-") } }
        guard supported.count == wanted.count else { throw AppError.message("This macOS Vision installation does not support \(language == "mixed" ? "English + Greek" : language) OCR. Available languages: \(available.joined(separator: ", ")). Use accessible selected text or paste the original text instead.") }
        request.recognitionLanguages = supported; request.automaticallyDetectsLanguage = wanted.count > 1
        try VNImageRequestHandler(cgImage: image).perform([request]); try Task.checkCancellation()
        let observations = request.results ?? []
        let blocks = observations.compactMap { observation -> OCRBlock? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return OCRBlock(text: text, bounds: CGRect(x: box.minX, y: 1-box.maxY, width: box.width, height: box.height))
        }
        let text = ReadingOrder.ordered(blocks).map(\.text).joined(separator: "\n")
        guard !text.isEmpty else { throw AppError.message("No readable text was found in this capture.") }
        return ExtractedText(text: text, source: source, note: "Local Vision OCR · Review accuracy and column order")
    }
}

@MainActor enum ScreenReader {
    static func captureWindow(_ target: WindowTarget) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw AppError.message("Screen Recording permission is required for OCR. Grant it in Settings, then relaunch OpenReader Mac if macOS requests it.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windows = content.windows.filter { $0.owningApplication?.processID == target.pid && $0.windowLayer == 0 }
        guard let window = windows.min(by: { distance($0.frame, target.frame) < distance($1.frame, target.frame) }), distance(window.frame, target.frame) < 80 else { throw AppError.message("The active window changed before capture. Retry or select a region.") }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration(); let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale); config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false; config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat { abs(a.minX-b.minX)+abs(a.minY-b.minY)+abs(a.width-b.width)+abs(a.height-b.height) }
    static func captureRegion(_ rect: CGRect, displayID: CGDirectDisplayID) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw AppError.message("Enable Screen Recording in Settings before choosing a region.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw AppError.message("The selected display disconnected.") }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let area = rect.intersection(display.frame)
        guard area.width > 3, area.height > 3 else { throw AppError.message("Select a larger region within one display.") }
        let config = SCStreamConfiguration()
        config.sourceRect = CaptureGeometry.displayLocal(area, displayFrame: display.frame)
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(area.width*scale); config.height = Int(area.height*scale)
        config.showsCursor = false; config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
