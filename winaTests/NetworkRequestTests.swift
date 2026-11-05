//
//  NetworkRequestTests.swift
//  winaTests
//
//  Tests for NetworkRequest model: status colors, duration formatting,
//  content type detection, security indicators, and Equatable.
//

import SwiftUI
import Testing
@testable import wina

@Test("cURL export quotes captured arguments and replays the body literally")
func curlExportQuotesCapturedArguments() {
    let request = NetworkRequest(
        id: UUID(), method: "X'$(method)", url: "https://example.com/a'$(url)'b",
        requestHeaders: ["X-Custom'": "$(header)'", "@file": "ignored"], requestBodyPreview: "@payload'",
        startTime: Date(), pageIsSecure: true, requestType: .fetch
    )

    #expect(request.curlCommand == #"""
    curl --globoff --proto '=http,https' --request 'X'\''$(method)' --url 'https://example.com/a'\''$(url)'\''b' \
      --header 'X-Custom'\'': $(header)'\''' \
      --data-raw '@payload'\'''
    """#)
}

// MARK: - NetworkRequest Status Tests

@Suite("NetworkRequest Status")
struct NetworkRequestStatusTests {

    private func makeRequest(status: Int? = nil, error: String? = nil, endTime: Date? = nil) -> NetworkRequest {
        NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: status,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: endTime,
            error: error,
            requestType: .fetch
        )
    }

    @Test("Status 2xx is success (secondary)")
    func testStatus2xxIsSecondary() {
        let request200 = makeRequest(status: 200)
        let request201 = makeRequest(status: 201)
        let request204 = makeRequest(status: 204)

        #expect(request200.statusColor == .secondary)
        #expect(request201.statusColor == .secondary)
        #expect(request204.statusColor == .secondary)
    }

    @Test("Status 3xx is redirect (secondary)")
    func testStatus3xxIsSecondary() {
        let request301 = makeRequest(status: 301)
        let request302 = makeRequest(status: 302)
        let request304 = makeRequest(status: 304)

        #expect(request301.statusColor == .secondary)
        #expect(request302.statusColor == .secondary)
        #expect(request304.statusColor == .secondary)
    }

    @Test("Status 4xx is client error (orange with opacity)")
    func testStatus4xxIsOrangeOpacity() {
        let request400 = makeRequest(status: 400)
        let request404 = makeRequest(status: 404)
        let request403 = makeRequest(status: 403)

        #expect(request400.statusColor == .orange.opacity(0.8))
        #expect(request404.statusColor == .orange.opacity(0.8))
        #expect(request403.statusColor == .orange.opacity(0.8))
    }

    @Test("Status 5xx is server error (red with opacity)")
    func testStatus5xxIsRedOpacity() {
        let request500 = makeRequest(status: 500)
        let request502 = makeRequest(status: 502)
        let request503 = makeRequest(status: 503)

        #expect(request500.statusColor == .red.opacity(0.8))
        #expect(request502.statusColor == .red.opacity(0.8))
        #expect(request503.statusColor == .red.opacity(0.8))
    }

    @Test("Nil status is secondary")
    func testNilStatusIsSecondary() {
        let request = makeRequest(status: nil)
        #expect(request.statusColor == .secondary)
    }
}

// MARK: - NetworkRequest Status Boundary Tests

@Suite("NetworkRequest Status Boundaries")
struct NetworkRequestStatusBoundaryTests {

    private func makeRequest(status: Int?) -> NetworkRequest {
        NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: status,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )
    }

    // MARK: - Below Valid HTTP Status Range

    @Test("Status 0 falls to default (secondary)")
    func testStatus0() {
        let request = makeRequest(status: 0)
        #expect(request.statusColor == .secondary)
    }

    @Test("Status 99 falls to default (secondary)")
    func testStatus99() {
        let request = makeRequest(status: 99)
        #expect(request.statusColor == .secondary)
    }

    @Test("Status 100 (informational) falls to default (secondary)")
    func testStatus100() {
        let request = makeRequest(status: 100)
        #expect(request.statusColor == .secondary)
    }

    @Test("Negative status -1 falls to default (secondary)")
    func testStatusNegative1() {
        let request = makeRequest(status: -1)
        #expect(request.statusColor == .secondary)
    }

    // MARK: - 2xx Boundaries

    @Test("Status 199 (below 2xx) falls to default (secondary)")
    func testStatus199() {
        let request = makeRequest(status: 199)
        #expect(request.statusColor == .secondary)
    }

    @Test("Status 200 (start of 2xx) is secondary")
    func testStatus200Boundary() {
        let request = makeRequest(status: 200)
        #expect(request.statusColor == .secondary)
    }

    @Test("Status 299 (end of 2xx) is secondary")
    func testStatus299Boundary() {
        let request = makeRequest(status: 299)
        #expect(request.statusColor == .secondary)
    }

    // MARK: - 3xx Boundaries

    @Test("Status 300 (start of 3xx) is secondary")
    func testStatus300Boundary() {
        let request = makeRequest(status: 300)
        #expect(request.statusColor == .secondary)
    }

    @Test("Status 399 (end of 3xx) is secondary")
    func testStatus399Boundary() {
        let request = makeRequest(status: 399)
        #expect(request.statusColor == .secondary)
    }

    // MARK: - 4xx Boundaries

    @Test("Status 400 (start of 4xx) is orange")
    func testStatus400Boundary() {
        let request = makeRequest(status: 400)
        #expect(request.statusColor == .orange.opacity(0.8))
    }

    @Test("Status 499 (end of 4xx) is orange")
    func testStatus499Boundary() {
        let request = makeRequest(status: 499)
        #expect(request.statusColor == .orange.opacity(0.8))
    }

    // MARK: - 5xx Boundaries

    @Test("Status 500 (start of 5xx) is red")
    func testStatus500Boundary() {
        let request = makeRequest(status: 500)
        #expect(request.statusColor == .red.opacity(0.8))
    }

    @Test("Status 599 (within 5xx) is red")
    func testStatus599Boundary() {
        let request = makeRequest(status: 599)
        #expect(request.statusColor == .red.opacity(0.8))
    }

    @Test("Status 600 (above 5xx, but matches 500... pattern) is red")
    func testStatus600Boundary() {
        // 500... is open-ended range, so 600+ still matches
        let request = makeRequest(status: 600)
        #expect(request.statusColor == .red.opacity(0.8))
    }

    @Test("Status Int.max (extreme upper bound) is red")
    func testStatusIntMax() {
        let request = makeRequest(status: Int.max)
        #expect(request.statusColor == .red.opacity(0.8))
    }
}

// MARK: - NetworkRequest Duration Tests

@Suite("NetworkRequest Duration")
struct NetworkRequestDurationTests {

    @Test("Duration under 1 second shows milliseconds")
    func testDurationUnder1Second() {
        let start = Date()
        let end = start.addingTimeInterval(0.5)

        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: start,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: end,
            error: nil,
            requestType: .fetch
        )

        #expect(request.durationText == "500ms")
    }

    @Test("Duration over 1 second shows seconds")
    func testDurationOver1Second() {
        let start = Date()
        let end = start.addingTimeInterval(2.5)

        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: start,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: end,
            error: nil,
            requestType: .fetch
        )

        #expect(request.durationText == "2.50s")
    }

    @Test("Pending request shows ellipsis")
    func testPendingDuration() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: nil,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: nil,
            error: nil,
            requestType: .fetch
        )

        #expect(request.durationText == "...")
    }
}

// MARK: - NetworkRequest Duration Boundary Tests

@Suite("NetworkRequest Duration Boundaries")
struct NetworkRequestDurationBoundaryTests {

    private func makeRequest(duration: TimeInterval) -> NetworkRequest {
        let start = Date()
        let end = start.addingTimeInterval(duration)
        return NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: start,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: end,
            error: nil,
            requestType: .fetch
        )
    }

    // MARK: - Zero and Near-Zero

    @Test("Duration 0 shows 0ms")
    func testDuration0() {
        let request = makeRequest(duration: 0)
        #expect(request.durationText == "0ms")
    }

    @Test("Very small duration rounds to 0ms")
    func testDurationVerySmall() {
        let request = makeRequest(duration: 0.0001)  // 0.1ms
        #expect(request.durationText == "0ms")
    }

    @Test("Duration 0.001 (1ms) shows 1ms")
    func testDuration1ms() {
        let request = makeRequest(duration: 0.001)
        #expect(request.durationText == "1ms")
    }

    // MARK: - 1 Second Boundary (Critical Threshold)

    @Test("Duration 0.999 (just below 1s) shows 999ms")
    func testDurationJustBelow1Second() {
        let request = makeRequest(duration: 0.999)
        #expect(request.durationText == "999ms")
    }

    @Test("Duration exactly 1.0 shows 1.00s")
    func testDurationExactly1Second() {
        let request = makeRequest(duration: 1.0)
        #expect(request.durationText == "1.00s")
    }

    @Test("Duration 1.001 (just above 1s) shows 1.00s")
    func testDurationJustAbove1Second() {
        let request = makeRequest(duration: 1.001)
        #expect(request.durationText == "1.00s")
    }

    @Test("Duration 0.9999 rounds to 1000ms (still under 1s threshold)")
    func testDurationAlmostExactly1Second() {
        // 0.9999 * 1000 = 999.9, rounds to 1000
        let request = makeRequest(duration: 0.9999)
        #expect(request.durationText == "1000ms")
    }

    // MARK: - Large Values

    @Test("Duration 10 seconds shows 10.00s")
    func testDuration10Seconds() {
        let request = makeRequest(duration: 10.0)
        #expect(request.durationText == "10.00s")
    }

    @Test("Duration 100 seconds shows 100.00s")
    func testDuration100Seconds() {
        let request = makeRequest(duration: 100.0)
        #expect(request.durationText == "100.00s")
    }

    // MARK: - Decimal Precision

    @Test("Duration 1.234 rounds to 1.23s")
    func testDurationDecimalPrecision() {
        let request = makeRequest(duration: 1.234)
        #expect(request.durationText == "1.23s")
    }

    @Test("Duration 1.999 rounds to 2.00s")
    func testDurationRoundsUp() {
        let request = makeRequest(duration: 1.999)
        #expect(request.durationText == "2.00s")
    }
}

// MARK: - NetworkRequest Completion Tests

@Suite("NetworkRequest Completion State")
struct NetworkRequestCompletionTests {

    @Test("Request with endTime is complete")
    func testRequestWithEndTimeIsComplete() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.isComplete == true)
        #expect(request.isPending == false)
    }

    @Test("Request with error is complete")
    func testRequestWithErrorIsComplete() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: nil,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: nil,
            error: "Network error",
            requestType: .fetch
        )

        #expect(request.isComplete == true)
        #expect(request.isPending == false)
    }

    @Test("Request without endTime or error is pending")
    func testRequestWithoutEndTimeIsPending() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: nil,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: nil,
            error: nil,
            requestType: .fetch
        )

        #expect(request.isComplete == false)
        #expect(request.isPending == true)
    }
}

// MARK: - NetworkRequest Security Tests

@Suite("NetworkRequest Security")
struct NetworkRequestSecurityTests {

    @Test("HTTPS URL is secure")
    func testHttpsIsSecure() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.isSecure == true)
    }

    @Test("HTTP URL is not secure")
    func testHttpIsNotSecure() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "http://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: false,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.isSecure == false)
    }

    @Test("Mixed content detected: HTTPS page loading HTTP resource")
    func testMixedContentDetection() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "http://cdn.example.com/image.png",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,  // Page is HTTPS
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.isMixedContent == true)
        #expect(request.securityIcon == "exclamationmark.shield.fill")
        #expect(request.securityIconColor == .orange)
    }

    @Test("No mixed content when page is HTTP")
    func testNoMixedContentOnHttpPage() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "http://example.com/resource",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: false,  // Page is HTTP
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.isMixedContent == false)
    }

    @Test("No mixed content when resource is HTTPS")
    func testNoMixedContentForHttpsResource() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://cdn.example.com/script.js",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.isMixedContent == false)
        #expect(request.securityIcon == "lock.fill")
        #expect(request.securityIconColor == .green)
    }
}

// MARK: - NetworkRequest Content Type Tests

@Suite("NetworkRequest Content Type Detection")
struct NetworkRequestContentTypeTests {

    private func makeRequest(contentTypeHeader: String?, bodyPreview: String?) -> NetworkRequest {
        var headers: [String: String]?
        if let contentType = contentTypeHeader {
            headers = ["Content-Type": contentType]
        }

        return NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: headers,
            responseBodyPreview: bodyPreview,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )
    }

    @Test("Detects JSON from Content-Type header")
    func testJsonFromHeader() {
        let request = makeRequest(contentTypeHeader: "application/json", bodyPreview: nil)
        #expect(request.responseContentType == "JSON")
    }

    @Test("Detects HTML from Content-Type header")
    func testHtmlFromHeader() {
        let request = makeRequest(contentTypeHeader: "text/html; charset=utf-8", bodyPreview: nil)
        #expect(request.responseContentType == "HTML")
    }

    @Test("Detects XML from Content-Type header")
    func testXmlFromHeader() {
        let request1 = makeRequest(contentTypeHeader: "text/xml", bodyPreview: nil)
        let request2 = makeRequest(contentTypeHeader: "application/xml", bodyPreview: nil)

        #expect(request1.responseContentType == "XML")
        #expect(request2.responseContentType == "XML")
    }

    @Test("Detects JavaScript from Content-Type header")
    func testJsFromHeader() {
        let request = makeRequest(contentTypeHeader: "application/javascript", bodyPreview: nil)
        #expect(request.responseContentType == "JS")
    }

    @Test("Detects JSON from body content")
    func testJsonFromBody() {
        let request1 = makeRequest(contentTypeHeader: nil, bodyPreview: "{\"key\": \"value\"}")
        let request2 = makeRequest(contentTypeHeader: nil, bodyPreview: "[1, 2, 3]")

        #expect(request1.responseContentType == "JSON")
        #expect(request2.responseContentType == "JSON")
    }

    @Test("Detects HTML from body content")
    func testHtmlFromBody() {
        let request1 = makeRequest(contentTypeHeader: nil, bodyPreview: "<!DOCTYPE html><html>")
        let request2 = makeRequest(contentTypeHeader: nil, bodyPreview: "<html lang=\"en\">")

        #expect(request1.responseContentType == "HTML")
        #expect(request2.responseContentType == "HTML")
    }

    @Test("Detects XML from body content")
    func testXmlFromBody() {
        let request = makeRequest(contentTypeHeader: nil, bodyPreview: "<?xml version=\"1.0\"?>")
        #expect(request.responseContentType == "XML")
    }

    @Test("Returns Text for plain text")
    func testPlainText() {
        let request = makeRequest(contentTypeHeader: nil, bodyPreview: "Hello, World!")
        #expect(request.responseContentType == "Text")
    }

    @Test("Returns dash for empty body")
    func testEmptyBody() {
        let request = makeRequest(contentTypeHeader: nil, bodyPreview: nil)
        #expect(request.responseContentType == "—")
    }
}

// MARK: - NetworkRequest URL Parsing Tests

@Suite("NetworkRequest URL Parsing")
struct NetworkRequestURLParsingTests {

    @Test("Extracts host from URL")
    func testHostExtraction() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://api.example.com/v1/users",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.host == "api.example.com")
    }

    @Test("Extracts path from URL")
    func testPathExtraction() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com/api/v1/users",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.path == "/api/v1/users")
    }

    @Test("Returns root path for URL without path")
    func testRootPath() {
        let request = NetworkRequest(
            id: UUID(),
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: Date(),
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: Date(),
            error: nil,
            requestType: .fetch
        )

        #expect(request.path == "/")
    }
}

// MARK: - NetworkRequest Equatable Tests

@MainActor
@Suite("NetworkRequest Equatable")
struct NetworkRequestEquatableTests {

    @Test("Same request is equal")
    func testSameRequestEqual() {
        let id = UUID()
        let date = Date()

        let request1 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: date,
            error: nil,
            requestType: .fetch
        )

        let request2 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: date,
            error: nil,
            requestType: .fetch
        )

        #expect(request1 == request2)
    }

    @Test("Different status means not equal")
    func testDifferentStatusNotEqual() {
        let id = UUID()
        let date = Date()

        let request1 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: date,
            error: nil,
            requestType: .fetch
        )

        let request2 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: 404,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: date,
            error: nil,
            requestType: .fetch
        )

        #expect(request1 != request2)
    }

    @Test("Different endTime means not equal")
    func testDifferentEndTimeNotEqual() {
        let id = UUID()
        let date = Date()

        let request1 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: date,
            error: nil,
            requestType: .fetch
        )

        let request2 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: 200,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: date.addingTimeInterval(1),
            error: nil,
            requestType: .fetch
        )

        #expect(request1 != request2)
    }

    @Test("Different error means not equal")
    func testDifferentErrorNotEqual() {
        let id = UUID()
        let date = Date()

        let request1 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: nil,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: nil,
            error: nil,
            requestType: .fetch
        )

        let request2 = NetworkRequest(
            id: id,
            method: "GET",
            url: "https://example.com",
            requestHeaders: nil,
            requestBodyPreview: nil,
            startTime: date,
            pageIsSecure: true,
            status: nil,
            statusText: nil,
            responseHeaders: nil,
            responseBodyPreview: nil,
            endTime: nil,
            error: "Network error",
            requestType: .fetch
        )

        #expect(request1 != request2)
    }
}

// MARK: - NetworkRequest RequestType Tests

@Suite("NetworkRequest RequestType")
struct NetworkRequestTypeTests {

    @Test("Fetch type has correct properties")
    func testFetchType() {
        let type = NetworkRequest.RequestType.fetch
        #expect(type.label == "Fetch")
        #expect(type.icon == "arrow.down.doc")
    }

    @Test("XHR type has correct properties")
    func testXhrType() {
        let type = NetworkRequest.RequestType.xhr
        #expect(type.label == "XHR")
        #expect(type.icon == "arrow.triangle.2.circlepath")
    }

    @Test("Document type has correct properties")
    func testDocumentType() {
        let type = NetworkRequest.RequestType.document
        #expect(type.label == "Doc")
        #expect(type.icon == "doc.text")
    }

    @Test("Other type has correct properties")
    func testOtherType() {
        let type = NetworkRequest.RequestType.other
        #expect(type.label == "Other")
        #expect(type.icon == "questionmark.circle")
    }
}
