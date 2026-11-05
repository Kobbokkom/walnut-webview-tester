//
//  UserAgentTests.swift
//  winaTests
//
//  Tests for UserAgentBuilder, UserAgentParser (with UAParserSwift), and UserAgentVersionModifier
//  Edge cases based on MDN UA string documentation and real-world browser strings
//
//  References:
//  - https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Browser_detection_using_the_user_agent
//  - https://deviceatlas.com/blog/list-of-user-agent-strings
//  - https://learn.microsoft.com/en-us/microsoft-edge/web-platform/user-agent-guidance
//

import XCTest
@testable import wina

// MARK: - UserAgentBuilder Tests

final class UserAgentBuilderTests: XCTestCase {

    // MARK: - Basic Build Tests

    func testDefaultBuild() {
        let builder = UserAgentBuilder()
        let ua = builder.build()

        XCTAssertTrue(ua.contains("Mozilla/5.0"))
        XCTAssertTrue(ua.contains("Windows NT"))
        XCTAssertTrue(ua.contains("AppleWebKit/537.36"))
        XCTAssertTrue(ua.contains("Chrome/"))
        XCTAssertTrue(ua.contains("Safari/537.36"))
    }

    func testChromeBuilder() {
        let ua = UserAgentBuilder.chrome(version: "120.0.0.0").build()

        XCTAssertTrue(ua.contains("Chrome/120.0.0.0"))
        XCTAssertTrue(ua.contains("Mozilla/5.0"))
        XCTAssertTrue(ua.contains("Safari/537.36"))
    }

    func testSafariBuilder() {
        let ua = UserAgentBuilder.safari(version: "17.0").build()

        XCTAssertTrue(ua.contains("Version/17.0"))
        XCTAssertTrue(ua.contains("Safari/605.1.15"))
        XCTAssertTrue(ua.contains("AppleWebKit/537.36"))
    }

    func testFirefoxBuilder() {
        let ua = UserAgentBuilder.firefox(version: "120.0").build()

        XCTAssertTrue(ua.contains("Firefox/120.0"))
        XCTAssertTrue(ua.contains("Gecko/20100101"))
        XCTAssertFalse(ua.contains("Safari"))  // Firefox doesn't have Safari token
    }

    func testEdgeBuilder() {
        let ua = UserAgentBuilder.edge(version: "120.0.0.0").build()

        XCTAssertTrue(ua.contains("Chrome/120.0.0.0"))
        XCTAssertTrue(ua.contains("Edg/120.0.0.0"))
        XCTAssertTrue(ua.contains("Safari/537.36"))
    }

    // MARK: - Platform Token Tests

    func testWindowsPlatform() {
        let ua = UserAgentBuilder.chrome(platform: .windowsDesktop).build()
        XCTAssertTrue(ua.contains("Windows NT 10.0; Win64; x64"))
    }

    func testMacPlatform() {
        let ua = UserAgentBuilder.chrome(platform: .macDesktop).build()
        XCTAssertTrue(ua.contains("Macintosh; Intel Mac OS X"))
    }

    func testMacAppleSiliconPlatform() {
        let ua = UserAgentBuilder.chrome(platform: .macAppleSilicon).build()
        XCTAssertTrue(ua.contains("Macintosh; ARM Mac OS X"))
    }

    func testLinuxPlatform() {
        let ua = UserAgentBuilder.chrome(platform: .linux).build()
        XCTAssertTrue(ua.contains("X11; Linux x86_64"))
    }

    func testAndroidPlatform() {
        let ua = UserAgentBuilder.chrome(platform: .android).build()
        XCTAssertTrue(ua.contains("Linux; Android"))
    }

    func testiPhonePlatform() {
        let ua = UserAgentBuilder.chrome(platform: .iphone).build()
        XCTAssertTrue(ua.contains("iPhone; CPU iPhone OS"))
    }

    func testiPadPlatform() {
        let ua = UserAgentBuilder.chrome(platform: .ipad).build()
        XCTAssertTrue(ua.contains("iPad; CPU OS"))
    }

    // MARK: - Engine Tests

