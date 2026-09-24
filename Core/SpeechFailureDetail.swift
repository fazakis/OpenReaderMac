import Foundation

enum SpeechFailureDetail {
    static let maximumBytes = 16_384

    /// Extract diagnostic fields only. Pydantic's `input`/`ctx` and arbitrary
    /// response bodies can echo document text or credentials; never include them.
    static func parse(_ data: Data) -> String? {
        guard data.count <= maximumBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let message: String?
        if let detail = root["detail"] as? String { message = detail }
        else if let detail = root["detail"] as? [String: Any] { message = detail["message"] as? String }
        else if let details = root["detail"] as? [[String: Any]] {
            message = details.prefix(3).compactMap { detail in
                guard let message = detail["msg"] as? String else { return nil }
                let location = (detail["loc"] as? [String] ?? []).filter { $0 != "body" }.joined(separator: ".")
                return location.isEmpty ? message : "\(location): \(message)"
            }.joined(separator: "; ")
        } else { message = nil }
        guard let message else { return nil }
        let clean = message.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        return String(clean.prefix(600))
    }
}
