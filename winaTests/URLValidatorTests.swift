//
//  URLValidatorTests.swift
//  winaTests
//
//  Tests for URLValidator: URL and IP address validation
//  Edge cases based on URL/IP standards and common pitfalls
//
//  References:
//  - https://www.guido-flohr.net/the-gory-details-of-url-validation/
//  - https://docs.pydantic.dev/2.0/usage/types/urls/
//

import XCTest
@testable import wina

// MARK: - URL Validation Tests

final class URLValidationTests: XCTestCase {

    // MARK: - Valid URL Tests

    func testValidURLWithHTTPS() {
        XCTAssertTrue(URLValidator.isValidURL("https://www.google.com"))
        XCTAssertTrue(URLValidator.isValidURL("https://example.com"))
        XCTAssertTrue(URLValidator.isValidURL("https://sub.domain.com"))
    }

    func testValidURLWithHTTP() {
        XCTAssertTrue(URLValidator.isValidURL("http://www.google.com"))
        XCTAssertTrue(URLValidator.isValidURL("http://example.com"))
    }

    func testValidURLWithoutScheme() {
        // Should auto-add https://
        XCTAssertTrue(URLValidator.isValidURL("www.google.com"))
        XCTAssertTrue(URLValidator.isValidURL("example.com"))
        XCTAssertTrue(URLValidator.isValidURL("naver.com"))
    }

    func testValidURLWithPath() {
        XCTAssertTrue(URLValidator.isValidURL("https://example.com/path"))
        XCTAssertTrue(URLValidator.isValidURL("https://example.com/path/to/page"))
        XCTAssertTrue(URLValidator.isValidURL("example.com/search"))
    }

    func testValidURLWithQueryString() {
        XCTAssertTrue(URLValidator.isValidURL("https://example.com?q=test"))
        XCTAssertTrue(URLValidator.isValidURL("https://example.com/search?q=hello&lang=en"))
    }

    func testValidURLWithFragment() {
        XCTAssertTrue(URLValidator.isValidURL("https://example.com#section"))
        XCTAssertTrue(URLValidator.isValidURL("https://example.com/page#anchor"))
    }

    func testValidURLWithPort() {
        XCTAssertTrue(URLValidator.isValidURL("https://example.com:8080"))
        XCTAssertTrue(URLValidator.isValidURL("http://localhost:3000"))
    }

    // MARK: - SafariVC URL Scheme Tests

    func testSafariSupportedSchemes() {
        XCTAssertTrue(URLValidator.isSupportedSafariURL("https://example.com"))
        XCTAssertTrue(URLValidator.isSupportedSafariURL("http://example.com"))
        XCTAssertTrue(URLValidator.isSupportedSafariURL("example.com"))
    }

    func testSafariSupportsBareHostsWithPorts() {
        XCTAssertTrue(URLValidator.isSupportedSafariURL("localhost:3000/path"))
        XCTAssertTrue(URLValidator.isSupportedSafariURL(" example.com:8080 "))
        XCTAssertTrue(URLValidator.isSupportedSafariURL("192.168.1.1:8080"))
    }

    func testSafariUnsupportedSchemes() {
        XCTAssertFalse(URLValidator.isSupportedSafariURL("about:blank"))
        XCTAssertFalse(URLValidator.isSupportedSafariURL("file:///path/to/file.html"))
        XCTAssertFalse(URLValidator.isSupportedSafariURL("myapp://deep-link"))
        XCTAssertFalse(URLValidator.isSupportedSafariURL("com.example://deep-link"))
        XCTAssertFalse(URLValidator.isSupportedSafariURL("about:123"))
    }

    // MARK: - Localhost Tests

    func testLocalhost() {
        XCTAssertTrue(URLValidator.isValidURL("localhost"))
        XCTAssertTrue(URLValidator.isValidURL("http://localhost"))
        XCTAssertTrue(URLValidator.isValidURL("https://localhost"))
    }

    func testLocalhostWithPort() {
        XCTAssertTrue(URLValidator.isValidURL("localhost:3000"))
        XCTAssertTrue(URLValidator.isValidURL("http://localhost:8080"))
        XCTAssertTrue(URLValidator.isValidURL("localhost:80/path"))
    }

    func testLocalhostWithPath() {
        XCTAssertTrue(URLValidator.isValidURL("localhost/api"))
        XCTAssertTrue(URLValidator.isValidURL("localhost/api/v1/users"))
    }

    // MARK: - IP Address URL Tests