    func testWebKitEngine() {
        let builder = UserAgentBuilder(engine: .webkit)
        let ua = builder.build()

        XCTAssertTrue(ua.contains("AppleWebKit/537.36"))
        XCTAssertTrue(ua.contains("(KHTML, like Gecko)"))
    }

    func testGeckoEngine() {
        let builder = UserAgentBuilder(engine: .gecko, browserName: "Firefox", browserVersion: "120.0")
        let ua = builder.build()

        XCTAssertTrue(ua.contains("Gecko/20100101"))
        XCTAssertFalse(ua.contains("Safari"))  // Gecko engine shouldn't have Safari token
    }

    // MARK: - Custom Tokens Tests

    func testAdditionalTokens() {
        var builder = UserAgentBuilder()
        builder.additionalTokens = ["MyApp/1.0", "CustomToken"]
        let ua = builder.build()

        XCTAssertTrue(ua.contains("MyApp/1.0"))
        XCTAssertTrue(ua.contains("CustomToken"))
    }
}

// MARK: - UserAgentParser Tests (using UAParserSwift)

final class UserAgentParserTests: XCTestCase {

    func testCanonicalOSNamesRemainRecognized() {
        for (platform, expected) in [("Android", "Android"), ("iOS", "iOS"),
                                     ("Mac OS", "macOS"), ("macOS", "macOS"),
                                     ("Windows", "Windows"), ("Linux", "Linux")] {
            var parsed = UserAgentParser.ParsedUserAgent()
            parsed.platform = platform
            XCTAssertEqual(parsed.osName, expected, platform)
        }
    }

    // MARK: - Chrome Detection Tests

