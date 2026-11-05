import Network
import SwiftUI
import WebKit
import XCTest
@testable import wina

@MainActor
final class NavigationLogRegressionTests: XCTestCase {
    private final class Coordinator: WKWebViewCoordinator {
        var onFinish: (() -> Void)?
        var onCommit: (() -> Void)?
        var onFailure: ((Error) -> Void)?
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

        override func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            super.webView(webView, didCommit: navigation)
            onCommit?()
        }

        override func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            super.webView(webView, didFail: navigation, withError: error)
            onFailure?(error)
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
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
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

    func testFailedReloadDoesNotSkipClearingAtNextCommit() async {
        let defaults = UserDefaults.standard
        let key = LogClearStrategy.consoleDefaultsKey
        let migrationKey = LogClearStrategy.migrationFlagKey
        let previous = defaults.object(forKey: key)
        let previousMigration = defaults.object(forKey: migrationKey)
        defaults.set(LogClearStrategy.page.rawValue, forKey: key)
        defaults.set(true, forKey: migrationKey)
        defer {
            defaults.set(previous, forKey: key)
            defaults.set(previousMigration, forKey: migrationKey)
        }

        let navigator = WebViewNavigator()
        let webView = WKWebView(frame: .zero)
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        webView.navigationDelegate = coordinator

        for provisional in [true, false] {
            coordinator.prepareForManualReloadRequest()
            if provisional {
                coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.notConnectedToInternet))
            } else {
                coordinator.webView(webView, didFail: nil, withError: URLError(.networkConnectionLost))
            }
            navigator.consoleManager.logs.append(ConsoleLog(type: .log, message: "old page", source: nil, timestamp: Date()))
            let loaded = expectation(description: "Next document loaded")
            coordinator.onFinish = { loaded.fulfill() }
            webView.loadHTMLString("<html><body>next page</body></html>", baseURL: nil)
            await fulfillment(of: [loaded], timeout: 5)
            XCTAssertTrue(navigator.consoleManager.logs.isEmpty)
        }
    }

    func testCancelingOldDocumentDoesNotClearPreservedLogsDuringReload() async throws {
        let server = try await startHTTPServer(delayBody: true)
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/slow"))
        let defaults = UserDefaults.standard
        let keys = [LogClearStrategy.consoleDefaultsKey, LogClearStrategy.migrationFlagKey, "consolePreserveLog"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defaults.set(LogClearStrategy.page.rawValue, forKey: keys[0])
        defaults.set(true, forKey: keys[1])
        defaults.set(true, forKey: keys[2])
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }

        let navigator = WebViewNavigator()
        let webView = WKWebView(frame: .zero)
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        webView.navigationDelegate = coordinator
        let loaded = expectation(description: "Slow document committed")
        coordinator.onCommit = { loaded.fulfill() }
        webView.load(URLRequest(url: url))
        await fulfillment(of: [loaded], timeout: 5)

        navigator.consoleManager.logs.append(ConsoleLog(type: .log, message: "keep this log", source: nil, timestamp: Date()))
        let canceled = expectation(description: "First document canceled")
        coordinator.onFailure = { error in
            if (error as? URLError)?.code == .cancelled { canceled.fulfill() }
        }
        let reloaded = expectation(description: "Reload committed")
        coordinator.onCommit = { reloaded.fulfill() }
        XCTAssertNotNil(webView.reload())
        await fulfillment(of: [canceled, reloaded], timeout: 5)
        XCTAssertEqual(navigator.consoleManager.logs.map(\.message), ["keep this log"])
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func testNetworkHookPreservesFetchAndXHRHeaderValues() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/page"))
        let navigator = WebViewNavigator()
        let coordinator = WKWebViewCoordinator(isLoading: .constant(false), navigator: navigator)
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(coordinator, name: "networkRequest")
        controller.addUserScript(WKUserScript(
            source: WebViewScripts.networkHook, injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        defer { controller.removeScriptMessageHandler(forName: "networkRequest") }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        await webView.loadHTMLStringAsync("<html><body>header fixture</body></html>", baseURL: url)

        _ = try await webView.callAsyncJavaScript("""
        await fetch('/fetch', { headers: [['X-Walnut-Detail', 'first: second']] });
        await new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open('GET', '/xhr');
            xhr.onload = resolve;
            xhr.onerror = reject;
            xhr.send();
        });
        """, arguments: [:], in: nil, contentWorld: .page)
        let iteratorResponse = try await webView.callAsyncJavaScript("""
        function* pair() { yield 'X-One-Shot'; yield 'keep'; }
        const response = await fetch('/iterator', { headers: [pair()] });
        return response.status;
        """, arguments: [:], in: nil, contentWorld: .page) as? Int
        XCTAssertEqual(iteratorResponse, 200)
        let captured = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let requests = navigator.networkManager.requests
            let fetch = requests.first { $0.requestType == .fetch && $0.url.hasSuffix("/fetch") }
            let xhr = requests.first { $0.requestType == .xhr }
            return fetch?.requestHeaders?["x-walnut-detail"] == "first: second"
                && xhr?.responseHeaders?["x-walnut-detail"] == "first: second"
        }, object: nil)
        await fulfillment(of: [captured], timeout: 3)
    }

    private func startHTTPServer(delayBody: Bool = false) async throws -> NWListener {
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
                let trailing = delayBody ? String(repeating: " ", count: 4096) : ""
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nX-Walnut-Detail: first: second\r\nContent-Length: \(body.utf8.count + trailing.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    if delayBody {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            connection.send(content: Data(trailing.utf8), completion: .contentProcessed { _ in connection.cancel() })
                        }
                    } else {
                        connection.cancel()
                    }
                })
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 5)
        _ = try XCTUnwrap(listener.port)
        return listener
    }

}
