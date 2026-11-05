//
//  NetworkManagerTests.swift
//  winaTests
//
//  Tests for NetworkManager request tracking, memory management, and statistics.
//

import XCTest
@testable import wina

final class NetworkManagerTests: XCTestCase {

    var manager: NetworkManager!

    override func setUp() {
        super.setUp()
        manager = NetworkManager()
    }

    override func tearDown() {
        manager.clear()
        manager = nil
        super.tearDown()
    }

    @MainActor
    func testOpenDetailTracksRequestReplacementAndRemoval() async throws {
        let id = UUID()
        manager.addRequest(id: id.uuidString, method: "GET", url: "https://example.com", requestType: "fetch", headers: nil, body: nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let detail = LiveNetworkDetailView(manager: manager, requestID: id)
        XCTAssertTrue(try XCTUnwrap(detail.request).isPending)
        manager.updateRequest(id: id.uuidString, status: 200, statusText: "OK", responseHeaders: ["content-type": "text/plain"], responseBody: "done", error: nil)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertEqual(detail.request?.status, 200)
        XCTAssertEqual(detail.request?.responseBody, "done")
        XCTAssertFalse(try XCTUnwrap(detail.request).isPending)
        manager.clear()
        XCTAssertNil(detail.request)
    }

    // MARK: - Request Lifecycle Tests

    func testAddRequestCreatesNewEntry() {
        let id = UUID().uuidString
        manager.addRequest(
            id: id,
            method: "GET",
            url: "https://example.com/api",
            requestType: "fetch",
            headers: ["Accept": "application/json"],
            body: nil
        )

        // Wait for async dispatch
        let expectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.requests.count, 1)
        XCTAssertEqual(manager.requests.first?.method, "GET")
        XCTAssertEqual(manager.requests.first?.url, "https://example.com/api")
        XCTAssertNil(manager.requests.first?.status)  // Still pending
    }

    func testAddRequestNormalizesMethodToUppercase() {
        manager.addRequest(
            id: UUID().uuidString,
            method: "post",
            url: "https://example.com",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let expectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.requests.first?.method, "POST")
    }

