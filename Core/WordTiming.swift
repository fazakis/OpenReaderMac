import Foundation

public struct WordTimestamp: Decodable, Sendable {
    public let word: String
    public let start_time: Double
    public let end_time: Double
    public init(word: String, start: Double, end: Double) { self.word = word; start_time = start; end_time = end }
}
public struct TimedWord: Equatable, Sendable {
    public let range: NSRange
    public let start: Double
    public let end: Double
}
public enum WordAlignment {
    /// Fail closed if tokens were rewritten, omitted, reordered, or have invalid time ranges.
    /// Punctuation may extend into trailing silence trimmed by this verified server.
    public static func align(_ timestamps: [WordTimestamp], text: String, duration: Double) -> [TimedWord]? {
        guard !timestamps.isEmpty, duration > 0 else { return nil }
        let source = text as NSString
        var cursor = 0, previous = -Double.infinity, words: [TimedWord] = []
        let whitespace = CharacterSet.whitespacesAndNewlines
        for timestamp in timestamps {
            let token = timestamp.word.trimmingCharacters(in: whitespace)
            guard !token.isEmpty, timestamp.start_time.isFinite, timestamp.end_time.isFinite,
                  timestamp.start_time >= -0.1, timestamp.start_time >= previous-0.005,
                  timestamp.end_time >= timestamp.start_time, timestamp.end_time <= duration+0.35 else { return nil }
            while cursor < source.length, let scalar = UnicodeScalar(source.character(at: cursor)), whitespace.contains(scalar) { cursor += 1 }
            let range = source.range(of: token, options: [.anchored], range: NSRange(location: cursor, length: source.length-cursor))
            guard range.location != NSNotFound else { return nil }
            if token.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) {
                words.append(TimedWord(range: range, start: max(0,timestamp.start_time), end: min(duration,timestamp.end_time)))
            }
            previous = timestamp.start_time; cursor = NSMaxRange(range)
        }
        let tail = source.substring(from: cursor).trimmingCharacters(in: whitespace.union(.punctuationCharacters))
        guard tail.isEmpty else { return nil }
        return words.isEmpty ? nil : words
    }
}
