import Foundation
import XCTest
@testable import wina

@MainActor
final class AgentBridgeTests: XCTestCase {
    func testRequestSchemaRejectsBooleanAsIntegerAndUnknownInputs() throws {
        let tool = AgentTool.definition("test", "Test", [
            "limit": ["type": "integer", "minimum": 1, "maximum": 3],
            "filter": ["type": "string", "enum": ["all", "errors"]]
        ], required: ["limit"])

        try AgentTool.validate(["limit": 2, "filter": "errors"], using: tool)
        XCTAssertThrowsError(try AgentTool.validate(["limit": true], using: tool))
        XCTAssertThrowsError(try AgentTool.validate(["limit": 4], using: tool))
        XCTAssertThrowsError(try AgentTool.validate(["limit": 2, "filter": "other"], using: tool))
        XCTAssertThrowsError(try AgentTool.validate(["limit": 2, "extra": 1], using: tool))
        XCTAssertThrowsError(try AgentTool.validate([:], using: tool))
    }

    func testSafariCapabilitiesDistinguishUnavailableToolsAndActions() throws {
        let safari = ContentView.agentCapabilities(safari: true)
        let wk = ContentView.agentCapabilities(safari: false)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(safari))
        XCTAssertEqual(safari["mode"] as? String, "safarivc")
        let unavailable = try XCTUnwrap(safari["unavailable"] as? [String])
        XCTAssertTrue(unavailable.contains("walnut_panel"))
        XCTAssertTrue(unavailable.contains("console_list"))
        XCTAssertFalse(unavailable.contains("walnut_browser"))
        XCTAssertFalse(unavailable.contains("walnut_screenshot"))
        let actions = try XCTUnwrap(safari["unavailableActions"] as? [String: [String]])
        XCTAssertEqual(actions["walnut_browser"], ["back", "forward", "initial", "stop", "wait"])
        XCTAssertEqual(actions["preload"], ["clear_logs", "logs"])
        XCTAssertEqual(wk["mode"] as? String, "wkwebview")
        XCTAssertEqual(wk["unavailable"] as? [String], [])
        XCTAssertEqual(wk["unavailableActions"] as? [String: [String]], [:])
        let safariTools = try XCTUnwrap(safari["tools"] as? [[String: Any]])
        let wkTools = try XCTUnwrap(wk["tools"] as? [[String: Any]])
        XCTAssertEqual(safariTools.compactMap { $0["name"] as? String }, wkTools.compactMap { $0["name"] as? String })
    }

    func testNavigationSeparatesHTTPStatusFromLoadCompletion() throws {
        let state = AgentNavigation()
        XCTAssertFalse(state.isTerminal, "A newly replaced navigator has not loaded the requested page yet")
        let firstNavigation = NSObject()
        let secondNavigation = NSObject()
        let url = try XCTUnwrap(URL(string: "https://example.com/demo?token=secret"))
        state.start(firstNavigation, url: url)
        XCTAssertFalse(state.isTerminal)
        state.response(403, url: url)
        let documentID = UUID()
        state.commit(documentID, navigation: firstNavigation)
        state.finish(firstNavigation, url: url)
        XCTAssertEqual(state.phase, "finished")
        XCTAssertTrue(state.isTerminal)
        XCTAssertEqual(state.documentID, documentID)
        XCTAssertEqual(state.evidence["httpStatus"] as? Int, 403)
        XCTAssertEqual(state.evidence["url"] as? String, "https://example.com/demo")

        let firstRun = state.runID
        state.start(secondNavigation, url: url)
        state.finish(firstNavigation, url: url, error: URLError(.cancelled))
        XCTAssertEqual(state.phase, "loading")
        state.finish(secondNavigation, url: nil, error: URLError(.notConnectedToInternet))
        XCTAssertEqual(state.phase, "failed")
        XCTAssertTrue(state.isTerminal)
        XCTAssertNil(state.documentID)
        XCTAssertNil(state.status)
        XCTAssertNotEqual(state.runID, firstRun)
    }

    func testMalformedRequestArgumentsRejected() throws {
        let valid = Data(#"{"id":"42","tool":"test","arguments":{"limit":2}}"#.utf8)
        let (request, arguments) = try AgentRequest.decode(valid)
        XCTAssertEqual(request.id, "42")
        XCTAssertEqual(arguments["limit"] as? Int, 2)
        let invalid = Data(#"{"id":"42","tool":"test","arguments":[]}"#.utf8)
        XCTAssertThrowsError(try AgentRequest.decode(invalid))
    }
}