    func testUpdateRequestSetsStatusAndResponse() {
        let id = UUID().uuidString

        manager.addRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: 200,
            statusText: "OK",
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{\"success\": true}",
            error: nil
        )

        let updateExpectation = expectation(description: "Request updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.status, 200)
        XCTAssertEqual(request?.statusText, "OK")
        XCTAssertNotNil(request?.endTime)
    }

    func testSimulatedFetchRequestBackfillsBodyOnComplete() {
        let id = UUID().uuidString
        let requestBody = #"{"user":"walnut","mode":"json"}"#

        // fetch(Request) 시나리오를 시뮬레이션: start에는 body가 비어 있고 complete에서 보완됩니다.
        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/login",
            requestType: "fetch",
            headers: ["Content-Type": "application/json"],
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: 201,
            statusText: "Created",
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: #"{"ok":true}"#,
            error: nil,
            requestBody: requestBody
        )

        let updateExpectation = expectation(description: "Request updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.requestBodyPreview, requestBody)
        XCTAssertEqual(request?.requestBody, requestBody)
    }

    func testSimulatedFetchRequestBackfillsFormDataBodyOnError() {
        let id = UUID().uuidString
        let formBody = "email=test@example.com&name=walnut"

        // 실패 요청도 error 이벤트에 포함된 requestBody로 보강되는지 확인합니다.
        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/signup",
            requestType: "fetch",
            headers: ["Content-Type": "multipart/form-data"],
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: nil,
            statusText: nil,
            responseHeaders: nil,
            responseBody: nil,
            error: "Network error",
            requestBody: formBody
        )

        let updateExpectation = expectation(description: "Request error updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.requestBodyPreview, formBody)
        XCTAssertEqual(request?.requestBody, formBody)
        XCTAssertEqual(request?.error, "Network error")
    }

    func testRequestBodyBackfillDoesNotMarkPendingRequestAsComplete() {
        let id = UUID().uuidString
        let requestBody = #"{"step":"pending"}"#

        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/pending",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequestBody(id: id, requestBody: requestBody)

        let updateExpectation = expectation(description: "Request body backfilled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.requestBodyPreview, requestBody)
        XCTAssertNil(request?.endTime)
        XCTAssertTrue(request?.isPending ?? false)
    }

    func testUpdateRequestBodyIgnoresEmptyBody() {
        let id = UUID().uuidString

        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/empty",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequestBody(id: id, requestBody: "")

        let updateExpectation = expectation(description: "Empty body ignored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertNil(request?.requestBodyPreview)
        XCTAssertNil(request?.requestBody)
    }

    func testUpdateRequestWithoutRequestBodyKeepsExistingBackfilledBody() {
        let id = UUID().uuidString
        let backfilled = "token=abc123"

        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/session",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequestBody(id: id, requestBody: backfilled)

        let bodyExpectation = expectation(description: "Request body backfilled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            bodyExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: 204,
            statusText: "No Content",
            responseHeaders: nil,
            responseBody: nil,
            error: nil,
            requestBody: nil
        )

        let updateExpectation = expectation(description: "Request updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.requestBodyPreview, backfilled)
        XCTAssertEqual(request?.requestBody, backfilled)
    }

    func testPlaceholderRequestBodyDoesNotOverrideExistingBackfilledBody() {
        let id = UUID().uuidString
        let actualBody = #"{"email":"hello@walnut.dev"}"#
        let placeholder = "ReadableStream"

        // fetch(Request) 시나리오: 실제 본문 backfill 이후 complete에서 placeholder가 다시 올 수 있습니다.
        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/profile",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequestBody(id: id, requestBody: actualBody)

        let backfillExpectation = expectation(description: "Body backfilled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            backfillExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: 200,
            statusText: "OK",
            responseHeaders: nil,
            responseBody: nil,
            error: nil,
            requestBody: placeholder
        )

        let updateExpectation = expectation(description: "Complete updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.requestBodyPreview, actualBody)
        XCTAssertEqual(request?.requestBody, actualBody)
    }

    func testWhitespaceOnlyBodyIsPreservedAndNotOverriddenByPlaceholder() {
        let id = UUID().uuidString
        let whitespaceBody = "   \n"
        let placeholder = "ReadableStream"

        manager.addRequest(
            id: id,
            method: "POST",
            url: "https://example.com/api/whitespace",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequestBody(id: id, requestBody: whitespaceBody)

        let backfillExpectation = expectation(description: "Whitespace body backfilled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            backfillExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: 200,
            statusText: "OK",
            responseHeaders: nil,
            responseBody: nil,
            error: nil,
            requestBody: placeholder
        )

        let updateExpectation = expectation(description: "Complete updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let request = manager.requests.first
        XCTAssertEqual(request?.requestBodyPreview, whitespaceBody)
        XCTAssertEqual(request?.requestBody, whitespaceBody)
    }

    func testUpdateNonexistentRequestDoesNothing() {
        let missingId = UUID()
        manager.updateRequest(
            id: missingId.uuidString,
            status: 200,
            statusText: "OK",
            responseHeaders: nil,
            responseBody: "response",
            error: nil,
            requestBody: "request"
        )

        let expectation = expectation(description: "Update processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(manager.requests.isEmpty)
        XCTAssertNil(NetworkBodyStorage.shared.load(id: missingId, type: .request))
        XCTAssertNil(NetworkBodyStorage.shared.load(id: missingId, type: .response))
    }

    func testPendingCountTracksIncompleteRequests() {
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString

        manager.addRequest(id: id1, method: "GET", url: "https://a.com", requestType: "fetch", headers: nil, body: nil)
        manager.addRequest(id: id2, method: "POST", url: "https://b.com", requestType: "xhr", headers: nil, body: nil)

        let addExpectation = expectation(description: "Requests added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.pendingCount, 2)

        manager.updateRequest(id: id1, status: 200, statusText: "OK", responseHeaders: nil, responseBody: nil, error: nil)

        let updateExpectation = expectation(description: "Request updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.pendingCount, 1)
    }

    func testErrorCountTracksFailedRequests() {
        let id = UUID().uuidString

        manager.addRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.updateRequest(
            id: id,
            status: 500,
            statusText: "Internal Server Error",
            responseHeaders: nil,
            responseBody: nil,
            error: nil
        )

        let updateExpectation = expectation(description: "Request updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.errorCount, 1)
    }

    // MARK: - Clear Tests

    func testClearRemovesAllRequests() {
        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "https://example.com/1",
            requestType: "fetch",
            headers: nil,
            body: nil
        )
        manager.addRequest(
            id: UUID().uuidString,
            method: "POST",
            url: "https://example.com/2",
            requestType: "xhr",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Requests added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.requests.count, 2)

        manager.clear()

        XCTAssertTrue(manager.requests.isEmpty)
    }

    func testClearIfNotPreservedClearsWhenPreserveLogFalse() {
        // Temporarily set preserveLog to false
        UserDefaults.standard.set(false, forKey: "networkPreserveLog")

        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "https://example.com",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.clearIfNotPreserved()

        XCTAssertTrue(manager.requests.isEmpty)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "networkPreserveLog")
    }

    func testClearIfNotPreservedKeepsWhenPreserveLogTrue() {
        // Set preserveLog to true
        UserDefaults.standard.set(true, forKey: "networkPreserveLog")

        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "https://example.com",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let addExpectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            addExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        manager.clearIfNotPreserved()

        XCTAssertEqual(manager.requests.count, 1)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "networkPreserveLog")
    }

    // MARK: - Mixed Content Tests

    func testMixedContentDetectsHTTPOnHTTPSPage() {
        // Set page as HTTPS
        manager.pageURL = URL(string: "https://secure.com")

        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "http://insecure.com/image.png",  // HTTP resource
            requestType: "image",
            headers: nil,
            body: nil
        )

        let expectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.mixedContentCount, 1)
    }

    func testMixedContentIgnoresHTTPSOnHTTPS() {
        // Set page as HTTPS
        manager.pageURL = URL(string: "https://secure.com")

        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "https://secure.com/api",  // HTTPS resource
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let expectation = expectation(description: "Request added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(manager.mixedContentCount, 0)
    }

    // MARK: - Page Security Tests

    func testPageIsSecureReturnsCorrectValue() {
        manager.pageURL = URL(string: "https://example.com")
        XCTAssertTrue(manager.pageIsSecure)

        manager.pageURL = URL(string: "http://example.com")
        XCTAssertFalse(manager.pageIsSecure)

        manager.pageURL = nil
        XCTAssertFalse(manager.pageIsSecure)
    }

    // MARK: - Capture Toggle Tests

    func testIsCapturingDisablesNewRequests() {
        manager.isCapturing = false

        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "https://example.com",
            requestType: "fetch",
            headers: nil,
            body: nil
        )

        let expectation = expectation(description: "Request processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(manager.requests.isEmpty)
    }

    // MARK: - Request Type Tests

    func testRequestTypeParsing() {
        manager.addRequest(
            id: UUID().uuidString,
            method: "GET",
            url: "https://example.com/api",
            requestType: "fetch",
            headers: nil,
            body: nil
        )
        manager.addRequest(
            id: UUID().uuidString,
            method: "POST",
            url: "https://example.com/data",
            requestType: "xhr",
            headers: nil,
            body: nil
        )

        let expectation = expectation(description: "Requests added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let fetchRequest = manager.requests.first { $0.url.contains("/api") }
        let xhrRequest = manager.requests.first { $0.url.contains("/data") }

        XCTAssertEqual(fetchRequest?.requestType, .fetch)
        XCTAssertEqual(xhrRequest?.requestType, .xhr)
    }
}

// MARK: - LogClearStrategy Tests

final class LogClearStrategyTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(LogClearStrategy.origin.displayName, "Same Origin")
        XCTAssertEqual(LogClearStrategy.page.displayName, "Each Page")
        XCTAssertEqual(LogClearStrategy.keep.displayName, "Keep All")
    }

    func testDescriptions() {
        XCTAssertFalse(LogClearStrategy.origin.description.isEmpty)
        XCTAssertFalse(LogClearStrategy.page.description.isEmpty)
        XCTAssertFalse(LogClearStrategy.keep.description.isEmpty)
    }

    func testAllCases() {
        XCTAssertEqual(LogClearStrategy.allCases.count, 3)
    }
}

final class LogClearStrategyResolverTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LogClearStrategyResolverTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testResolveStrategiesUsesIndependentKeys() {
        defaults.set(LogClearStrategy.page.rawValue, forKey: LogClearStrategy.consoleDefaultsKey)
        defaults.set(LogClearStrategy.keep.rawValue, forKey: LogClearStrategy.networkDefaultsKey)
        defaults.set(true, forKey: LogClearStrategy.migrationFlagKey)

        let resolver = LogClearStrategyResolver(defaults: defaults)
        let resolved = resolver.resolveStrategies()

        XCTAssertEqual(resolved.console, .page)
        XCTAssertEqual(resolved.network, .keep)
    }

    func testMigrateLegacyCopiesOnlyMissingKey() {
        defaults.set(LogClearStrategy.page.rawValue, forKey: LogClearStrategy.consoleDefaultsKey)
        defaults.set(LogClearStrategy.origin.rawValue, forKey: LogClearStrategy.legacyDefaultsKey)

        let resolver = LogClearStrategyResolver(defaults: defaults)
        let resolved = resolver.resolveStrategies()

        XCTAssertEqual(resolved.console, .page)
        XCTAssertEqual(resolved.network, .origin)
        XCTAssertNil(defaults.string(forKey: LogClearStrategy.legacyDefaultsKey))
        XCTAssertTrue(defaults.bool(forKey: LogClearStrategy.migrationFlagKey))
    }

    func testMigrateLegacyDoesNotOverrideExistingSeparatedKeys() {
        defaults.set(LogClearStrategy.page.rawValue, forKey: LogClearStrategy.consoleDefaultsKey)
        defaults.set(LogClearStrategy.keep.rawValue, forKey: LogClearStrategy.networkDefaultsKey)
        defaults.set(LogClearStrategy.origin.rawValue, forKey: LogClearStrategy.legacyDefaultsKey)

        let resolver = LogClearStrategyResolver(defaults: defaults)
        let resolved = resolver.resolveStrategies()

        XCTAssertEqual(resolved.console, .page)
        XCTAssertEqual(resolved.network, .keep)
    }

    func testShouldClearForEachPageAlwaysTrue() {
        let shouldClear = LogClearStrategyResolver.shouldClear(
            strategy: .page,
            currentURL: URL(string: "https://example.com/a"),
            newURL: URL(string: "https://example.com/b")
        )

        XCTAssertTrue(shouldClear)
    }

    func testShouldClearForSameOriginIsFalseWithinSameHost() {
        let shouldClear = LogClearStrategyResolver.shouldClear(
            strategy: .origin,
            currentURL: URL(string: "https://example.com/a"),
            newURL: URL(string: "https://example.com/b")
        )

        XCTAssertFalse(shouldClear)
    }

    func testShouldClearForSameOriginTreatsDefaultPortAsSameOrigin() {
        let shouldClear = LogClearStrategyResolver.shouldClear(
            strategy: .origin,
            currentURL: URL(string: "https://example.com:443/a"),
            newURL: URL(string: "https://example.com/b")
        )

        XCTAssertFalse(shouldClear)
    }

    func testShouldClearForSameOriginIsTrueWhenHostChanges() {
        let shouldClear = LogClearStrategyResolver.shouldClear(
            strategy: .origin,
            currentURL: URL(string: "https://example.com"),
            newURL: URL(string: "https://api.example.com")
        )

        XCTAssertTrue(shouldClear)
    }

    func testShouldClearForSameOriginIsTrueWhenSchemeChanges() {
        let shouldClear = LogClearStrategyResolver.shouldClear(
            strategy: .origin,
            currentURL: URL(string: "http://example.com/page"),
            newURL: URL(string: "https://example.com/page")
        )

        XCTAssertTrue(shouldClear)
    }

    func testShouldClearForSameOriginIsFalseWhenOriginCannotBeResolved() {
        let shouldClear = LogClearStrategyResolver.shouldClear(
            strategy: .origin,
            currentURL: URL(string: "about:blank"),
            newURL: URL(string: "file:///tmp/index.html")
        )

        XCTAssertFalse(shouldClear)
    }
}
