import XCTest
@testable import OpenReaderCore

final class SpeechRoutingTests: XCTestCase {
    let capabilities = SpeechCapabilities(version: 1, greek: true, mixedGreekEnglish: true,
        sampleRate: 24000, greekModel: "supertonic-3", greekVoices: ["st_f1", "st_m1"], greekWordTimestamps: false)
    let voices = ["af_alloy", "st_f1", "st_m1"]

    func testEnglishKeepsLegacyVoiceAndTimestamps() throws {
        let route = try SpeechRoute.resolve(text: "Hello world.", connection: Connection(), capabilities: .kokoro, voices: voices)
        XCTAssertEqual(route.model, "kokoro")
        XCTAssertEqual(route.voice, "af_alloy")
        XCTAssertTrue(route.wordTimestamps)
    }
    func testGreekAndMixedUseOneExplicitMultilingualVoice() throws {
        var connection = Connection(); connection.greekVoice = "st_m1"
        for text in ["Καλημέρα κόσμε.", "Hello world. Καλημέρα κόσμε.", "Ἑλληνικά"] {
            let route = try SpeechRoute.resolve(text: text, connection: connection, capabilities: capabilities, voices: voices)
            XCTAssertEqual(route.model, "supertonic-3")
            XCTAssertEqual(route.voice, "st_m1")
            XCTAssertEqual(route.language, "auto")
            XCTAssertFalse(route.wordTimestamps)
        }
    }
    func testLegacyBackendRejectsGreekBeforeSynthesis() {
        XCTAssertThrowsError(try SpeechRoute.resolve(text: "Greek: Ελληνικά", connection: Connection(), capabilities: .kokoro, voices: voices))
    }
    func testMissingGreekVoiceDoesNotSilentlySubstitute() {
        var connection = Connection(); connection.greekVoice = "st_f5"
        XCTAssertThrowsError(try SpeechRoute.resolve(text: "Ελληνικά", connection: connection, capabilities: capabilities, voices: voices))
    }
    func testIncompatibleSampleRateAndMixedSupportAreRejected() {
        let wrongRate = SpeechCapabilities(version: 1, greek: true, mixedGreekEnglish: true,
            sampleRate: 44100, greekModel: "supertonic-3", greekVoices: ["st_f1"], greekWordTimestamps: false)
        XCTAssertThrowsError(try SpeechRoute.resolve(text: "Ελληνικά", connection: Connection(), capabilities: wrongRate, voices: voices))
        let monolingual = SpeechCapabilities(version: 1, greek: true, mixedGreekEnglish: false,
            sampleRate: 24000, greekModel: "supertonic-3", greekVoices: ["st_f1"], greekWordTimestamps: false)
        XCTAssertThrowsError(try SpeechRoute.resolve(text: "Hello Ελληνικά", connection: Connection(), capabilities: monolingual, voices: voices))
    }
    func testCapabilitiesWireFormatAndLegacyPreferenceMigration() throws {
        let json = #"{"version":1,"greek":true,"mixed_greek_english":true,"sample_rate":24000,"greek_model":"supertonic-3","greek_voices":["st_f1","st_m1"],"greek_word_timestamps":false}"#
        XCTAssertEqual(try JSONDecoder().decode(SpeechCapabilities.self, from: Data(json.utf8)), capabilities)
        let old = #"{"useSSH":true,"sshHost":"speech-example","sshUser":"","localPort":18880,"serverURL":"http://127.0.0.1:18880/v1","voice":"af_alloy","language":"auto"}"#
        let connection = try JSONDecoder().decode(Connection.self, from: Data(old.utf8))
        XCTAssertEqual(connection.sshHost, "speech-example")
        XCTAssertNil(connection.greekVoice)
        let route = try SpeechRoute.resolve(text: "Καλημέρα", connection: connection, capabilities: capabilities, voices: voices)
        XCTAssertEqual(route.voice, "st_f1")
        XCTAssertEqual(try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(connection)), connection)
    }
}
