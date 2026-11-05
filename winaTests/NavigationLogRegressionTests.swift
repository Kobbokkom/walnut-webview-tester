import Network
import SwiftUI
import WebKit
import XCTest
@testable import wina

@MainActor
final class NavigationLogRegressionTests: XCTestCase {
    private final class Coordinator: WKWebViewCoordinator {
        var onFinish: (() -> Void)?
        var httpResponseCount = 0

        override func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                              decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, response.response is HTTPURLResponse { httpResponseCount += 1 }
            super.webView(webView, decidePolicyFor: response, decisionHandler: decisionHandler)
        }

        override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            super.webView(webView, didFinish: navigation)
            onFinish?()
        }
    }

    func testCurrentDocumentSurvivesCommitTimeClearPolicies() async throws {
        let firstServer = try await startHTTPServer()
        let secondServer = try await startHTTPServer()
        defer { firstServer.cancel(); secondServer.cancel() }
        let ports = try [XCTUnwrap(firstServer.port), XCTUnwrap(secondServer.port)]
        let urls = try ports.map { try XCTUnwrap(URL(string: "http://127.0.0.1:\($0.rawValue)/page")) }
        let defaults = UserDefaults.standard
        let keys = [LogClearStrategy.networkDefaultsKey, LogClearStrategy.consoleDefaultsKey,
                    LogClearStrategy.migrationFlagKey]
        let original = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, original) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: LogClearStrategy.migrationFlagKey)
        defaults.set(LogClearStrategy.keep.rawValue, forKey: LogClearStrategy.consoleDefaultsKey)

        for strategy in [LogClearStrategy.page, .origin, .keep] {
            defaults.set(strategy.rawValue, forKey: LogClearStrategy.networkDefaultsKey)
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            let navigator = WebViewNavigator()
            navigator.attach(to: webView)
            let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
            coordinator.observeWebView(webView)
            webView.navigationDelegate = coordinator

            for url in urls {
                let loaded = expectation(description: "\(strategy.rawValue) committed \(url)")
                coordinator.onFinish = { loaded.fulfill() }
                webView.load(URLRequest(url: url))
                await fulfillment(of: [loaded], timeout: 10)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                let current = navigator.networkManager.requests.first { $0.url == url.absoluteString }
                XCTAssertEqual(current?.status, 200, "\(strategy.rawValue): committing document must remain visible")
                let contentType = current?.responseHeaders?.first { $0.key.lowercased() == "content-type" }?.value
                XCTAssertEqual(contentType, "text/html")
            }
            let documents = navigator.networkManager.requests.filter { $0.requestType == .document }
            XCTAssertEqual(documents.count, strategy == .keep ? 2 : 1)
            XCTAssertEqual(documents.last?.url, urls.last?.absoluteString)
            XCTAssertEqual(coordinator.httpResponseCount, 2, "The fixture must deliver real HTTP responses")
            webView.navigationDelegate = nil
            coordinator.invalidateObservation()
            navigator.detach()
        }
    }

    private func startHTTPServer() async throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "Loopback HTTP fixture listening")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let body = "<html><body>navigation fixture</body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        _ = try XCTUnwrap(listener.port)
        return listener
    }

}
