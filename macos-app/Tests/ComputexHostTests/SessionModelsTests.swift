import XCTest
@testable import ComputexHost

final class SessionModelsTests: XCTestCase {
    func testSessionSummaryCodableRoundTrip() throws {
        let summary = VMSessionSummary(id: "session-1", name: "Session 1", kind: .disposable)
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(VMSessionSummary.self, from: data)
        XCTAssertEqual(decoded, summary)
    }

    func testSessionKindLabels() {
        XCTAssertEqual(SessionKind.primary.label, "Primary")
        XCTAssertEqual(SessionKind.disposable.label, "Disposable")
    }
}
