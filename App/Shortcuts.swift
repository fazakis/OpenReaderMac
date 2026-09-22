import AppKit
import Carbon

struct Shortcut: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var key: UInt32
    var modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
    var enabled = true
    static let keyNames: [(String, UInt32)] = [("R",15),("S",1),("A",0),("C",8),("P",35),("Period",47),("Left",123),("Right",124),("Down",125),("Up",126),("F",3),("D",2),("E",14),("G",5),("H",4),("J",38),("K",40),("L",37),("M",46),("N",45),("T",17),("U",32),("V",9),("W",13),("X",7),("Y",16),("Z",6),("Space",49)]
    var label: String {
        guard enabled else { return "Disabled" }
        return (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + (Self.keyNames.first { $0.1 == key }?.0 ?? "Key \(key)")
    }
    static let defaults = [Shortcut(id:"selection",title:"Read selection",key:15), Shortcut(id:"window",title:"Read active window",key:1), Shortcut(id:"region",title:"Select screen region",key:0), Shortcut(id:"clipboard",title:"Read clipboard",key:8), Shortcut(id:"play",title:"Play / pause",key:35), Shortcut(id:"stop",title:"Stop",key:47), Shortcut(id:"previous",title:"Previous sentence",key:123), Shortcut(id:"next",title:"Next sentence",key:124), Shortcut(id:"slower",title:"Decrease speed",key:125), Shortcut(id:"faster",title:"Increase speed",key:126), Shortcut(id:"player",title:"Show / hide player",key:3)]
}

@MainActor final class ShortcutManager: ObservableObject {
    @Published var conflicts: [String: String] = [:]
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var actions: [Shortcut] = []
    var perform: ((String) -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            let manager = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                let index = Int(hotkey.id) - 1
                if manager.actions.indices.contains(index) { manager.perform?(manager.actions[index].id) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcuts: [Shortcut]) {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); conflicts = [:]; actions = shortcuts
        var used: [String: String] = [:]
        for (index, shortcut) in shortcuts.enumerated() where shortcut.enabled {
            // Command is optional. Keep plain and Shift-only typing keys available to apps.
            guard shortcut.modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { conflicts[shortcut.id] = "Choose Control, Option, or Command. Command is optional."; continue }
            let key = "\(shortcut.key):\(shortcut.modifiers)"
            if let previous = used[key] { conflicts[shortcut.id] = "Also assigned to \(previous)."; continue }
            used[key] = shortcut.title
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.key, shortcut.modifiers, EventHotKeyID(signature: 0x4F524D43, id: UInt32(index+1)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { conflicts[shortcut.id] = "Unavailable or reserved by macOS / another app (\(status))." }
        }
    }
}
