import Foundation

private actor ReceivedAudio {
    var count = 0
    func add(_ data: Data) { count += data.count }
}

@main enum SpeechFailureHarness {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { exit(2) }
        for captioned in [false, true] {
            for (voice, expected) in [
                ("st_f1", "U+001B"), ("oversized", "rejected the speech input or settings"),
                ("html", "rejected the speech input or settings"),
                ("unauthorized", "Authentication was rejected"), ("unavailable", "HTTP 503"),
                ("success", "")
            ] {
                var connection = Connection()
                connection.serverURL = CommandLine.arguments[1]; connection.voice = voice
                let backend = SpeechBackend(connection: connection, token: "", model: "supertonic-3")
                let received = ReceivedAudio()
                var failure: String?
                do {
                    if captioned {
                        try await backend.captioned(text: "Public fixture text.") { data, _ in await received.add(data) }
                    } else {
                        try await backend.stream(text: "Public fixture text.") { data in await received.add(data) }
                    }
                } catch { failure = error.localizedDescription }
                let count = await received.count
                if voice == "success" {
                    guard failure == nil, count == 9600 else { fatalError("Successful PCM was consumed or rejected: \(failure ?? "")") }
                } else {
                    guard let failure, failure.contains(expected), !failure.contains("PRIVATE-FIXTURE-INPUT"), count == 0 else {
                        fatalError("Incorrect error handling for \(voice): \(failure ?? "no error") / \(count) bytes")
                    }
                }
                print("PASS: \(captioned ? "captioned" : "raw") \(voice)")
            }
        }
    }
}