    func testValidIPAddressURL() {
        XCTAssertTrue(URLValidator.isValidURL("192.168.1.1"))
        XCTAssertTrue(URLValidator.isValidURL("http://192.168.1.1"))
        XCTAssertTrue(URLValidator.isValidURL("https://10.0.0.1"))
    }

    func testIPAddressWithPort() {
        XCTAssertTrue(URLValidator.isValidURL("192.168.1.1:8080"))
        XCTAssertTrue(URLValidator.isValidURL("http://10.0.0.1:3000"))
    }

    func testIPAddressWithPath() {
        XCTAssertTrue(URLValidator.isValidURL("192.168.1.1/api"))
        XCTAssertTrue(URLValidator.isValidURL("http://10.0.0.1/path/to/resource"))
    }

    // MARK: - Invalid URL Tests

    func testEmptyString() {
        XCTAssertFalse(URLValidator.isValidURL(""))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(URLValidator.isValidURL("   "))
        XCTAssertFalse(URLValidator.isValidURL("\t\n"))
    }

    func testDomainWithoutTLD() {
        // Should fail - no TLD (not localhost, not IP)
        XCTAssertFalse(URLValidator.isValidURL("example"))
        XCTAssertFalse(URLValidator.isValidURL("www"))
        XCTAssertFalse(URLValidator.isValidURL("mysite"))
    }

    func testInvalidCharacters() {
        XCTAssertFalse(URLValidator.isValidURL("example .com"))  // Space in domain
        XCTAssertFalse(URLValidator.isValidURL("exam<ple.com"))  // Invalid char
    }

    func testMalformedURL() {
        XCTAssertFalse(URLValidator.isValidURL("://example.com"))  // Missing scheme
        XCTAssertFalse(URLValidator.isValidURL("http://"))  // No host
    }

    // MARK: - Whitespace Handling Tests

    func testTrimsWhitespace() {
        XCTAssertTrue(URLValidator.isValidURL("  google.com  "))
        XCTAssertTrue(URLValidator.isValidURL("\nhttps://example.com\n"))
        XCTAssertTrue(URLValidator.isValidURL("\t localhost \t"))
    }

    // MARK: - Case Sensitivity Tests

    func testSchemeCaseInsensitive() {
        XCTAssertTrue(URLValidator.isValidURL("HTTP://example.com"))
        XCTAssertTrue(URLValidator.isValidURL("HTTPS://example.com"))
        XCTAssertTrue(URLValidator.isValidURL("HtTpS://example.com"))
    }

    func testDomainCaseInsensitive() {
        XCTAssertTrue(URLValidator.isValidURL("GOOGLE.COM"))
        XCTAssertTrue(URLValidator.isValidURL("Example.Com"))
    }

    // MARK: - Special TLD Tests

    func testVariousTLDs() {
        XCTAssertTrue(URLValidator.isValidURL("example.io"))
        XCTAssertTrue(URLValidator.isValidURL("example.co.kr"))
        XCTAssertTrue(URLValidator.isValidURL("example.org"))
        XCTAssertTrue(URLValidator.isValidURL("example.net"))
        XCTAssertTrue(URLValidator.isValidURL("example.dev"))
    }

    func testCountryCodeTLDs() {
        XCTAssertTrue(URLValidator.isValidURL("naver.com"))
        XCTAssertTrue(URLValidator.isValidURL("example.co.uk"))
        XCTAssertTrue(URLValidator.isValidURL("example.com.au"))
    }
}

// MARK: - IPv4 Validation Tests

final class IPv4ValidationTests: XCTestCase {

    // MARK: - Valid IPv4 Tests

