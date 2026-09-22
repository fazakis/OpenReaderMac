import AppKit
import Carbon

/// Registers production shortcuts with macOS, without posting keys or changing preferences.
@main enum ShortcutHarness {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let manager = ShortcutManager()
        defer { manager.register([]) }
        var passed = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fputs("FAIL: \(name)\n", stderr); exit(1) }
            passed += 1
            print("PASS: \(name)")
        }
        for (name, modifiers) in [("Control", controlKey), ("Option", optionKey),
                                  ("Control–Option", controlKey | optionKey),
                                  ("Option–Shift", optionKey | shiftKey)] {
            let shortcut = Shortcut(id: "test", title: "Test", key: 90, modifiers: UInt32(modifiers))
            manager.register([shortcut])
            check(manager.conflicts.isEmpty, "macOS registration without Command: \(name)")
        }
        for modifiers in [0, shiftKey] {
            manager.register([Shortcut(id: "typing", title: "Typing", key: 15, modifiers: UInt32(modifiers))])
            check(manager.conflicts["typing"] != nil, "Reject plain or Shift-only typing keys: \(modifiers)")
        }
        let first = Shortcut(id: "first", title: "First", key: 90, modifiers: UInt32(controlKey | optionKey))
        var duplicate = first
        duplicate.id = "second"
        manager.register([first, duplicate])
        check(manager.conflicts["first"] == nil && manager.conflicts["second"]?.contains("Also assigned") == true,
              "Detect duplicate assignments")
        duplicate.enabled = false
        manager.register([first, duplicate])
        check(manager.conflicts.isEmpty, "Ignore disabled assignments")
        check(try JSONDecoder().decode([Shortcut].self, from: JSONEncoder().encode([first, duplicate])) == [first, duplicate],
              "Persist shortcuts without adding Command")
        manager.register([])
        var reserved: EventHotKeyRef?
        let status = RegisterEventHotKey(first.key, first.modifiers,
            EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), 0, &reserved)
        check(status == noErr && reserved != nil, "Reserve native hotkey for conflict test")
        defer { if let reserved { UnregisterEventHotKey(reserved) } }
        manager.register([first])
        check(manager.conflicts["first"]?.contains("Unavailable or reserved") == true,
              "Report a macOS registration conflict")
        print("\(passed) native shortcut checks passed.")
    }
}
