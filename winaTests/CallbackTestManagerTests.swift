import XCTest
@testable import wina

@MainActor
final class CallbackTestManagerTests: XCTestCase {
    func testIncomingURLPreservesRepeatedParametersFlagsAndOrder() throws {
        let manager = CallbackTestManager.shared
        let originalURL = manager.lastCallbackURL
        let originalParameters = manager.callbackParameters
        let originalTime = manager.lastCallbackTime
        let originalAlert = manager.showResultAlert
        defer {
            manager.lastCallbackURL = originalURL
            manager.callbackParameters = originalParameters
            manager.lastCallbackTime = originalTime
            manager.showResultAlert = originalAlert
        }
        let url = try XCTUnwrap(URL(string:
            "walnut://callback?value=first&flag&value=second&empty=&value=%26%3D&%ED%82%A4=%EA%B0%92"))
        manager.handleIncomingURL(url)

        XCTAssertEqual(manager.lastCallbackURL, url)
        XCTAssertNotNil(manager.lastCallbackTime)
        XCTAssertTrue(manager.showResultAlert)
        XCTAssertEqual(manager.callbackParameters.map(\.name), ["value", "flag", "value", "empty", "value", "키"])
        XCTAssertEqual(manager.callbackParameters.map(\.value), ["first", nil, "second", "", "&=", "값"])
        let lines = manager.formattedResult.split(separator: "\n").map(String.init).filter { $0.hasPrefix("   • ") }
        XCTAssertEqual(lines, ["   • value: first", "   • flag: —", "   • value: second", "   • empty: ",
                               "   • value: &=", "   • 키: 값"])
        XCTAssertTrue(manager.formattedResult.contains(url.absoluteString))

        let nextURL = try XCTUnwrap(URL(string: "walnut://next"))
        manager.handleIncomingURL(nextURL)
        XCTAssertTrue(manager.callbackParameters.isEmpty)
        XCTAssertEqual(manager.lastCallbackURL, nextURL)
        manager.clearHistory()
        XCTAssertNil(manager.lastCallbackURL)
        XCTAssertNil(manager.lastCallbackTime)
        XCTAssertTrue(manager.callbackParameters.isEmpty)
    }
}