    func testValidIPv4Standard() {
        XCTAssertTrue(URLValidator.isValidIPv4Address("192.168.1.1"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("10.0.0.1"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("172.16.0.1"))
    }

    func testValidIPv4BoundaryValues() {
        XCTAssertTrue(URLValidator.isValidIPv4Address("0.0.0.0"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("255.255.255.255"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("1.1.1.1"))
    }

    func testValidIPv4LoopbackAndBroadcast() {
        XCTAssertTrue(URLValidator.isValidIPv4Address("127.0.0.1"))  // Loopback
        XCTAssertTrue(URLValidator.isValidIPv4Address("255.255.255.255"))  // Broadcast
    }

    func testValidIPv4PrivateRanges() {
        // Class A private
        XCTAssertTrue(URLValidator.isValidIPv4Address("10.0.0.0"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("10.255.255.255"))

        // Class B private
        XCTAssertTrue(URLValidator.isValidIPv4Address("172.16.0.0"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("172.31.255.255"))

        // Class C private
        XCTAssertTrue(URLValidator.isValidIPv4Address("192.168.0.0"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("192.168.255.255"))
    }

    // MARK: - Invalid IPv4 Tests

    func testInvalidIPv4OutOfRange() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("256.0.0.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.1.256"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("999.999.999.999"))
    }

    func testInvalidIPv4NegativeNumbers() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("-1.0.0.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.-1.1.1"))
    }

    func testInvalidIPv4WrongOctetCount() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.1"))  // 3 octets
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.1.1.1"))  // 5 octets
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168"))  // 2 octets
    }

    func testInvalidIPv4EmptyOctets() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("192..1.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address(".168.1.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.1."))
    }

    func testInvalidIPv4LeadingZeros() {
        // Leading zeros should be rejected (octal interpretation issue)
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.01.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.001.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("01.02.03.04"))
    }

    func testInvalidIPv4NonNumeric() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.a.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("abc.def.ghi.jkl"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.1.1a"))
    }

    func testInvalidIPv4WithSpaces() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("192. 168.1.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address(" 192.168.1.1"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("192.168.1.1 "))
    }

    func testEmptyString() {
        XCTAssertFalse(URLValidator.isValidIPv4Address(""))
    }

    func testNotAnIPAddress() {
        XCTAssertFalse(URLValidator.isValidIPv4Address("localhost"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("google.com"))
        XCTAssertFalse(URLValidator.isValidIPv4Address("not an ip"))
    }

    // MARK: - Edge Cases

    func testIPv4SingleDigitOctets() {
        XCTAssertTrue(URLValidator.isValidIPv4Address("1.2.3.4"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("0.0.0.1"))
    }

    func testIPv4DoubleDigitOctets() {
        XCTAssertTrue(URLValidator.isValidIPv4Address("10.20.30.40"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("99.99.99.99"))
    }

    func testIPv4TripleDigitOctets() {
        XCTAssertTrue(URLValidator.isValidIPv4Address("100.200.100.200"))
        XCTAssertTrue(URLValidator.isValidIPv4Address("255.100.50.25"))
    }
}

// MARK: - URL Normalization Tests

final class URLNormalizationTests: XCTestCase {

    func testNormalizeAddsHTTPS() {
        XCTAssertEqual(URLValidator.normalizeURL("google.com"), "https://google.com")
        XCTAssertEqual(URLValidator.normalizeURL("example.com/path"), "https://example.com/path")
    }

    func testNormalizePreservesExistingScheme() {
        XCTAssertEqual(URLValidator.normalizeURL("http://google.com"), "http://google.com")
        XCTAssertEqual(URLValidator.normalizeURL("https://google.com"), "https://google.com")
    }

    func testNormalizeCaseInsensitiveScheme() {
        XCTAssertEqual(URLValidator.normalizeURL("HTTP://google.com"), "HTTP://google.com")
        XCTAssertEqual(URLValidator.normalizeURL("HTTPS://google.com"), "HTTPS://google.com")
    }

    func testNormalizeTrimsWhitespace() {
        XCTAssertEqual(URLValidator.normalizeURL("  google.com  "), "https://google.com")
        XCTAssertEqual(URLValidator.normalizeURL("\nhttps://example.com\n"), "https://example.com")
    }
}

// MARK: - Host Extraction Tests

final class HostExtractionTests: XCTestCase {

    func testExtractHostFromURL() {
        XCTAssertEqual(URLValidator.extractHost("https://www.google.com"), "www.google.com")
        XCTAssertEqual(URLValidator.extractHost("https://example.com/path"), "example.com")
    }

    func testExtractHostWithoutScheme() {
        XCTAssertEqual(URLValidator.extractHost("google.com"), "google.com")
        XCTAssertEqual(URLValidator.extractHost("www.example.com/path"), "www.example.com")
    }

    func testExtractHostWithPort() {
        XCTAssertEqual(URLValidator.extractHost("localhost:3000"), "localhost")
        XCTAssertEqual(URLValidator.extractHost("https://example.com:8080"), "example.com")
    }

    func testExtractHostFromIPAddress() {
        XCTAssertEqual(URLValidator.extractHost("192.168.1.1"), "192.168.1.1")
        XCTAssertEqual(URLValidator.extractHost("http://10.0.0.1:8080"), "10.0.0.1")
    }

    func testExtractHostInvalidURL() {
        XCTAssertNil(URLValidator.extractHost(""))
        XCTAssertNil(URLValidator.extractHost("   "))
    }
}