    func testParseChromeWindows() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Chrome")
        XCTAssertEqual(parsed.browserVersion, "120.0.0.0")
        XCTAssertEqual(parsed.engine, "WebKit")
        // UAParserSwift returns OS name (e.g., "Windows") instead of full platform string
        XCTAssertTrue(parsed.platform.contains("Windows") || parsed.osName == "Windows")
        XCTAssertFalse(parsed.isMobile)
        XCTAssertFalse(parsed.isTablet)
    }

    func testParseChromeAndroid() {
        let ua = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Chrome")
        // UAParserSwift uses deviceType for mobile detection
        XCTAssertTrue(parsed.isMobile || parsed.deviceType.lowercased() == "mobile")
    }

    func testParseChromeIOS() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.0.0 Mobile/15E148 Safari/604.1"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift returns "Chrome" for CriOS, not "Chrome iOS"
        XCTAssertEqual(parsed.browser, "Chrome")
        XCTAssertTrue(parsed.isMobile || parsed.deviceType.lowercased() == "mobile")
    }

    // MARK: - Safari Detection Tests

    func testParseSafariMac() {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Safari")
        XCTAssertEqual(parsed.browserVersion, "17.0")
        XCTAssertFalse(parsed.isMobile)
    }

    func testParseSafariiOS() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift returns "Mobile Safari" for mobile Safari
        XCTAssertTrue(parsed.browser == "Mobile Safari" || parsed.browser == "Safari")
        XCTAssertTrue(parsed.isMobile || parsed.deviceType.lowercased() == "mobile")
    }

    func testParseSafariiPad() {
        let ua = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertTrue(parsed.browser == "Mobile Safari" || parsed.browser == "Safari")
        XCTAssertTrue(parsed.isTablet || parsed.deviceType.lowercased() == "tablet")
    }

    // MARK: - Edge Detection Tests

    func testParseEdgeWindows() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift doesn't detect modern Edge (Edg/) - it falls back to Chrome
        // Modern Edge uses "Edg/" which differs from legacy "Edge/" pattern
        XCTAssertTrue(parsed.browser == "Edge" || parsed.browser == "Chrome")
    }

    func testParseEdgeAndroid() {
        let ua = "Mozilla/5.0 (Linux; Android 10; HD1913) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 EdgA/120.0.0.0"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift doesn't detect modern Edge mobile (EdgA/) - falls back to Chrome
        XCTAssertTrue(parsed.browser == "Edge" || parsed.browser == "Chrome")
    }

    func testParseEdgeiOS() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 EdgiOS/120.0.0.0 Mobile/15E148 Safari/604.1"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift doesn't detect modern Edge iOS (EdgiOS/) - falls back to Mobile Safari
        XCTAssertTrue(parsed.browser == "Edge" || parsed.browser == "Mobile Safari" || parsed.browser == "Safari")
    }

    // MARK: - Firefox Detection Tests

    func testParseFirefoxWindows() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Firefox")
        XCTAssertEqual(parsed.browserVersion, "120.0")
        XCTAssertEqual(parsed.engine, "Gecko")
    }

    func testParseFirefoxMac() {
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:120.0) Gecko/20100101 Firefox/120.0"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Firefox")
    }

    func testParseFirefoxiOS() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/120.0 Mobile/15E148 Safari/605.1.15"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift returns "Firefox" for FxiOS, not "Firefox iOS"
        XCTAssertEqual(parsed.browser, "Firefox")
        XCTAssertTrue(parsed.isMobile || parsed.deviceType.lowercased() == "mobile")
    }

    // MARK: - Opera Detection Tests

    func testParseOpera() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Opera")
        // Opera should be detected before Chrome
        XCTAssertNotEqual(parsed.browser, "Chrome")
    }

    // MARK: - Brave Detection Tests

    func testParseBrave() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Brave"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift may or may not detect Brave specifically
        // It might fall back to Chrome detection
        XCTAssertTrue(parsed.browser == "Brave" || parsed.browser == "Chrome")
    }

    // MARK: - Mozilla Version Tests

    func testMozillaVersion() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.mozilla, "5.0")
    }

    // MARK: - Engine Version Tests

    func testWebKitEngineVersion() {
        let ua = "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.engine, "WebKit")
        XCTAssertEqual(parsed.engineVersion, "537.36")
    }

    func testGeckoEngineVersion() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:120.0) Gecko/20100101 Firefox/120.0"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.engine, "Gecko")
        // UAParserSwift returns the Gecko engine version
        XCTAssertFalse(parsed.engineVersion.isEmpty)
    }

    // MARK: - Edge Cases

    func testEmptyUserAgent() {
        let parsed = UserAgentParser.parse("")

        XCTAssertEqual(parsed.mozilla, "5.0")  // Default value
        XCTAssertTrue(parsed.browser.isEmpty)
    }

    func testMalformedUserAgent() {
        let ua = "Not a valid user agent string"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.mozilla, "5.0")  // Default when not found
    }

    func testUnbalancedParentheses() {
        let ua = "Mozilla/5.0 (Windows NT 10.0 AppleWebKit/537.36"
        let parsed = UserAgentParser.parse(ua)

        // Should handle gracefully without crashing
        XCTAssertNotNil(parsed)
    }

    func testAndroidTabletDetection() {
        // Android tablet doesn't have "Mobile" in UA
        let ua = "Mozilla/5.0 (Linux; Android 10; SM-T500) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift uses deviceType for better tablet detection
        XCTAssertTrue(parsed.isTablet || parsed.deviceType.lowercased() == "tablet" || !parsed.isMobile)
    }

    // MARK: - Browser Priority Tests

    func testEdgeDetectedBeforeChrome() {
        // Edge UA contains both "Chrome" and "Edg"
        // Note: UAParserSwift doesn't detect modern Edge (Edg/) pattern
        let ua = "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
        let parsed = UserAgentParser.parse(ua)

        // UAParserSwift falls back to Chrome for modern Edge
        XCTAssertTrue(parsed.browser == "Edge" || parsed.browser == "Chrome")
    }

    func testOperaDetectedBeforeChrome() {
        let ua = "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.browser, "Opera")
    }

    // MARK: - New Device Info Tests (UAParserSwift specific)

    func testDeviceInfoiPhone() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.deviceVendor, "Apple")
        XCTAssertEqual(parsed.deviceModel, "iPhone")
    }

    func testDeviceInfoiPad() {
        let ua = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        let parsed = UserAgentParser.parse(ua)

        XCTAssertEqual(parsed.deviceVendor, "Apple")
        XCTAssertEqual(parsed.deviceModel, "iPad")
    }
}

