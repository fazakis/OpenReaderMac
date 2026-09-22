import SwiftUI
import Security

@MainActor final class Preferences: ObservableObject {
    @Published var connection: Connection { didSet { save() } }
    @Published var speed: Double { didSet { UserDefaults.standard.set(speed, forKey: "speed") } }
    @Published var volume: Double { didSet { UserDefaults.standard.set(volume, forKey: "volume") } }
    @Published var highlightWords: Bool { didSet { UserDefaults.standard.set(highlightWords, forKey: "highlightWords") } }
    @Published var ocrLanguage: String { didSet { UserDefaults.standard.set(ocrLanguage, forKey: "ocrLanguage") } }
    @Published var automaticCopyFallback: Bool { didSet { UserDefaults.standard.set(automaticCopyFallback, forKey: "automaticCopyFallback") } }
    @Published var shortcuts: [Shortcut] { didSet { save() } }
    init() {
        let d = UserDefaults.standard
        connection = Connection.load(from: d)
        automaticCopyFallback = d.object(forKey: "automaticCopyFallback") as? Bool ?? true
        speed = d.object(forKey: "speed") as? Double ?? 1.4
        volume = d.object(forKey: "volume") as? Double ?? 0.8
        highlightWords = d.object(forKey: "highlightWords") as? Bool ?? true
        ocrLanguage = d.string(forKey: "ocrLanguage") ?? "en"
        shortcuts = d.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) } ?? Shortcut.defaults
    }
    private func save() {
        if let data = try? JSONEncoder().encode(connection) { UserDefaults.standard.set(data, forKey: "connection") }
        if let data = try? JSONEncoder().encode(shortcuts) { UserDefaults.standard.set(data, forKey: "shortcuts") }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum SecretStore {
    static func key(for url: String) -> String { "api-token:" + url }
    static func read(_ account: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "gr.fazakis.OpenReaderMac", kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "gr.fazakis.OpenReaderMac", kSecAttrAccount as String: account]
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add.merge(update) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.message("Keychain could not save the credential (\(status)).") }
    }
}
