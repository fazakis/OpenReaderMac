import Foundation

enum SelectionFocusRead<Element> {
    case found(Element)
    case noValue
    case failed(Int32)
}

enum SelectionFocusRecoveryError: Error {
    case sourceChanged
}

enum SelectionFocusRecovery {
    static func recover<Element>(
        initial: SelectionFocusRead<Element>,
        eligible: Bool,
        initialize: () -> Bool,
        read: () -> SelectionFocusRead<Element>,
        contextIsCurrent: () -> Bool,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(200)) }
    ) async throws -> SelectionFocusRead<Element> {
        try Task.checkCancellation()
        guard eligible, case .noValue = initial else { return initial }
        guard contextIsCurrent() else { throw SelectionFocusRecoveryError.sourceChanged }
        guard initialize() else { return initial }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        for _ in 0..<10 {
            try await pause()
            try Task.checkCancellation()
            guard contextIsCurrent() else { throw SelectionFocusRecoveryError.sourceChanged }
            guard ContinuousClock.now < deadline else { break }
            let result = read()
            guard contextIsCurrent() else { throw SelectionFocusRecoveryError.sourceChanged }
            switch result {
            case .noValue: continue
            case .found, .failed: return result
            }
        }
        return .noValue
    }
}
