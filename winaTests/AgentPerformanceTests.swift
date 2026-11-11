import SwiftUI
import WebKit
import XCTest
@testable import wina

@MainActor
final class AgentPerformanceTests: XCTestCase {
    private final class Coordinator: WKWebViewCoordinator {
        var onStart: (() -> Void)?
        var onFinish: (() -> Void)?

        override func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            super.webView(webView, didStartProvisionalNavigation: navigation)
            let started = onStart
            onStart = nil
            started?()
        }

        override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            super.webView(webView, didFinish: navigation)
            let finished = onFinish
            onFinish = nil
            finished?()
        }
    }

    func testReadRequiresACompletedMeasurement() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(server.port).rawValue)/page"))
        let (navigator, webView, coordinator) = await openPage(url)
        defer { webView.navigationDelegate = nil; coordinator.onFinish = nil }
        let manager = navigator.performanceManager

        await assertReadFails(["collect": false], navigator, "No Performance measurement")
        manager.isLoading = true
        await assertReadFails(["collect": false], navigator, "already running")
        manager.isLoading = false
        manager.lastError = "Fixture collection failed"
        await assertReadFails(["collect": false], navigator, "Fixture collection failed")

        let measured = try await read([:], navigator)
        let retained = try await read(["collect": false], navigator)
        XCTAssertEqual(measured["documentId"] as? String, navigator.documentID.uuidString)
        XCTAssertEqual(retained["documentId"] as? String, measured["documentId"] as? String)
        XCTAssertNotNil(retained["navigation"])

        _ = try await AgentDevTools.call(
            "performance_clear", arguments: [:], navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        await assertReadFails(["collect": false], navigator, "No Performance measurement")
    }

    func testReloadMeasuresOnlyTheRequestedNavigation() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(server.port).rawValue)/page"))
        let (navigator, webView, coordinator) = await openPage(url)
        defer { webView.navigationDelegate = nil; coordinator.onStart = nil }
        let originalDocument = navigator.documentID
        let result = try await read(["reload": true], navigator)
        XCTAssertNotEqual(navigator.documentID, originalDocument)
        XCTAssertEqual(result["documentId"] as? String, navigator.documentID.uuidString)
        XCTAssertNotNil(result["navigation"])

        let replacement = url.deletingLastPathComponent().appendingPathComponent("replacement")
        coordinator.onStart = { webView.load(URLRequest(url: replacement)) }
        await assertReadFails(["reload": true], navigator, "different navigation interrupted")
        XCTAssertNil(navigator.performanceManager.data.navigation)
    }

    func testReloadRejectsDocumentChangedDuringApproval() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(server.port).rawValue)/page"))
        let (navigator, webView, coordinator) = await openPage(url)
        let replacement = url.deletingLastPathComponent().appendingPathComponent("replacement")
        var prompted = false
        await assertReadFails(["reload": true, "raw": true], navigator, "document changed") { _ in
            prompted = true
            let loaded = self.expectation(description: "Replacement finished while the Mac waited for approval")
            coordinator.onFinish = { loaded.fulfill() }
            webView.load(URLRequest(url: replacement))
            await self.fulfillment(of: [loaded], timeout: 10)
            return true
        }
        XCTAssertTrue(prompted)
    }

    private func openPage(_ url: URL) async -> (WebViewNavigator, WKWebView, Coordinator) {
        let navigator = WebViewNavigator()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        navigator.attach(to: webView)
        webView.navigationDelegate = coordinator
        let loaded = expectation(description: "Performance fixture finished")
        coordinator.onFinish = { loaded.fulfill() }
        webView.load(URLRequest(url: url))
        await fulfillment(of: [loaded], timeout: 10)
        return (navigator, webView, coordinator)
    }

    private func read(
        _ arguments: [String: Any],
        _ navigator: WebViewNavigator,
        authorize: @escaping (String) async -> Bool = { _ in true }
    ) async throws -> [String: Any] {
        let result = try await AgentDevTools.call(
            "performance_read", arguments: arguments, navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: authorize
        )
        return try XCTUnwrap(result as? [String: Any])
    }

    private func assertReadFails(
        _ arguments: [String: Any],
        _ navigator: WebViewNavigator,
        _ message: String,
        authorize: @escaping (String) async -> Bool = { _ in true },
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await read(arguments, navigator, authorize: authorize)
            XCTFail("Expected \(message)", file: file, line: line)
        } catch {
            XCTAssertTrue(error.localizedDescription.contains(message), error.localizedDescription, file: file, line: line)
        }
    }
}
