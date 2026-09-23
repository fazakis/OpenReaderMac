import Foundation

/// Machine-specific values live in macOS preferences, never in the source tree.
struct Connection: Codable, Equatable, Sendable {
    var useSSH = false
    var sshHost = ""
    var sshUser = ""
    var localPort = 18880
    var serverURL = "http://127.0.0.1:18880/v1"
    var voice = "af_alloy"
    var greekVoice: String? = nil
    var language = "auto"
    static func load(from defaults: UserDefaults = .standard) -> Connection {
        defaults.data(forKey: "connection").flatMap { try? JSONDecoder().decode(Connection.self, from: $0) } ?? Connection()
    }
}
