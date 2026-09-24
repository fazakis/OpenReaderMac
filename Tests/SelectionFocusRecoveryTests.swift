import XCTest
@testable import OpenReaderCore

final class SelectionFocusRecoveryTests: XCTestCase {
    func testColdChromeInitializesOnceAndRecoversAfterSeveralPolls() async throws {
        var initializations = 0, reads = 0, waits = 0
        let result: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(
            initial: .noValue, eligible: true,
            initialize: { initializations += 1; return true },
            read: { reads += 1; return reads < 5 ? .noValue : .found("selected web area") },
            contextIsCurrent: { true }, pause: { waits += 1 })
        guard case .found("selected web area") = result else { return XCTFail("Focus was not recovered") }
        XCTAssertEqual(initializations, 1)
        XCTAssertEqual(waits, 5)
        XCTAssertEqual(reads, 5)
    }
    func testWarmFocusReturnsWithoutInitializingOrWaiting() async throws {
        let result = try await SelectionFocusRecovery.recover(initial: .found("original focus"), eligible: true,
            initialize: { XCTFail("Must not initialize warm Chrome"); return true },
            read: { XCTFail("Must not replace existing focus"); return .noValue },
            contextIsCurrent: { XCTFail("No recovery context needed"); return true },
            pause: { XCTFail("No delay for warm Chrome") })
        guard case .found("original focus") = result else { return XCTFail() }
    }
    func testOtherAppsAndPermissionErrorsAreNotRetried() async throws {
        for (initial, eligible) in [(SelectionFocusRead<String>.noValue, false), (.failed(-25211), true)] {
            let result = try await SelectionFocusRecovery.recover(initial: initial, eligible: eligible,
                initialize: { XCTFail("Unexpected activation"); return true }, read: { .found("wrong") },
                contextIsCurrent: { XCTFail("Unexpected retry"); return true }, pause: { XCTFail("Unexpected delay") })
            switch result {
            case .noValue: XCTAssertFalse(eligible)
            case .failed(let code): XCTAssertEqual(code, -25211)
            case .found: XCTFail()
            }
        }
    }
    func testPersistentMissingFocusHasBoundedRetries() async throws {
        var reads = 0, initializations = 0
        let result: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(initial: .noValue, eligible: true,
            initialize: { initializations += 1; return true }, read: { reads += 1; return .noValue },
            contextIsCurrent: { true }, pause: {})
        guard case .noValue = result else { return XCTFail() }
        XCTAssertEqual(reads, 10)
        XCTAssertEqual(initializations, 1)
    }
    func testFailedRoleReadDoesNotPollOrHideFailure() async throws {
        let result: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(initial: .noValue, eligible: true,
            initialize: { false }, read: { XCTFail(); return .found("wrong") },
            contextIsCurrent: { true }, pause: { XCTFail() })
        guard case .noValue = result else { return XCTFail() }
    }
    func testChangedSourceDuringWaitStopsBeforeReadingSelection() async throws {
        var current = true
        do {
            let _: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(initial: .noValue, eligible: true,
                initialize: { true }, read: { XCTFail("Must not read the changed source"); return .found("wrong") },
                contextIsCurrent: { current }, pause: { current = false })
            XCTFail("Expected source change")
        } catch SelectionFocusRecoveryError.sourceChanged { }
    }
    func testChangedSourceDuringFocusReadRejectsRecoveredElement() async throws {
        var current = true
        do {
            let _: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(initial: .noValue, eligible: true,
                initialize: { true }, read: { current = false; return .found("wrong window") },
                contextIsCurrent: { current }, pause: {})
            XCTFail("Expected source change")
        } catch SelectionFocusRecoveryError.sourceChanged { }
    }
    func testCancellationDuringInitializationWaitStopsRecovery() async throws {
        do {
            let _: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(initial: .noValue, eligible: true,
                initialize: { true }, read: { XCTFail("Must not read after Stop"); return .found("wrong") },
                contextIsCurrent: { true }, pause: { throw CancellationError() })
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
    }
    func testAXErrorAfterInitializationIsNotHiddenOrRetried() async throws {
        var reads = 0
        let result: SelectionFocusRead<String> = try await SelectionFocusRecovery.recover(initial: .noValue, eligible: true,
            initialize: { true }, read: { reads += 1; return .failed(-25204) },
            contextIsCurrent: { true }, pause: {})
        guard case .failed(-25204) = result else { return XCTFail() }
        XCTAssertEqual(reads, 1)
    }
}
