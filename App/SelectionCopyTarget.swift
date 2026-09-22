import AppKit
import ApplicationServices

struct SelectionUnavailable: LocalizedError {
    let source: String
    let copyToken: UUID?
    var errorDescription: String? {
        "No accessible selection was found in \(source). Enable automatic Copy in Settings → Permissions, copy the text yourself and use Read clipboard, or choose a screen region explicitly."
    }
}

/// Actor-confined to TextExtractor. Captures the source before any player opens.
final class SelectionCopyTarget {
    let token = UUID()
    private let app: AXUIElement
    private let window: AXUIElement
    private let focused: AXUIElement
    private let document: String?
    private let selectedRange: CFTypeRef?
    private var command: AXUIElement?

    init(app: AXUIElement) throws {
        guard let window = Self.element(app, kAXFocusedWindowAttribute),
              let focused = Self.element(app, kAXFocusedUIElementAttribute) else {
            throw AppError.message("The source app does not expose enough focus information for automatic Copy. Use Read clipboard or select a screen region.")
        }
        self.app = app; self.window = window; self.focused = focused
        document = Self.value(window, kAXDocumentAttribute) as? String
        selectedRange = Self.value(focused, kAXSelectedTextRangeAttribute)
        try validate()
    }
    func prepare() throws {
        try validate()
        guard let menu = Self.element(app, kAXMenuBarAttribute) else { throw unavailable() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1.5))
        var visited = 0
        func find(_ item: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 8, visited < 800, ContinuousClock.now < deadline, !Task.isCancelled else { return nil }
            visited += 1
            if (Self.value(item, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "c",
               (Self.value(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0,
               Self.value(item, kAXEnabledAttribute) as? Bool == true { return item }
            for child in Self.value(item, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let result = find(child, depth: depth+1) { return result }
            }
            return nil
        }
        guard let found = find(menu, depth: 0) else { throw unavailable() }
        command = found
    }
    func perform() throws {
        try Task.checkCancellation(); try validate()
        guard let command, Self.value(command, kAXEnabledAttribute) as? Bool == true else { throw unavailable() }
        try Task.checkCancellation()
        guard AXUIElementPerformAction(command, kAXPressAction as CFString) == .success else {
            throw ClipboardCopyError.deliveryUncertain
        }
    }
    private func validate() throws {
        try Task.checkCancellation()
        var expectedPID: pid_t = 0, frontPID: pid_t = 0
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.25)
        guard let front = Self.element(system, kAXFocusedApplicationAttribute),
              AXUIElementGetPid(app, &expectedPID) == .success, AXUIElementGetPid(front, &frontPID) == .success,
              expectedPID == frontPID else { throw ClipboardCopyError.changed }
        guard let currentWindow = Self.element(app, kAXFocusedWindowAttribute), CFEqual(currentWindow, window),
              let currentFocus = Self.element(app, kAXFocusedUIElementAttribute), CFEqual(currentFocus, focused),
              document == Self.value(window, kAXDocumentAttribute) as? String else { throw ClipboardCopyError.changed }
        if let selectedRange {
            guard let current = Self.value(focused, kAXSelectedTextRangeAttribute), CFEqual(selectedRange, current) else { throw ClipboardCopyError.changed }
        }
        var current: AXUIElement? = focused
        for _ in 0..<50 {
            guard let item = current else { break }
            if Self.value(item, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole || Self.value(item, kAXRoleAttribute) as? String == "AXSecureTextField" {
                throw AppError.message("Secure text fields are never read or copied.")
            }
            if CFEqual(item, window) { return }
            current = Self.element(item, kAXParentAttribute)
        }
        throw AppError.message("The source focus could not be verified safely. Copy the selection yourself and use Read clipboard.")
    }
    private func unavailable() -> AppError { .message("The app has no enabled standard Copy command for this selection. Copy the text yourself and choose Read clipboard, or select a screen region explicitly.") }
    private static func value(_ item: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(item, name as CFString, &value) == .success ? value : nil
    }
    private static func element(_ item: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = value(item, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
