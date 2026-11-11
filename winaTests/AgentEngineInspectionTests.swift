import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentEngineInspectionTests: XCTestCase {
    func testGrantRequiresApprovalAndSensitiveCommandsShowTheirCode() async throws {
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<p>Inspector test</p>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        do {
            _ = try await call(["action": "authorize"], navigator) { _ in false }
            XCTFail("Unapproved inspection must not create a grant")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        XCTAssertNil(navigator.agentInspectorGrant)
        let before = try await marker(navigator)
        XCTAssertNil(before)

        let grant = try await call(["action": "authorize"], navigator) { prompt in
            XCTAssertTrue(prompt.contains("unredacted"))
            XCTAssertTrue(prompt.contains("pause JavaScript"))
            return true
        }
        let id = try XCTUnwrap(grant["grantId"] as? String)
        let nonce = try XCTUnwrap(grant["nonce"] as? String)
        XCTAssertNotNil(UUID(uuidString: nonce))
        XCTAssertEqual(grant["documentId"] as? String, navigator.documentID.uuidString)
        XCTAssertEqual(grant["bundleId"] as? String, Bundle.main.bundleIdentifier)
        let installed = try await marker(navigator)
        XCTAssertTrue(installed == nonce)
        let visibleToPage = try await navigator.evaluateJavaScriptReportingErrors("typeof globalThis.__walnutInspectorNonce")
        XCTAssertEqual(visibleToPage as? String, "undefined")

        let read = try await call(["action": "validate", "grantId": id, "method": "Debugger.getScriptSource"], navigator) { _ in
            XCTFail("Approved raw reads should use the existing grant")
            return false
        }
        XCTAssertEqual(read["valid"] as? Bool, true)
        XCTAssertNil(read["nonce"])

        let code = "function () {\n    return this.value;\n}"
        let arguments: [String: Any] = [
            "action": "validate", "grantId": id, "method": "Runtime.callFunctionOn",
            "params": ["functionDeclaration": code, "objectId": "fixture-object"]
        ]
        do {
            _ = try await call(arguments, navigator) { prompt in
                XCTAssertTrue(prompt.contains("Runtime.callFunctionOn"))
                XCTAssertTrue(prompt.contains(code))
                XCTAssertTrue(prompt.contains("fixture-object"))
                return false
            }
            XCTFail("Runtime evaluation must require a separate approval")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The iPhone did not approve this action.")
        }
        do {
            _ = try await call(["action": "validate", "grantId": id, "method": "Target.sendMessageToTarget"], navigator) { _ in
                XCTFail("A target-switch command cannot request approval")
                return true
            }
            XCTFail("Commands outside the current-target allowlist must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("method is unavailable"))
        }
        withExtendedLifetime(webView) {}
    }

    func testGrantEndsOnDocumentChangeAndExplicitRevocation() async throws {
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<p>First document</p>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let first = try await call(["action": "authorize"], navigator)
        let firstID = try XCTUnwrap(first["grantId"] as? String)
        do {
            _ = try await call(["action": "authorize"], navigator)
            XCTFail("An active inspector grant cannot be silently replaced")
        } catch {
            XCTAssertEqual(error.localizedDescription, "End the existing WebKit inspector grant first.")
        }

        await webView.loadHTMLStringAsync("<p>Second document</p>", baseURL: nil)
        navigator.documentDidChange(in: webView)
        XCTAssertNil(navigator.agentInspectorGrant)
        try await assertInactive(firstID, navigator)

        let second = try await call(["action": "authorize"], navigator)
        let secondID = try XCTUnwrap(second["grantId"] as? String)
        XCTAssertNotEqual(firstID, secondID)
        do {
            _ = try await call(["action": "end", "grantId": firstID], navigator)
            XCTFail("A stale end must not revoke a replacement grant")
        } catch {
            XCTAssertEqual(navigator.agentInspectorGrant?.id.uuidString, secondID)
        }

        let end = try await call(["action": "end", "grantId": secondID], navigator)
        XCTAssertEqual(end["ended"] as? Bool, true)
        XCTAssertNil(navigator.agentInspectorGrant)
        try await assertInactive(secondID, navigator)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while try await marker(navigator) != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let cleared = try await marker(navigator)
        XCTAssertNil(cleared)
        withExtendedLifetime(webView) {}
    }

    func testGrantCannotAuthorizeACommandAfterDisconnectDuringApproval() async throws {
        let webView = WKWebView(frame: .zero)
        await webView.loadHTMLStringAsync("<p>Disconnect fixture</p>", baseURL: nil)
        let navigator = WebViewNavigator()
        navigator.attach(to: webView)
        let grant = try await call(["action": "authorize"], navigator)
        let id = try XCTUnwrap(grant["grantId"] as? String)
        do {
            _ = try await call(["action": "validate", "grantId": id, "method": "Debugger.pause"], navigator) { _ in
                AgentEngineInspection.revoke(navigator)
                return true
            }
            XCTFail("A disconnected grant cannot authorize the pending command")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The WebKit inspector grant is no longer active for this document.")
        }
        try await assertInactive(id, navigator)
        withExtendedLifetime(webView) {}
    }

    private func assertInactive(_ grantID: String, _ navigator: WebViewNavigator) async throws {
        do {
            _ = try await call(["action": "validate", "grantId": grantID], navigator)
            XCTFail("A stale grant must not validate")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The WebKit inspector grant is no longer active for this document.")
        }
    }

    private func marker(_ navigator: WebViewNavigator) async throws -> String? {
        try await navigator.evaluateJavaScriptReportingErrors(
            "globalThis.__walnutInspectorNonce ?? null", contentWorld: AgentEngineInspection.contentWorld
        ) as? String
    }

    private func call(
        _ arguments: [String: Any], _ navigator: WebViewNavigator, approve: @escaping (String) async -> Bool = { _ in true }
    ) async throws -> [String: Any] {
        try await AgentEngineInspection.call(
            input: AgentDevInput(values: arguments), context: AgentDevContext(navigator: navigator, authorize: approve)
        )
    }
}
