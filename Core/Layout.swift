import Foundation
import CoreGraphics

public struct OCRBlock: Sendable, Equatable {
    public let text: String
    public let bounds: CGRect // top-left normalized coordinates
    public init(text: String, bounds: CGRect) { self.text = text; self.bounds = bounds }
}
public enum ReadingOrder {
    /// Recursive whitespace cuts preserve simple multi-column layouts. Complex tables
    /// remain reviewable in the reader; no semantic reconstruction is invented.
    public static func ordered(_ blocks: [OCRBlock]) -> [OCRBlock] {
        guard blocks.count > 1 else { return blocks }
        let byX = blocks.sorted { $0.bounds.minX < $1.bounds.minX }
        var edge = byX[0].bounds.maxX, split: Int?, bestGap: CGFloat = 0.025
        for i in 1..<byX.count {
            let gap = byX[i].bounds.minX - edge
            if gap > bestGap { bestGap = gap; split = i }
            edge = max(edge, byX[i].bounds.maxX)
        }
        if let split { return ordered(Array(byX[..<split])) + ordered(Array(byX[split...])) }
        let byY = blocks.sorted { $0.bounds.minY < $1.bounds.minY }
        edge = byY[0].bounds.maxY; split = nil; bestGap = 0.018
        for i in 1..<byY.count {
            let gap = byY[i].bounds.minY - edge
            if gap > bestGap { bestGap = gap; split = i }
            edge = max(edge, byY[i].bounds.maxY)
        }
        if let split { return ordered(Array(byY[..<split])) + ordered(Array(byY[split...])) }
        var rows: [[OCRBlock]] = []
        for block in byY {
            if let last = rows.last, let first = last.first,
               abs(first.bounds.midY-block.bounds.midY) < min(first.bounds.height,block.bounds.height)*0.55 {
                rows[rows.count-1].append(block)
            } else { rows.append([block]) }
        }
        return rows.flatMap { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }
}
public enum CaptureGeometry {
    public static func quartzRect(local: CGRect, screenFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX+local.minX, y: primaryTop-screenFrame.minY-local.maxY, width: local.width, height: local.height)
    }
    public static func displayLocal(_ rect: CGRect, displayFrame: CGRect) -> CGRect {
        let clipped = rect.intersection(displayFrame)
        return CGRect(x: clipped.minX-displayFrame.minX, y: clipped.minY-displayFrame.minY, width: clipped.width, height: clipped.height)
    }
}
