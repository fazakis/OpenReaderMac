import Foundation

/// No redirect may leak credentials to a different origin, or change an authenticated POST into a login page.
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct SpeechBackend: Sendable {
    let connection: Connection
    let token: String
    var model = "kokoro"
    private func request(_ path: String) throws -> URLRequest {
        guard let base = URL(string: connection.serverURL), let host = base.host,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw AppError.message("Use HTTPS, or a loopback HTTP address through SSH. The public /app URL is a website, not the speech API.")
        }
        var req = URLRequest(url: base.appendingPathComponent(path)); req.timeoutInterval = 90
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return req
    }
    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil; c.httpCookieStorage = nil; c.timeoutIntervalForRequest = 90; c.timeoutIntervalForResource = 180
        return URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }
    private func check(_ response: URLResponse, audio: Bool = false) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.message("The server returned an invalid response.") }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw AppError.message("Authentication was rejected. Check SSH access or the API credential in Settings. No automatic login retries were made.")
        case 300...399: throw AppError.message("The address redirected to another page. Use the verified speech API, not the web login gateway.")
        case 429: throw AppError.message("The server is rate limited. Wait before trying again.")
        default: throw AppError.message("The speech server returned HTTP \(http.statusCode). No audio was replayed automatically.")
        }
        if audio && !(http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased().hasPrefix("audio/pcm") {
            throw AppError.message("Expected the verified 24 kHz PCM stream, but the server returned a different format.")
        }
    }
    func voices() async throws -> [String] {
        let s = session(); defer { s.invalidateAndCancel() }
        let (data, response) = try await s.data(for: request("audio/voices")); try check(response)
        guard data.count < 1_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.message("Invalid voice list.") }
        let voices = (object["voices"] as? [String]) ?? (object["voices"] as? [[String: String]])?.compactMap { $0["id"] } ?? []
        guard !voices.isEmpty else { throw AppError.message("The speech API returned no voices.") }
        return voices
    }
    func capabilities() async throws -> SpeechCapabilities {
        let s = session(); defer { s.invalidateAndCancel() }
        let (data, response) = try await s.data(for: request("capabilities"))
        if let http = response as? HTTPURLResponse, [404, 405].contains(http.statusCode) { return .kokoro }
        try check(response)
        guard data.count < 100_000 else { throw AppError.message("Invalid speech capabilities response.") }
        return try JSONDecoder().decode(SpeechCapabilities.self, from: data)
    }
    struct CaptionPacket: Decodable, Sendable {
        let audio: String
        let audio_format: String
        let timestamps: [WordTimestamp]?
    }
    func captioned(text: String, receive: @escaping @Sendable (Data, [TimedWord]?) async throws -> Void) async throws {
        // The deployed caption route is at the origin root, not under /v1.
        var req = try request("audio/speech")
        guard let base = URL(string: connection.serverURL), let endpoint = URL(string: "/dev/captioned_speech", relativeTo: base)?.absoluteURL else { throw AppError.message("Invalid caption endpoint.") }
        req.url = endpoint; req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model":model, "input":text, "voice":connection.voice, "speed":1.0, "response_format":"pcm", "stream":true, "return_timestamps":true, "return_download_link":false, "volume_multiplier":1.0, "normalization_options":["normalize":false]]
        if connection.language != "auto" { body["lang_code"] = connection.language }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let s = session(); defer { s.invalidateAndCancel() }
        let (bytes,response) = try await s.bytes(for: req); try check(response)
        guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true else { throw AppError.message("The caption endpoint returned an unexpected format. Disable word highlighting to use the PCM endpoint.") }
        var line = Data(), accumulatedAudio = Data(), allTimes: [WordTimestamp] = []
        // One app chunk is at most 350 characters. Buffer this bounded sentence so timing
        // validation covers all its tokens before any word is highlighted.
        func parse(_ data: Data) throws {
            guard !data.isEmpty else { return }
            let packet = try JSONDecoder().decode(CaptionPacket.self, from: data)
            guard packet.audio_format == "audio/pcm", let pcm = Data(base64Encoded: packet.audio), pcm.count % 2 == 0 else { throw AppError.message("Invalid captioned PCM audio.") }
            accumulatedAudio.append(pcm); allTimes += packet.timestamps ?? []
            guard accumulatedAudio.count <= 24_000*2*180 else { throw AppError.message("Captioned audio exceeded its bounded buffer.") }
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 { try parse(line); line.removeAll(keepingCapacity: true) }
            else { line.append(byte); guard line.count <= 24_000_000 else { throw AppError.message("Caption stream exceeded its bounded buffer.") } }
        }
        try parse(line); try Task.checkCancellation()
        guard !accumulatedAudio.isEmpty else { throw AppError.message("The caption endpoint returned no audio.") }
        let duration = Double(accumulatedAudio.count)/48_000
        let alignment = WordAlignment.align(allTimes, text: text, duration: duration)
        try await receive(accumulatedAudio, alignment)
    }
    func stream(text: String, receive: @escaping @Sendable (Data) async throws -> Void) async throws {
        var req = try request("audio/speech"); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": model, "input": text, "voice": connection.voice, "speed": 1.0, "response_format": "pcm", "stream": true, "return_download_link": false, "volume_multiplier": 1.0, "normalization_options": ["normalize": false]]
        if connection.language != "auto" { body["lang_code"] = connection.language }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let s = session(); defer { s.invalidateAndCancel() }
        let (bytes, response) = try await s.bytes(for: req); try check(response, audio: true)
        var chunk = Data(), total = 0
        for try await byte in bytes {
            try Task.checkCancellation(); chunk.append(byte); total += 1
            guard total <= 24_000 * 2 * 180 else { throw AppError.message("A speech segment exceeded the three-minute safety bound.") }
            if chunk.count >= 8192 { try await receive(chunk); chunk.removeAll(keepingCapacity: true) }
        }
        try Task.checkCancellation()
        if !chunk.isEmpty { try await receive(chunk) }
        guard total > 0, total % 2 == 0 else { throw AppError.message("The server returned an empty or truncated audio stream.") }
    }
}

@MainActor final class SSHTunnel {
    private var process: Process?
    private var signature = ""
    func ensure(_ c: Connection) async throws {
        guard c.useSSH else { return }
        let configuration = SSHConfiguration(connection: c)
        if let message = configuration.validationMessage { throw AppError.message(message) }
        let newSignature = configuration.arguments.joined(separator: "\n")
        if process?.isRunning == true && signature == newSignature { return }
        close()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = configuration.arguments
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); process = p; signature = newSignature
        for _ in 0..<40 {
            try Task.checkCancellation()
            guard p.isRunning else { throw AppError.message("SSH could not start. Verify the configured SSH alias or host in Terminal, including this Mac's key/agent and trusted host entry, and check that local port \(c.localPort) is free.") }
            var probe = URLRequest(url: URL(string: "http://127.0.0.1:\(c.localPort)/health")!); probe.timeoutInterval = 0.3
            if let (_, response) = try? await URLSession.shared.data(for: probe), (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(for: .milliseconds(150))
        }
        close(); throw AppError.message("SSH opened, but the speech service did not respond on the forwarded port.")
    }
    func close() { if process?.isRunning == true { process?.terminate() }; process = nil; signature = "" }
}
