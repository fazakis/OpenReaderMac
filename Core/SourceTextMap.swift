import Foundation

/// Maps the unchanged spoken text to the text elements exposed by the source app.
/// PDFKit inserts different whitespace into its document selection and leaf text.
/// Only whitespace may differ; every other UTF-16 unit must match, in order.
public struct SourceTextFragment: Sendable {
    public let text: String
    public let sourceOffset: Int
    public init(text: String, sourceOffset: Int = 0) { self.text = text; self.sourceOffset = sourceOffset }
}

public struct SourceTextSpan: Equatable, Sendable {
    public var textRange: NSRange
    public let element: Int
    public var sourceRange: NSRange
}

public enum SourceTextMap {
    public static func align(_ text: String, fragments: [SourceTextFragment]) -> [SourceTextSpan]? {
        let target = Array(text.utf16)
        func whitespace(_ unit: UInt16) -> Bool {
            Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        var cursor = 0, result: [SourceTextSpan] = []
        for (index, fragment) in fragments.enumerated() {
            guard fragment.sourceOffset >= 0 else { return nil }
            for (offset, unit) in fragment.text.utf16.enumerated() where !whitespace(unit) {
                while cursor < target.count && whitespace(target[cursor]) { cursor += 1 }
                guard cursor < target.count, target[cursor] == unit else { return nil }
                let source = fragment.sourceOffset + offset
                if let last = result.last, last.element == index,
                   NSMaxRange(last.textRange) == cursor, NSMaxRange(last.sourceRange) == source {
                    result[result.count-1].textRange.length += 1
                    result[result.count-1].sourceRange.length += 1
                } else {
                    result.append(SourceTextSpan(textRange: NSRange(location: cursor, length: 1), element: index,
                                                 sourceRange: NSRange(location: source, length: 1)))
                }
                cursor += 1
            }
        }
        while cursor < target.count && whitespace(target[cursor]) { cursor += 1 }
        return cursor == target.count ? result : nil
    }

    /// Restrict a document mapping to the captured selection, keeping exact offsets.
    public static func selected(_ spans: [SourceTextSpan], range: NSRange) -> [SourceTextSpan] {
        spans.compactMap { span in
            let intersection = NSIntersectionRange(span.textRange, range)
            guard intersection.length > 0 else { return nil }
            return SourceTextSpan(textRange: NSRange(location: intersection.location-range.location, length: intersection.length),
                                  element: span.element,
                                  sourceRange: NSRange(location: span.sourceRange.location+intersection.location-span.textRange.location, length: intersection.length))
        }
    }
}
