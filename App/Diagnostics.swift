import AppKit
import Vision
import AVFoundation

/// Opt-in integration diagnostics using the exact production client and audio engine.
/// Invoke the app executable with --diagnostics /absolute/path/report.json.
@MainActor enum Diagnostics {
    static func run(reportPath: String) async {
        var result: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "os": ProcessInfo.processInfo.operatingSystemVersionString]
        let tunnel = SSHTunnel(), audio = AudioPlayback(), extractor = TextExtractor()
        var c = Connection.load()
        if c.useSSH { c.localPort = 18881; c.serverURL = "http://127.0.0.1:18881/v1" }
        result["accessibilityGranted"] = AXIsProcessTrusted()
        result["screenRecordingGranted"] = CGPreflightScreenCaptureAccess()
        result["displays"] = NSScreen.screens.map { ["width": $0.frame.width, "height": $0.frame.height, "scale": $0.backingScaleFactor] }
        do {
            let langs = try await extractor.languages(); result["visionLanguages"] = langs
            let size = NSSize(width: 1000, height: 220)
            let image = NSImage(size: size); image.lockFocus()
            NSColor.white.setFill(); CGRect(origin: .zero, size: size).fill()
            ("OpenReader local OCR test.\nThe original words stay unchanged." as NSString).draw(at: NSPoint(x: 30,y: 65), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
            image.unlockFocus()
            var rect = CGRect(origin: .zero, size: size)
            if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                let text = try await extractor.recognize(cg, language: "en", source: "Generated test fixture")
                result["localOCRFixture"] = text.text.contains("OpenReader") && text.text.contains("original words")
            }
        } catch { result["ocrError"] = "Diagnostic operation failed; inspect the configured connection locally." }
        do {
            try await tunnel.ensure(c)
            let backend = SpeechBackend(connection: c, token: SecretStore.read(SecretStore.key(for: Connection.load().serverURL)))
            let voices = try await backend.voices(); result["liveVoiceCount"] = voices.count; result["verifiedVoicePresent"] = voices.contains("af_alloy")
            let start = Date(), epoch = try audio.begin(at: 0)
            audio.setSpeed(1.4); audio.setVolume(0.3)
            let counter = DiagnosticCounter()
            try await backend.stream(text: "OpenReader Mac is testing real speech from your Kokoro service. Pause preserves this sentence, and playback resumes from the same position.") { data in
                await counter.add(data.count)
                try await audio.append(data, chunk: 0, epoch: epoch)
            }
            result["livePCMBytes"] = await counter.bytes
            result["firstPCMSeconds"] = await counter.firstDate.map { $0.timeIntervalSince(start) }
            audio.togglePause(); let paused = audio.renderedSampleTime
            try await Task.sleep(for: .milliseconds(450))
            result["pauseRetainsSamplePosition"] = paused == audio.renderedSampleTime && audio.isPaused
            audio.togglePause(); audio.setSpeed(3)
            try await Task.sleep(for: .milliseconds(450))
            result["resumeAdvancesSamplePosition"] = (audio.renderedSampleTime ?? 0) > (paused ?? 0)
            audio.setSpeed(0.5); result["speedRangeApplied"] = "0.5–3.0 with AVAudioUnitTimePitch"
            audio.finish(epoch: epoch)
            let deadline = Date().addingTimeInterval(35)
            audio.setSpeed(3)
            while audio.isActive && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
            result["livePlaybackCompleted"] = !audio.isActive
            let wordEpoch = try audio.begin(at: 0)
            audio.setSpeed(1)
            let wordCounter = DiagnosticCounter()
            try await backend.captioned(text: "The quick brown fox jumps over the lazy dog.") { data, words in
                await wordCounter.addWords(words?.count ?? 0)
                for offset in stride(from: 0, to: data.count, by: 8192) {
                    try await audio.append(data.subdata(in: offset..<min(offset+8192,data.count)), chunk: 0, epoch: wordEpoch, words: offset == 0 ? words : nil)
                }
            }
            audio.finish(epoch: wordEpoch)
            var observedWords = Set<Int>()
            let wordDeadline = Date().addingTimeInterval(12)
            while audio.isActive && Date() < wordDeadline {
                if let range = audio.currentWord { observedWords.insert(range.location) }
                try await Task.sleep(for: .milliseconds(35))
            }
            result["liveValidatedWordCount"] = await wordCounter.wordCount
            result["observedSynchronizedWordHighlights"] = observedWords.count
            let old = try audio.begin(at: 0)
            let task = Task {
                try await backend.stream(text: String(repeating: "Cancellation must stop pending speech immediately. ", count: 5)) { data in
                    try await audio.append(data, chunk: 0, epoch: old)
                }
            }
            try await Task.sleep(for: .milliseconds(200)); task.cancel(); audio.stop()
            do { try await task.value; result["networkCancellation"] = "completed before cancellation" } catch { result["networkCancellation"] = "cancelled" }
            do { try await audio.append(Data([0,0,0,0]), chunk: 0, epoch: old); result["rejectsStaleAudio"] = false } catch { result["rejectsStaleAudio"] = true }
            result["stopClearsPendingFrames"] = audio.pendingFrames == 0 && !audio.isActive
            var unavailable = c; unavailable.useSSH = false; unavailable.serverURL = "http://127.0.0.1:1/v1"
            do { _ = try await SpeechBackend(connection: unavailable, token: "").voices(); result["unavailableServerHandled"] = false } catch { result["unavailableServerHandled"] = true }
            var unsafe = c; unsafe.serverURL = "http://example.invalid/app"
            do { _ = try await SpeechBackend(connection: unsafe, token: "").voices(); result["publicHTTPRejected"] = false } catch { result["publicHTTPRejected"] = true }
        } catch { result["liveError"] = "Diagnostic operation failed; inspect the configured connection locally." }
        if ProcessInfo.processInfo.environment["OPENREADER_ERROR_FIXTURE"] == "1" {
            for (path, expected) in [("unauthorized", "Authentication was rejected"), ("unavailable", "HTTP 503")] {
                var fixture = c; fixture.useSSH = false; fixture.serverURL = "http://127.0.0.1:18882/" + path
                do { _ = try await SpeechBackend(connection: fixture, token: "test-only-not-a-secret").voices(); result["fixture_"+path] = false }
                catch { result["fixture_"+path] = error.localizedDescription.contains(expected) }
            }
        }
        audio.stop(); tunnel.close()
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: reportPath)) }
        NSApp.terminate(nil)
    }
}
private actor DiagnosticCounter {
    var wordCount = 0
    func addWords(_ count: Int) { wordCount += count }
    var bytes = 0
    var firstDate: Date?
    func add(_ count: Int) { if firstDate == nil { firstDate = Date() }; bytes += count }
}
