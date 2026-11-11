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
                await fulfillment(of: [loaded], timeout: 20)
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
            await fulfillment(of: [loaded], timeout: 15)
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
        await fulfillment(of: [loaded], timeout: 15)

        navigator.consoleManager.logs.append(ConsoleLog(type: .log, message: "keep this log", source: nil, timestamp: Date()))
        let canceled = expectation(description: "First document canceled")
        coordinator.onFailure = { error in
            if (error as? URLError)?.code == .cancelled { canceled.fulfill() }
        }
        let reloaded = expectation(description: "Reload committed")
        coordinator.onCommit = { reloaded.fulfill() }
        XCTAssertNotNil(webView.reload())
        await fulfillment(of: [canceled, reloaded], timeout: 15)
        XCTAssertEqual(navigator.consoleManager.logs.map(\.message), ["keep this log"])
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    func testSupersededDocumentKeepsItsResponseAndDoesNotCorruptTheNextRequest() async throws {
        let slow = try await startHTTPServer(delayBody: true)
        let fast = try await startHTTPServer()
        defer { slow.cancel(); fast.cancel() }
        let slowURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(slow.port).rawValue)/slow"))
        let fastURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(fast.port).rawValue)/fast"))
        let defaults = UserDefaults.standard
        let keys = [LogClearStrategy.networkDefaultsKey, LogClearStrategy.migrationFlagKey]
        let previous = keys.map { defaults.object(forKey: $0) }
        defaults.set(LogClearStrategy.keep.rawValue, forKey: keys[0])
        defaults.set(true, forKey: keys[1])
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }

        let navigator = WebViewNavigator()
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = coordinator
        let slowCommitted = expectation(description: "Slow document committed")
        coordinator.onCommit = { slowCommitted.fulfill() }
        webView.load(URLRequest(url: slowURL))
        await fulfillment(of: [slowCommitted], timeout: 15)

        coordinator.onCommit = nil
        let fastFinished = expectation(description: "Second document finished")
        coordinator.onFinish = { fastFinished.fulfill() }
        webView.load(URLRequest(url: fastURL))
        await fulfillment(of: [fastFinished], timeout: 15)

        let first = try XCTUnwrap(navigator.networkManager.requests.first { $0.url == slowURL.absoluteString })
        let second = try XCTUnwrap(navigator.networkManager.requests.first { $0.url == fastURL.absoluteString })
        XCTAssertEqual(first.status, 200)
        XCTAssertEqual(second.status, 200)
        XCTAssertNil(second.error)
    }

    func testRedirectUsesDelegateEvidenceAndKeepsTheFinalStatus() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(server.port).rawValue)"))
        let defaults = UserDefaults.standard
        let keys = [LogClearStrategy.networkDefaultsKey, LogClearStrategy.migrationFlagKey]
        let previous = keys.map { defaults.object(forKey: $0) }
        defaults.set(LogClearStrategy.keep.rawValue, forKey: keys[0])
        defaults.set(true, forKey: keys[1])
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
        }

        let navigator = WebViewNavigator()
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = coordinator
        let loaded = expectation(description: "Redirect target finished")
        coordinator.onFinish = { loaded.fulfill() }
        webView.load(URLRequest(url: base.appending(path: "redirect")))
        await fulfillment(of: [loaded], timeout: 15)

        let redirect = try XCTUnwrap(navigator.networkManager.requests.first { $0.url.hasSuffix("/redirect") })
        let target = try XCTUnwrap(navigator.networkManager.requests.first { $0.url.hasSuffix("/target") })
        XCTAssertNil(redirect.status)
        XCTAssertEqual(redirect.statusText, "Redirect")
        XCTAssertFalse(redirect.isPending)
        XCTAssertEqual(target.status, 200)
    }

    func testCookieAddReportsRejectionAndPerformanceClearsOnlyForNewDocuments() async throws {
        let server = try await startHTTPServer()
        defer { server.cancel() }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(XCTUnwrap(server.port).rawValue)/page"))
        let navigator = WebViewNavigator()
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        navigator.attach(to: webView)
        webView.navigationDelegate = coordinator

        let loaded = expectation(description: "First page loaded")
        coordinator.onFinish = { loaded.fulfill() }
        webView.load(URLRequest(url: url))
        await fulfillment(of: [loaded], timeout: 15)

        let storage = StorageManager()
        storage.setNavigator(navigator)
        let accepted = await storage.addItem(key: "small", value: "works", type: .cookies, pageURL: url)
        XCTAssertTrue(accepted, storage.errorMessage ?? "The native store did not confirm the cookie.")
        let rejected = await storage.addItem(key: "large", value: String(repeating: "a", count: 10_000), type: .cookies, pageURL: url)
        XCTAssertFalse(rejected)
        let whitespace = await storage.addItem(key: " padded ", value: " value ", type: .cookies, pageURL: url)
        XCTAssertTrue(whitespace, storage.errorMessage ?? "The native store did not confirm the trimmed cookie.")
        let cookies = try await webView.evaluateJavaScript("document.cookie") as? String
        XCTAssertEqual(Set(cookies?.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) } ?? []), ["small=works", "padded=value"])

        await navigator.performanceManager.collect(using: navigator, reload: false)
        XCTAssertNotNil(navigator.performanceManager.data.navigation)
        let originalDocument = navigator.documentID
        _ = try await webView.evaluateJavaScript("location.hash = 'same-document'")
        XCTAssertEqual(navigator.documentID, originalDocument)
        XCTAssertNotNil(navigator.performanceManager.data.navigation)

        let next = expectation(description: "Second page loaded")
        coordinator.onFinish = { next.fulfill() }
        webView.load(URLRequest(url: url.deletingLastPathComponent().appending(path: "other")))
        await fulfillment(of: [next], timeout: 15)
        XCTAssertNotEqual(navigator.documentID, originalDocument)
        XCTAssertNil(navigator.performanceManager.data.navigation)
        await navigator.performanceManager.collect(using: navigator, reload: false)
        XCTAssertNotNil(navigator.performanceManager.data.navigation)
    }

    func testAgentCookieAddUsesRootPathFromNestedPage() async throws {
        let server = try await startHTTPServer { connection in
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html\r
            Set-Cookie: protected=original; Path=/; HttpOnly\r
            Content-Length: 13\r
            Connection: close\r
            \r
            <html></html>
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
        defer { server.cancel() }
        let port = try XCTUnwrap(server.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/account/settings"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigator = WebViewNavigator()
        let coordinator = Coordinator(isLoading: .constant(false), navigator: navigator)
        webView.navigationDelegate = coordinator
        let loaded = expectation(description: "Nested page loaded")
        coordinator.onFinish = { loaded.fulfill() }
        webView.load(URLRequest(url: url))
        await fulfillment(of: [loaded], timeout: 15)
        navigator.attach(to: webView)
        defer { navigator.detach() }

        let storage = StorageManager()
        storage.setNavigator(navigator)
        let addedInApp = await storage.addItem(key: "agent", value: "original", type: .cookies, pageURL: url)
        XCTAssertTrue(addedInApp)
        let result = try await AgentDevTools.call(
            "storage_write", arguments: ["action": "add", "type": "cookies", "key": "agent", "value": "original", "path": "/"],
            navigator: navigator, storage: storage, console: ConsoleSession(), authorize: { _ in true }
        ) as? [String: Any]
        XCTAssertEqual(result?["applied"] as? Bool, true)

        for key in ["agent", "protected"] {
            do {
                _ = try await AgentDevTools.call(
                    "storage_write", arguments: ["action": "add", "type": "cookies", "key": key, "value": "replace"],
                    navigator: navigator, storage: storage, console: ConsoleSession(), authorize: { _ in true }
                )
                XCTFail("An existing root cookie should not be overwritten")
            } catch {
                XCTAssertEqual(error.localizedDescription, "A cookie with this name already exists at /.")
            }
        }
        let cookies = await configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertEqual(cookies.filter { $0.name == "agent" && $0.value == "original" }.map(\.path).sorted(), ["/", "/account"])
        let protected = try XCTUnwrap(cookies.first { $0.name == "protected" })
        XCTAssertTrue(protected.isHTTPOnly)
        XCTAssertEqual(protected.value, "original")
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

}

@MainActor
extension XCTestCase {
    func startHTTPServer(
        delayBody: Bool = false,
        handleRequest: ((NWConnection) -> Void)? = nil
    ) async throws -> NWListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "Loopback HTTP fixture listening")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                if let handleRequest {
                    handleRequest(connection)
                    return
                }
                if let data, String(decoding: data, as: UTF8.self).hasPrefix("GET /redirect ") {
                    let redirect = "HTTP/1.1 307 Temporary Redirect\r\nLocation: /target\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(redirect.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
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
        await fulfillment(of: [ready], timeout: 10)
        _ = try XCTUnwrap(listener.port)
        return listener
    }

}
