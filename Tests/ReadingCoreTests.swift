import XCTest
@testable import OpenReaderCore

final class ReadingCoreTests: XCTestCase {
    func testPreservesMixedUnicodeAndGreekPunctuation() {
        let source = "Hello world. Καλημέρα· τι κάνεις; Πολύ καλά; Yes! 👩🏽‍💻\nAnother line."
        let result = Segmenter.split(source)
        XCTAssertEqual(result.map(\.text).joined(), source)
        XCTAssertTrue(result.contains { $0.text.contains("τι κάνεις;") })
        XCTAssertTrue(Segmenter.containsGreek(source))
    }
    func testAbbreviationsAndDecimals() {
        let result = Segmenter.split("Dr. Smith paid 3.14 euros. Is that right?")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "Dr. Smith paid 3.14 euros. ")
    }
    func testLongUnbrokenTextAndGraphemes() {
        let input = String(repeating: "👨‍👩‍👧‍👦α", count: 501)
        let result = Segmenter.split(input, limit: 80)
        XCTAssertEqual(result.map(\.text).joined(), input)
        XCTAssertTrue(result.allSatisfy { $0.text.count <= 80 && $0.isFragment })
        XCTAssertEqual(Set(result.map(\.sentenceID)).count, 1)
    }
    func testWhitespaceAndEmpty() {
        XCTAssertTrue(Segmenter.split(" \n \t").isEmpty)
        let input = "One.\n\nTwo!  Three;\n"
        XCTAssertEqual(Segmenter.split(input).map(\.text).joined(), input)
    }
    func testCancellationRejectsLateResponsesAndCompletions() {
        var ledger = PlaybackLedger(); let old = ledger.epoch
        XCTAssertTrue(ledger.enqueue(epoch: old, chunk: 0, frames: 100))
        let current = ledger.reset()
        XCTAssertFalse(ledger.enqueue(epoch: old, chunk: 1, frames: 100))
        XCTAssertTrue(ledger.enqueue(epoch: current, chunk: 0, frames: 80))
        XCTAssertFalse(ledger.completed(epoch: old, frames: 100))
        XCTAssertEqual(ledger.pendingFrames, 80)
    }
    func testAudioOrderingAndRepeatedBuffersWithinSentence() {
        var ledger = PlaybackLedger(); let epoch = ledger.epoch
        XCTAssertTrue(ledger.enqueue(epoch: epoch, chunk: 0, frames: 20))
        XCTAssertTrue(ledger.enqueue(epoch: epoch, chunk: 0, frames: 20))
        XCTAssertTrue(ledger.enqueue(epoch: epoch, chunk: 1, frames: 20))
        XCTAssertFalse(ledger.enqueue(epoch: epoch, chunk: 0, frames: 20))
        XCTAssertEqual(ledger.pendingFrames, 60)
        XCTAssertTrue(ledger.completed(epoch: epoch, frames: 20))
        XCTAssertEqual(ledger.pendingFrames, 40)
    }
    func testPCMFramingAcrossArbitraryNetworkBoundaries() {
        var framer = PCMFramer()
        XCTAssertEqual(framer.append(Data([1])), Data())
        XCTAssertTrue(framer.hasIncompleteSample)
        XCTAssertEqual(framer.append(Data([2,3,4,5])), Data([1,2,3,4]))
        XCTAssertEqual(framer.append(Data([6])), Data([5,6]))
        XCTAssertFalse(framer.hasIncompleteSample)
    }
    func testMultiColumnReadingOrder() {
        let left1 = OCRBlock(text: "left1", bounds: CGRect(x: 0.05,y: 0.2,width: 0.35,height: 0.04))
        let left2 = OCRBlock(text: "left2", bounds: CGRect(x: 0.05,y: 0.3,width: 0.35,height: 0.04))
        let right1 = OCRBlock(text: "right1", bounds: CGRect(x: 0.55,y: 0.2,width: 0.35,height: 0.04))
        let right2 = OCRBlock(text: "right2", bounds: CGRect(x: 0.55,y: 0.3,width: 0.35,height: 0.04))
        let title = OCRBlock(text: "title", bounds: CGRect(x: 0.05,y: 0.02,width: 0.85,height: 0.06))
        XCTAssertEqual(ReadingOrder.ordered([right2,left2,title,right1,left1]).map(\.text), ["title","left1","left2","right1","right2"])
    }
    func testDisplayCoordinatesWithNegativeOriginAndRetina() {
        let screen = CGRect(x: -1920,y: -100,width: 1920,height: 1080)
        let rect = CaptureGeometry.quartzRect(local: CGRect(x: 100,y: 100,width: 500,height: 300), screenFrame: screen, primaryTop: 1440)
        XCTAssertEqual(rect, CGRect(x: -1820,y: 1140,width: 500,height: 300))
        let display = CGRect(x: -1920,y: 460,width: 1920,height: 1080)
        let local = CaptureGeometry.displayLocal(rect, displayFrame: display)
        XCTAssertEqual(local, CGRect(x: 100,y: 680,width: 500,height: 300))
        XCTAssertEqual(local.width*2, 1000) // Source coordinates are points; only output dimensions scale.
    }
    func testWordTimingRequiresExactTextAndValidTime() {
        let timestamps = [WordTimestamp(word: "Hello", start: 0, end: 0.4), WordTimestamp(word: "world", start: 0.4, end: 0.9), WordTimestamp(word: ".", start: 0.9, end: 1.05)]
        let result = WordAlignment.align(timestamps, text: "Hello world.", duration: 1)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[1].range, NSRange(location: 6,length: 5))
        XCTAssertNil(WordAlignment.align(timestamps, text: "Hello different world.", duration: 1))
        XCTAssertNil(WordAlignment.align(timestamps, text: "Hello world.", duration: 0.2))
        XCTAssertNil(WordAlignment.align([WordTimestamp(word: "Hello", start: .nan, end: 1)], text: "Hello", duration: 1))
    }
    func testSourcePositionsAcrossPDFLineBreaks() throws {
        let text = "First line.\nSecond line."
        let map = try XCTUnwrap(SourceTextMap.align(text, fragments: [
            SourceTextFragment(text: "First line.\r\n", sourceOffset: 12),
            SourceTextFragment(text: "Second line.", sourceOffset: 7)
        ]))
        let second = SourceTextMap.selected(map, range: NSRange(location: 12, length: 6))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.element, 1)
        XCTAssertEqual(second.first?.sourceRange, NSRange(location: 7, length: 6))
    }
    func testSourcePositionsDisambiguateRepeatedText() throws {
        let text = "Same word. Same word."
        let map = try XCTUnwrap(SourceTextMap.align(text, fragments: [SourceTextFragment(text: "Same word."), SourceTextFragment(text: "Same word.")]))
        let selected = SourceTextMap.selected(map, range: NSRange(location: 11, length: 9))
        XCTAssertTrue(selected.allSatisfy { $0.element == 1 })
        XCTAssertEqual(selected.first?.textRange.location, 0)
    }
    func testSourcePositionsPreserveUnicodeAndSplitFormatting() throws {
        let text = "👩🏽‍💻 Καλημέρα highlighter"
        let map = try XCTUnwrap(SourceTextMap.align(text, fragments: [SourceTextFragment(text: "👩🏽‍💻 Καλημέρα high"), SourceTextFragment(text: "lighter")]))
        let range = (text as NSString).range(of: "highlighter")
        let pieces = SourceTextMap.selected(map, range: range)
        XCTAssertEqual(pieces.map(\.element), [0, 1])
        XCTAssertEqual(pieces.map { $0.textRange.length }, [4, 7])
        XCTAssertEqual(pieces.last?.textRange.location, 4)
    }
    func testSourceMappingRejectsChangedOrMissingText() {
        XCTAssertNil(SourceTextMap.align("one two", fragments: [SourceTextFragment(text: "one too")]))
        XCTAssertNil(SourceTextMap.align("one two", fragments: [SourceTextFragment(text: "one")]))
        XCTAssertNil(SourceTextMap.align("one", fragments: [SourceTextFragment(text: "one two")]))
        XCTAssertNil(SourceTextMap.align("test", fragments: [SourceTextFragment(text: "test", sourceOffset: -1)]))
    }

    func testFreshConnectionContainsNoPersonalDestination() {
        let connection = Connection()
        XCTAssertFalse(connection.useSSH)
        XCTAssertTrue(connection.sshHost.isEmpty)
        XCTAssertTrue(connection.sshUser.isEmpty)
        XCTAssertEqual(connection.serverURL, "http://127.0.0.1:18880/v1")
        XCTAssertEqual(connection.localPort, 18880)
    }
    func testExistingConnectionPreferencesSurviveNewDefaults() throws {
        let suite = "OpenReaderTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Original version's stored schema, using documentation-only values.
        let data = Data(#"{"useSSH":true,"sshHost":"192.0.2.10","sshUser":"example","localPort":18880,"serverURL":"http://127.0.0.1:18880/v1","voice":"af_alloy","language":"auto"}"#.utf8)
        defaults.set(data, forKey: "connection")
        let loaded = Connection.load(from: defaults)
        XCTAssertTrue(loaded.useSSH)
        XCTAssertEqual(loaded.sshHost, "192.0.2.10")
        XCTAssertEqual(loaded.sshUser, "example")
        XCTAssertEqual(try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(loaded)), loaded)
    }
    func testSSHAliasUsesConfigurationUserAndSafeArguments() {
        var connection = Connection(); connection.useSSH = true; connection.sshHost = "openreader-tts"
        let ssh = SSHConfiguration(connection: connection)
        XCTAssertNil(ssh.validationMessage)
        XCTAssertEqual(ssh.arguments.last, "openreader-tts")
        XCTAssertTrue(ssh.arguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(ssh.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(ssh.arguments.contains("127.0.0.1:18880:127.0.0.1:8880"))
        connection.sshUser = "example"
        XCTAssertEqual(SSHConfiguration(connection: connection).destination, "example@openreader-tts")
    }
    func testSSHRejectsOptionsAndInvalidLocalForward() {
        var connection = Connection(); connection.useSSH = true
        for host in ["", "-oProxyCommand=bad", "host name", "example.com;bad", "user@example.com"] {
            connection.sshHost = host
            XCTAssertNotNil(SSHConfiguration(connection: connection).validationMessage)
        }
        connection.sshHost = "openreader-tts"; connection.sshUser = "-o"
        XCTAssertNotNil(SSHConfiguration(connection: connection).validationMessage)
        connection.sshUser = ""; connection.serverURL = "https://example.com:18880/v1"
        XCTAssertNotNil(SSHConfiguration(connection: connection).validationMessage)
        connection.serverURL = "http://127.0.0.1:18881/v1"
        XCTAssertNotNil(SSHConfiguration(connection: connection).validationMessage)
    }

}
