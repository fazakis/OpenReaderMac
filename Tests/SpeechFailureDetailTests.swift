import XCTest
@testable import OpenReaderCore

final class SpeechFailureDetailTests: XCTestCase {
    func testStructuredCharacterError() {
        let data = Data(#"{"detail":{"code":"unsupported_characters","message":"Cannot read U+001B. Use Select screen region.","codepoints":["U+001B"]}}"#.utf8)
        XCTAssertEqual(SpeechFailureDetail.parse(data), "Cannot read U+001B. Use Select screen region.")
    }
    func testLegacyStringError() {
        XCTAssertEqual(SpeechFailureDetail.parse(Data(#"{"detail":"Invalid language"}"#.utf8)), "Invalid language")
    }
    func testPydanticInputAndContextAreNotEchoed() {
        let data = Data(#"{"detail":[{"loc":["body","speed"],"msg":"Must be positive","input":"PRIVATE INPUT","ctx":{"error":"PRIVATE CONTEXT"}}]}"#.utf8)
        XCTAssertEqual(SpeechFailureDetail.parse(data), "speed: Must be positive")
    }
    func testMalformedHTMLAndUnknownShapesUseGenericError() {
        for body in ["<html>Bad gateway</html>", "{", "[]", #"{"input":"PRIVATE"}"#, #"{"detail":{"input":"PRIVATE"}}"#, #"{"detail":[]}"#] {
            XCTAssertNil(SpeechFailureDetail.parse(Data(body.utf8)))
        }
    }
    func testResponseAndMessageSizesAreBounded() {
        let huge = Data(repeating: 65, count: SpeechFailureDetail.maximumBytes + 1)
        XCTAssertNil(SpeechFailureDetail.parse(huge))
        let long = try! JSONSerialization.data(withJSONObject: ["detail": String(repeating: "x", count: 700)])
        XCTAssertEqual(SpeechFailureDetail.parse(long)?.count, 600)
    }
    func testControlsAndWhitespaceAreCollapsed() {
        let data = try! JSONSerialization.data(withJSONObject: ["detail": "Bad\u{1B}\n  input\ttext"])
        XCTAssertEqual(SpeechFailureDetail.parse(data), "Bad input text")
    }
}
