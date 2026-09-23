import Foundation

struct SpeechCapabilities: Codable, Equatable, Sendable {
    let version: Int
    let greek: Bool
    let mixedGreekEnglish: Bool
    let sampleRate: Int
    let greekModel: String
    let greekVoices: [String]
    let greekWordTimestamps: Bool
    enum CodingKeys: String, CodingKey {
        case version, greek
        case mixedGreekEnglish = "mixed_greek_english", sampleRate = "sample_rate"
        case greekModel = "greek_model", greekVoices = "greek_voices"
        case greekWordTimestamps = "greek_word_timestamps"
    }
    static let kokoro = SpeechCapabilities(version: 1, greek: false, mixedGreekEnglish: false,
        sampleRate: 24000, greekModel: "", greekVoices: [], greekWordTimestamps: false)
    var supportsGreek: Bool { version == 1 && greek && sampleRate == 24000 && greekModel == "supertonic-3" && !greekVoices.isEmpty }
}

struct SpeechRoute: Equatable, Sendable {
    let model: String
    let voice: String
    let language: String
    let wordTimestamps: Bool
    var label: String { model == "kokoro" ? "Kokoro" : "Supertonic 3 · Greek / English" }

    static func resolve(text: String, connection: Connection, capabilities: SpeechCapabilities, voices: [String]) throws -> SpeechRoute {
        let greek = Segmenter.containsGreek(text) || connection.language == "el"
        let multilingual = greek || connection.voice.hasPrefix("st_")
        if multilingual {
            guard capabilities.supportsGreek else {
                throw SpeechRoutingError("This speech server has no verified Greek support. Connect to a multilingual OpenReader server; the original text is unchanged.")
            }
            if Segmenter.containsGreek(text) && text.range(of: "[A-Za-z]", options: .regularExpression) != nil && !capabilities.mixedGreekEnglish {
                throw SpeechRoutingError("This server does not advertise mixed Greek/English speech support.")
            }
            let voice = greek ? (connection.greekVoice ?? "st_f1") : connection.voice
            guard capabilities.greekVoices.contains(voice), voices.contains(voice) else {
                throw SpeechRoutingError("The selected Greek voice is unavailable. Refresh voices and choose a Greek voice in Settings.")
            }
            return SpeechRoute(model: capabilities.greekModel, voice: voice, language: "auto", wordTimestamps: capabilities.greekWordTimestamps)
        }
        guard voices.contains(connection.voice) else {
            throw SpeechRoutingError("The configured voice is not in the live backend voice list.")
        }
        return SpeechRoute(model: "kokoro", voice: connection.voice, language: connection.language, wordTimestamps: true)
    }
}

struct SpeechRoutingError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