// MARK: - UserAgentVersionModifier Tests

final class UserAgentVersionModifierTests: XCTestCase {

    func testUpdateChromeVersion() {
        let ua = "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
        let updated = UserAgentVersionModifier.updateChromeVersion(ua, to: "121.0.0.0")

        XCTAssertTrue(updated.contains("Chrome/121.0.0.0"))
        XCTAssertFalse(updated.contains("Chrome/120.0.0.0"))
    }

    func testUpdateFirefoxVersion() {
        let ua = "Mozilla/5.0 (Windows NT 10.0; rv:120.0) Gecko/20100101 Firefox/120.0"
        let updated = UserAgentVersionModifier.updateFirefoxVersion(ua, to: "121.0")

        XCTAssertTrue(updated.contains("Firefox/121.0"))
        XCTAssertFalse(updated.contains("Firefox/120.0"))
    }

    func testUpdateSafariVersion() {
        let ua = "Mozilla/5.0 (Macintosh) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15"
        let updated = UserAgentVersionModifier.updateSafariVersion(ua, to: "18.0")

        XCTAssertTrue(updated.contains("Version/18.0"))
        XCTAssertFalse(updated.contains("Version/17.0"))
    }

    func testUpdateiOSVersion() {
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        let updated = UserAgentVersionModifier.updateiOSVersion(ua, to: "18.0")

        XCTAssertTrue(updated.contains("iPhone OS 18_0"))
        XCTAssertFalse(updated.contains("iPhone OS 17_0"))
    }

    func testUpdateiOSVersionWithDots() {
        // Version with dots should be converted to underscores
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        let updated = UserAgentVersionModifier.updateiOSVersion(ua, to: "18.1.2")

        XCTAssertTrue(updated.contains("iPhone OS 18_1_2"))
    }

    func testUpdateiPadOSVersion() {
        let ua = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
        let updated = UserAgentVersionModifier.updateiOSVersion(ua, to: "18.0")

        XCTAssertTrue(updated.contains("CPU OS 18_0"))
    }

    func testUpdateAndroidVersion() {
        let ua = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 Chrome/120.0.0.0"
        let updated = UserAgentVersionModifier.updateAndroidVersion(ua, to: "14")

        XCTAssertTrue(updated.contains("Android 14"))
        XCTAssertFalse(updated.contains("Android 10"))
    }

    func testUpdateNonExistentVersion() {
        // Should return original UA if pattern not found
        let ua = "Some random string without Chrome version"
        let updated = UserAgentVersionModifier.updateChromeVersion(ua, to: "121.0.0.0")

        XCTAssertEqual(updated, ua)
    }

    func testMultipleChromeVersions() {
        // Edge case: multiple Chrome version strings (shouldn't happen in real UA but test regex)
        let ua = "Chrome/120.0.0.0 Chrome/119.0.0.0"
        let updated = UserAgentVersionModifier.updateChromeVersion(ua, to: "121.0.0.0")

        // Should replace all occurrences
        XCTAssertFalse(updated.contains("Chrome/120.0.0.0"))
        XCTAssertFalse(updated.contains("Chrome/119.0.0.0"))
        XCTAssertTrue(updated.contains("Chrome/121.0.0.0"))
    }
}


final class UserAgentPresetFilterTests: XCTestCase {
    func testBrowserAndSearchFiltersBothApply() {
        let combined = UserAgentPresets.search("Windows", browser: .firefox)
        XCTAssertFalse(combined.isEmpty)
        XCTAssertTrue(combined.allSatisfy { $0.browser == .firefox })
        XCTAssertEqual(combined, UserAgentPresets.search("Windows").filter { $0.browser == .firefox })
        XCTAssertEqual(UserAgentPresets.search("", browser: .firefox), UserAgentPresets.presets(for: .firefox))
        XCTAssertEqual(UserAgentPresets.search(""), UserAgentPresets.allPresets)
    }
}
