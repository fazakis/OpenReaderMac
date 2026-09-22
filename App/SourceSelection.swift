import AppKit
import ApplicationServices

/// Used only on TextExtractor's actor. All access to the source is read-only.
final class SourceSelection {
    private struct Leaf { let element: AXUIElement; let fragment: SourceTextFragment }
    let pid: pid_t
    private let owner: AXUIElement
    private let window: AXUIElement?
    private let document: String?
    private let elements: [AXUIElement]
    private let spans: [SourceTextSpan]
    private let text: NSString

    private init(pid: pid_t, owner: AXUIElement, window: AXUIElement?, text: String, elements: [AXUIElement], spans: [SourceTextSpan]) {
        self.pid = pid; self.owner = owner; self.window = window; self.text = text as NSString
        self.elements = elements; self.spans = spans
        document = window.flatMap { Self.value($0, kAXDocumentAttribute) as? String }
    }

    static func capture(focused: AXUIElement, window: AXUIElement?, pid: pid_t) throws -> (String, SourceSelection?) {
        let deadline = Date().addingTimeInterval(4)
        var visited = 0
        func selectedText(_ e: AXUIElement) -> String {
            if let text = value(e, kAXSelectedTextAttribute) as? String, !text.isEmpty { return text }
            if let range = value(e, "AXSelectedTextMarkerRange"),
               let text = parameter(e, "AXStringForTextMarkerRange", range) as? String, !text.isEmpty { return text }
            if let range = range(value(e, kAXSelectedTextRangeAttribute)), range.length > 0 { return string(e, range) ?? "" }
            return ""
        }
        // Chromium's embedded PDF keeps its selection on an inner web area.
        func findSelection(_ e: AXUIElement, depth: Int) -> (AXUIElement, String)? {
            guard depth < 40, visited < 6000, Date() < deadline, !Task.isCancelled, !secure(e) else { return nil }
            visited += 1
            let text = selectedText(e)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return (e, text) }
            for child in children(e) { if let found = findSelection(child, depth: depth+1) { return found } }
            return nil
        }
        guard let (owner, text) = findSelection(focused, depth: 0) else { return ("", nil) }
        guard (text as NSString).length <= 1_000_000 else { throw AppError.message("Select a smaller passage to read and highlight.") }
        let selected = range(value(owner, kAXSelectedTextRangeAttribute))
        let role = value(owner, kAXRoleAttribute) as? String
        // Native editors and browser input fields already provide local character ranges.
        if let selected, selected.length == (text as NSString).length,
           role == kAXTextAreaRole || role == kAXTextFieldRole || role == kAXStaticTextRole,
           string(owner, selected) == text,
           let spans = SourceTextMap.align(text, fragments: [SourceTextFragment(text: text, sourceOffset: selected.location)]) {
            return (text, SourceSelection(pid: pid, owner: owner, window: window, text: text, elements: [owner], spans: spans))
        }
        // PDFKit publishes the whole document selection on each leaf, but a *local*
        // selected range on that leaf. Never use AXSelectedText as the leaf's value.
        var leaves: [Leaf] = [], selectedLeaves: [Leaf] = [], units = 0
        visited = 0
        var seen = Set<CFHashCode>()
        func collect(_ e: AXUIElement, depth: Int) {
            guard depth < 40, visited < 6000, units <= 1_000_000, Date() < deadline, !Task.isCancelled, !secure(e) else { return }
            visited += 1
            let role = value(e, kAXRoleAttribute) as? String
            if role == kAXStaticTextRole || role == kAXTextAreaRole || role == kAXTextFieldRole {
                if let selected = range(value(e, kAXSelectedTextRangeAttribute)), selected.length > 0,
                   let part = string(e, selected), !part.isEmpty {
                    selectedLeaves.append(Leaf(element: e, fragment: SourceTextFragment(text: part, sourceOffset: selected.location)))
                }
                if let text = value(e, kAXValueAttribute) as? String, !text.isEmpty {
                    // Element identity, not text, distinguishes repeated words/paragraphs.
                    // The tree is normally acyclic; retaining duplicates would fail alignment.
                    if seen.insert(CFHash(e)).inserted { leaves.append(Leaf(element: e, fragment: SourceTextFragment(text: text))); units += text.utf16.count }
                    return
                }
            }
            for child in children(e) { collect(child, depth: depth+1) }
        }
        collect(owner, depth: 0)
        func anchor(_ leaves: [Leaf], _ spans: [SourceTextSpan]) -> SourceSelection {
            SourceSelection(pid: pid, owner: owner, window: window, text: text, elements: leaves.map(\.element), spans: spans)
        }
        if !selectedLeaves.isEmpty, let spans = SourceTextMap.align(text, fragments: selectedLeaves.map(\.fragment)) {
            return (text, anchor(selectedLeaves, spans))
        }
        // Web-area bounds describe the whole page, even for a one-word range.
        // Align its indexed document text with its text leaves, then intersect with
        // the exact captured selection. This disambiguates repeated passages.
        if let selected, selected.length > 0,
           units <= 1_000_000, units >= NSMaxRange(selected),
           let documentText = string(owner, NSRange(location: 0, length: units)),
           NSMaxRange(selected) <= (documentText as NSString).length,
           (documentText as NSString).substring(with: selected) == text,
           let mapping = SourceTextMap.align(documentText, fragments: leaves.map(\.fragment)) {
            return (text, anchor(leaves, SourceTextMap.selected(mapping, range: selected)))
        }
        return (text, nil)
    }

    func bounds(range: NSRange, expected: String) -> [CGRect]? {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length,
              text.substring(with: range) == expected, !Task.isCancelled else { return nil }
        let app = AXUIElementCreateApplication(pid)
        if let window {
            guard let focused = Self.element(app, kAXFocusedWindowAttribute), CFEqual(window, focused) else { return nil }
            if let document, Self.value(window, kAXDocumentAttribute) as? String != document { return nil }
        }
        // A browser tab switch keeps the same window. Require the captured document
        // to remain an ancestor of keyboard focus; never paint over a different tab.
        if Self.value(owner, kAXRoleAttribute) as? String == "AXWebArea" {
            var item = Self.element(app, kAXFocusedUIElementAttribute), found = false
            for _ in 0..<40 {
                guard let current = item else { break }
                if CFEqual(current, owner) { found = true; break }
                item = Self.element(current, kAXParentAttribute)
            }
            guard found else { return nil }
        }
        let parts = SourceTextMap.selected(spans, range: range)
        guard !parts.isEmpty, parts.count <= 64 else { return nil }
        var boxes: [CGRect] = []
        for part in parts {
            let element = elements[part.element]
            let expectedPart = (expected as NSString).substring(with: part.textRange)
            guard Self.string(element, part.sourceRange) == expectedPart,
                  let raw = Self.rangeValue(part.sourceRange),
                  let rect = Self.rect(Self.parameter(element, kAXBoundsForRangeParameterizedAttribute, raw)),
                  !rect.isEmpty, rect.width < 1500, rect.height < 150 else { return nil }
            var clip = window.flatMap(Self.frame) ?? rect
            var ancestor: AXUIElement? = element
            for _ in 0..<40 {
                guard let current = ancestor else { break }
                if let role = Self.value(current, kAXRoleAttribute) as? String,
                   role == kAXScrollAreaRole || role == "AXWebArea", let bounds = Self.frame(current) { clip = clip.intersection(bounds) }
                if let window, CFEqual(current, window) { break }
                ancestor = Self.element(current, kAXParentAttribute)
            }
            // Entire word must be on screen; no rectangles over browser toolbars.
            guard clip.insetBy(dx: -1, dy: -1).contains(rect) else { return nil }
            if let last = boxes.last, abs(last.minY-rect.minY) < 2, abs(last.height-rect.height) < 3, rect.minX <= last.maxX+3, rect.minX >= last.minX {
                boxes[boxes.count-1] = last.union(rect)
            } else { boxes.append(rect) }
        }
        return boxes.count <= 8 ? boxes : nil
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        value(e, "AXChildrenInNavigationOrder") as? [AXUIElement] ?? value(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func secure(_ e: AXUIElement) -> Bool { value(e, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole || value(e, kAXRoleAttribute) as? String == "AXSecureTextField" }
    private static func value(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &result) == .success ? result : nil
    }
    private static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = value(e, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }; return (result as! AXUIElement)
    }
    private static func parameter(_ e: AXUIElement, _ name: String, _ arg: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(e, name as CFString, arg, &result) == .success ? result : nil
    }
    private static func range(_ raw: CFTypeRef?) -> NSRange? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var result = CFRange()
        guard AXValueGetValue(raw as! AXValue, .cfRange, &result), result.location >= 0, result.length >= 0,
              result.location < Int.max-result.length else { return nil }
        return NSRange(location: result.location, length: result.length)
    }
    private static func rangeValue(_ range: NSRange) -> AXValue? {
        var value = CFRange(location: range.location, length: range.length); return AXValueCreate(.cfRange, &value)
    }
    private static func string(_ e: AXUIElement, _ range: NSRange) -> String? {
        guard let raw = rangeValue(range) else { return nil }; return parameter(e, kAXStringForRangeParameterizedAttribute, raw) as? String
    }
    private static func rect(_ raw: CFTypeRef?) -> CGRect? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var result = CGRect.zero; return AXValueGetValue(raw as! AXValue, .cgRect, &result) ? result : nil
    }
    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let p = value(e, kAXPositionAttribute), let s = value(e, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
