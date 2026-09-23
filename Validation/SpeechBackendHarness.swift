import AppKit

@main enum SpeechBackendHarness {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: speech-backend-test LOOPBACK_OR_HTTPS_API_URL"); exit(2)
        }
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
        setbuf(stdout, nil)
        let suite = "OpenReaderSpeechValidation-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.connection.serverURL = CommandLine.arguments[1]
        preferences.connection.useSSH = false
        preferences.speed = 3; preferences.volume = 0
        let discovery = SpeechBackend(connection: preferences.connection, token: "")
        let capabilities = try await discovery.capabilities()
        guard capabilities.supportsGreek else { print("FAIL: Greek capabilities missing"); exit(3) }
        let voices = try await discovery.voices()
        guard voices.contains("af_alloy"), voices.contains("st_f1") else { exit(4) }
        print("PASS: live capabilities and both engine voice lists")

        let model = ReaderModel(registerShortcuts: false, preferences: preferences)
        for (name, text, highlight) in [
            ("English captioned", "Hello world. The original English voice still works.", true),
            ("Greek", "Καλημέρα κόσμε. Αυτή είναι η ελληνική φωνή.", true),
            ("Mixed", "Καλημέρα! This is OpenReader. Διαβάζουμε ελληνικά and English.", true),
            ("Greek raw", "Δοκιμή φωνής χωρίς επισήμανση λέξεων.", false)
        ] {
            preferences.highlightWords = highlight
            model.accept(ExtractedText(text: text, source: "Validation", note: "Public test sentence"))
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while model.status != "Finished", model.error == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            guard model.error == nil, model.status == "Finished", model.originalText == text else {
                print("FAIL: \(name): \(model.error ?? model.status)"); model.stop(); exit(5)
            }
            print("PASS: \(name) through production ReaderModel → SpeechBackend → AVAudioEngine (muted)")
        }
        model.accept(ExtractedText(text: String(repeating: "Αυτή είναι μια δοκιμή ακύρωσης. ", count: 20), source: "Validation", note: ""))
        try await Task.sleep(for: .milliseconds(200))
        model.stop()
        try await Task.sleep(for: .seconds(2))
        guard model.status == "Stopped", !model.audio.isActive else { print("FAIL: cancellation"); exit(6) }
        print("PASS: Stop rejects late audio and leaves playback inactive")
    }
}
