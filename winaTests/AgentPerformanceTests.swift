import JavaScriptCore
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
        let script = ResourceTiming(
            id: UUID(), name: "https://fixture.example/assets/main.js", initiatorType: "script", startTime: 1,
            duration: 3, transferSize: 0, encodedBodySize: 123, decodedBodySize: 456
        )
        manager.data.resources = [script]
        let retained = try await read(["collect": false], navigator)
        XCTAssertEqual(measured["documentId"] as? String, navigator.documentID.uuidString)
        XCTAssertEqual(retained["documentId"] as? String, measured["documentId"] as? String)
        XCTAssertNotNil(retained["navigation"])
        XCTAssertEqual(retained["measuredAt"] as? Double, manager.data.timestamp.timeIntervalSince1970)
        XCTAssertEqual(retained["measuredAt"] as? Double, measured["measuredAt"] as? Double)
        XCTAssertEqual(retained["totalResources"] as? Int, 1)
        XCTAssertEqual(retained["totalResourceBytes"] as? Int, 123)
        let matchingType = try await read(["collect": false, "section": "resources", "query": "script"], navigator)
        let resources = try XCTUnwrap(matchingType["resources"] as? [[String: Any]])
        XCTAssertEqual(resources.first?["id"] as? String, script.id.uuidString)
        XCTAssertEqual(resources.first?["displayBytes"] as? Int, 123)
        let noMatch = try await read(["collect": false, "section": "resources", "query": "main.js"], navigator)
        XCTAssertEqual(noMatch["resourceCount"] as? Int, 0)

        _ = try await AgentDevTools.call(
            "performance_clear", arguments: [:], navigator: navigator,
            storage: StorageManager(), console: ConsoleSession(), authorize: { _ in true }
        )
        await assertReadFails(["collect": false], navigator, "No Performance measurement")
    }

    func testConnectionTimingCountsTLSOnlyOnce() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var window = this;
        var entry = {startTime: 0, redirectStart: 0, redirectEnd: 0, domainLookupStart: 1, domainLookupEnd: 2,
          connectStart: 10, connectEnd: 45, secureConnectionStart: 25, responseStart: 55, requestStart: 50,
          responseEnd: 56, domComplete: 60, domInteractive: 58, domContentLoadedEventEnd: 59, loadEventEnd: 61};
        var performance = {getEntriesByType: type => type === 'navigation' ? [entry] : []};
        """)
        let manager = PerformanceManager()
        for (tlsStart, tcpTime, tlsTime) in [(25.0, 15.0, 20.0), (0, 35, 0), (8, 35, 0)] {
            context.evaluateScript("entry.secureConnectionStart = \(tlsStart)")
            let json = try XCTUnwrap(context.evaluateScript(PerformanceManager.collectionScript)?.toString())
            manager.parseData(from: json)
            let navigation = try XCTUnwrap(manager.data.navigation)
            XCTAssertEqual(navigation.tcpTime, tcpTime)
            XCTAssertEqual(navigation.tlsTime, tlsTime)
            XCTAssertEqual(navigation.connectionTime, 35)
        }
    }

    func testRealPerformanceCollectionIgnoresPageWorldOverrides() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(server.port).rawValue)/page"))
        let (navigator, webView, _) = await openPage(url)
        let marker = try await navigator.evaluateJavaScriptReportingErrors(
            "window.__webVitals_initialized", contentWorld: PerformanceManager.contentWorld
        )
        XCTAssertEqual(marker as? Bool, true)
        let pageValue = try await navigator.callAsyncJavaScriptReportingErrors("""
        const response = await fetch('/measured-resource');
        await response.text();
        const observerWasVisible = typeof window.__webVitals_initialized !== 'undefined';
        const getEntries = performance.getEntriesByType.bind(performance);
        performance.getEntriesByType = type => {
            if (type === 'paint') return [{name: 'forged-paint', startTime: 0}];
            if (type === 'resource') return [{name: 'https://forged.test/', initiatorType: 'script',
                startTime: 0, duration: 1, transferSize: 5000000}];
            return getEntries(type);
        };
        window.__webVitals_lcp = 1234567;
        return {fetched: response.ok, observerWasVisible, paint: performance.getEntriesByType('paint')[0].name};
        """) as? [String: Any]
        XCTAssertEqual(pageValue?["fetched"] as? Bool, true)
        XCTAssertEqual(pageValue?["observerWasVisible"] as? Bool, false)
        XCTAssertEqual(pageValue?["paint"] as? String, "forged-paint")

        let result = try await read([:], navigator, authorize: { _ in
            XCTFail("Default Performance read requires no content approval")
            return false
        })
        XCTAssertNotNil(result["navigation"])
        XCTAssertNotEqual(result["lcpMs"] as? Double, 1_234_567)
        let paints = try XCTUnwrap(result["paints"] as? [[String: Any]])
        XCTAssertFalse(paints.contains { $0["name"] as? String == "forged-paint" })
        let resources = try XCTUnwrap(result["resources"] as? [[String: Any]])
        XCTAssertTrue(resources.contains { $0["type"] as? String == "Fetch/XHR" })
        XCTAssertFalse(resources.contains { $0["url"] as? String == "https://forged.test" })
        XCTAssertLessThan(try XCTUnwrap(result["totalResourceBytes"] as? Int), 5_000_000)
        withExtendedLifetime(webView) {}
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
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(PerformanceManager.observerUserScript)
        let webView = WKWebView(frame: .zero, configuration: configuration)
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
