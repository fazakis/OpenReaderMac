import Foundation

public struct Sentence: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let sentenceID: Int
    public let isFragment: Bool
}

public enum Segmenter {
    /// Preserves every character, including whitespace. The limit is an app latency bound,
    /// not a claim about the server's phoneme-token limit.
    public static func split(_ text: String, limit: Int = 350) -> [Sentence] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let chars = Array(text)
        let cap = max(8, limit)
        var sentences: [String] = [], start = 0, i = 0
        let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "vs", "etc", "e.g", "i.e", "κ", "π.χ"]
        while i < chars.count {
            let c = chars[i]
            var boundary = c == "!" || c == "?" || c == ";" || c == "\u{037e}" || c == "\n"
            if c == "." {
                let decimal = i > 0 && i + 1 < chars.count && chars[i-1].isNumber && chars[i+1].isNumber
                let token = String(chars[start..<i]).split(whereSeparator: { $0.isWhitespace }).last.map(String.init)?.lowercased() ?? ""
                let initial = token.count == 1 && token.first?.isLetter == true
                boundary = !decimal && !initial && !abbreviations.contains(token) && (i+1 == chars.count || chars[i+1].isWhitespace || "\"”’».".contains(chars[i+1]))
            }
            if boundary {
                var end = i + 1
                while end < chars.count && (chars[end].isWhitespace || "\"”’»!?…".contains(chars[end]) || chars[end] == ".") { end += 1 }
                sentences.append(String(chars[start..<end])); start = end; i = end
            } else { i += 1 }
        }
        if start < chars.count { sentences.append(String(chars[start...])) }
        var result: [Sentence] = []
        for (sid, sentence) in sentences.enumerated() {
            var rest = Array(sentence), pieces: [String] = []
            while rest.count > cap {
                let cut = (1..<cap).reversed().first(where: { rest[$0].isWhitespace }) .map { $0 + 1 } ?? cap
                pieces.append(String(rest.prefix(cut))); rest.removeFirst(cut)
            }
            if !rest.isEmpty { pieces.append(String(rest)) }
            for part in pieces { result.append(Sentence(id: result.count, text: part, sentenceID: sid, isFragment: pieces.count > 1)) }
        }
        return result
    }
    public static func containsGreek(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x370...0x3ff).contains($0.value) || (0x1f00...0x1fff).contains($0.value) }
    }
}

/// Shared by playback and tests. An old response can never enqueue into a newer reading.
public struct PlaybackLedger: Sendable {
    public private(set) var epoch = UUID()
    public private(set) var pendingFrames = 0
    public private(set) var lastChunk = -1
    public init() {}
    @discardableResult public mutating func reset() -> UUID {
        epoch = UUID(); pendingFrames = 0; lastChunk = -1; return epoch
    }
    public mutating func enqueue(epoch: UUID, chunk: Int, frames: Int) -> Bool {
        guard epoch == self.epoch, chunk >= lastChunk, frames > 0 else { return false }
        lastChunk = chunk; pendingFrames += frames; return true
    }
    public mutating func completed(epoch: UUID, frames: Int) -> Bool {
        guard epoch == self.epoch else { return false }
        pendingFrames = max(0, pendingFrames - frames); return true
    }
}

public struct PCMFramer: Sendable {
    private var pending = Data()
    public init() {}
    public mutating func append(_ bytes: Data) -> Data {
        pending.append(bytes)
        let count = pending.count - pending.count % 2
        let result = Data(pending.prefix(count)); pending.removeFirst(count); return result
    }
    public var hasIncompleteSample: Bool { !pending.isEmpty }
}
