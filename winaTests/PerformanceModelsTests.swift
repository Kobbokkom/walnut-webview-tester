//
//  PerformanceModelsTests.swift
//  winaTests
//
//  Tests for PerformanceModels: Web Vitals scoring and performance metrics
//

import XCTest
import JavaScriptCore
@testable import wina

// MARK: - Metric Thresholds Tests

final class MetricThresholdsTests: XCTestCase {

    // MARK: - Rating Tests

    func testRateLCPGood() {
        // LCP ≤ 2500ms is good
        XCTAssertEqual(
            MetricThresholds.rate(2500, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .good
        )
        XCTAssertEqual(
            MetricThresholds.rate(1000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .good
        )
    }

    func testRateLCPNeedsImprovement() {
        // 2500 < LCP < 4000 needs improvement
        XCTAssertEqual(
            MetricThresholds.rate(3000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .needsImprovement
        )
        XCTAssertEqual(
            MetricThresholds.rate(3999, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .needsImprovement
        )
    }

    func testRateLCPPoor() {
        // LCP ≥ 4000ms is poor
        XCTAssertEqual(
            MetricThresholds.rate(4000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .poor
        )
        XCTAssertEqual(
            MetricThresholds.rate(10000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .poor
        )
    }

    func testRateCLSGood() {
        // CLS ≤ 0.1 is good
        XCTAssertEqual(
            MetricThresholds.rate(0.05, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .good
        )
        XCTAssertEqual(
            MetricThresholds.rate(0.1, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .good
        )
    }

    func testRateCLSPoor() {
        // CLS > 0.25 is poor
        XCTAssertEqual(
            MetricThresholds.rate(0.3, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .poor
        )
    }

    func testRateNegativeValue() {
        // Negative values should return unknown
        XCTAssertEqual(
            MetricThresholds.rate(-1, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .unknown
        )
    }

    // MARK: - Score Tests

    func testScorePerfect() {
        // At or below good threshold = 100
        XCTAssertEqual(
            MetricThresholds.score(2500, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            100
        )
        XCTAssertEqual(
            MetricThresholds.score(1000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            100
        )
    }

    func testScoreZero() {
        // At or above poor threshold = 0
        XCTAssertEqual(
            MetricThresholds.score(4000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            0
        )
        XCTAssertEqual(
            MetricThresholds.score(10000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            0
        )
    }

    func testScoreIntermediate() {
        // 3250 is halfway between 2500 (good) and 4000 (poor) = 50
        XCTAssertEqual(
            MetricThresholds.score(3250, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            50
        )
    }

    func testScoreNegative() {
        // Negative values should return 0
        XCTAssertEqual(
            MetricThresholds.score(-100, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            0
        )
    }

    func testScoreHigherIsBetter() {
        // Test isLowerBetter = false (not used in current code, but testing for correctness)
        XCTAssertEqual(
            MetricThresholds.score(100, good: 100, poor: 0, isLowerBetter: false),
            100
        )
        XCTAssertEqual(
            MetricThresholds.score(0, good: 100, poor: 0, isLowerBetter: false),
            0
        )
        XCTAssertEqual(
            MetricThresholds.score(50, good: 100, poor: 0, isLowerBetter: false),
            50
        )
    }
}

// MARK: - Metric Thresholds Boundary Tests

final class MetricThresholdsBoundaryTests: XCTestCase {

    // MARK: - LCP Boundaries (good: 2500, poor: 4000)

    func testLCPJustBelowGoodThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(2499, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .good
        )
    }

    func testLCPExactlyAtGoodThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(2500, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .good
        )
    }

    func testLCPJustAboveGoodThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(2501, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .needsImprovement
        )
    }

    func testLCPJustBelowPoorThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(3999, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .needsImprovement
        )
    }

    func testLCPExactlyAtPoorThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(4000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .poor
        )
    }

    func testLCPJustAbovePoorThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(4001, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .poor
        )
    }

    // MARK: - CLS Boundaries (good: 0.1, poor: 0.25)

    func testCLSJustBelowGoodThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(0.09, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .good
        )
    }

    func testCLSExactlyAtGoodThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(0.1, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .good
        )
    }

    func testCLSJustAboveGoodThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(0.11, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .needsImprovement
        )
    }

    func testCLSJustBelowPoorThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(0.24, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .needsImprovement
        )
    }

    func testCLSExactlyAtPoorThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(0.25, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .poor
        )
    }

    func testCLSJustAbovePoorThreshold() {
        XCTAssertEqual(
            MetricThresholds.rate(0.26, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .poor
        )
    }

    // MARK: - Score Boundaries

    func testScoreAtExactGoodThreshold() {
        // Exactly at good threshold = 100
        XCTAssertEqual(
            MetricThresholds.score(2500, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            100
        )
    }

    func testScoreJustAboveGoodThreshold() {
        // Just above good threshold = less than 100
        let score = MetricThresholds.score(2501, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor)
        XCTAssertLessThan(score, 100)
        XCTAssertGreaterThan(score, 0)
    }

    func testScoreAtExactPoorThreshold() {
        // Exactly at poor threshold = 0
        XCTAssertEqual(
            MetricThresholds.score(4000, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            0
        )
    }

    func testScoreJustBelowPoorThreshold() {
        // 3900 is below poor threshold (4000), gives score = Int((4000-3900)/1500*100) = 6
        let score = MetricThresholds.score(3900, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor)
        XCTAssertGreaterThan(score, 0)
        XCTAssertLessThan(score, 100)
    }

    // MARK: - Edge Cases

    func testZeroValue() {
        XCTAssertEqual(
            MetricThresholds.rate(0, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .good
        )
        XCTAssertEqual(
            MetricThresholds.score(0, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            100
        )
    }

    func testVerySmallNegative() {
        XCTAssertEqual(
            MetricThresholds.rate(-0.001, good: MetricThresholds.clsGood, poor: MetricThresholds.clsPoor),
            .unknown
        )
    }

    func testVeryLargeValue() {
        XCTAssertEqual(
            MetricThresholds.rate(Double.greatestFiniteMagnitude, good: MetricThresholds.lcpGood, poor: MetricThresholds.lcpPoor),
            .poor
        )
    }
}

// MARK: - Resource Type Tests

final class ResourceTypeTests: XCTestCase {

    func testFromInitiatorTypeNavigation() {
        XCTAssertEqual(ResourceType.from(initiatorType: "navigation", name: ""), .document)
    }

    func testFromInitiatorTypeScript() {
        XCTAssertEqual(ResourceType.from(initiatorType: "script", name: ""), .script)
    }

    func testFromInitiatorTypeLink() {
        XCTAssertEqual(ResourceType.from(initiatorType: "link", name: ""), .stylesheet)
        XCTAssertEqual(ResourceType.from(initiatorType: "css", name: ""), .stylesheet)
    }

    func testFromInitiatorTypeImage() {
        XCTAssertEqual(ResourceType.from(initiatorType: "img", name: ""), .image)
        XCTAssertEqual(ResourceType.from(initiatorType: "image", name: ""), .image)
    }

    func testFromInitiatorTypeFetch() {
        XCTAssertEqual(ResourceType.from(initiatorType: "fetch", name: ""), .fetch)
        XCTAssertEqual(ResourceType.from(initiatorType: "xmlhttprequest", name: ""), .fetch)
    }

    func testFromInitiatorTypeFont() {
        XCTAssertEqual(ResourceType.from(initiatorType: "font", name: ""), .font)
    }

    func testFallbackToExtensionJS() {
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "script.js"), .script)
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "module.mjs"), .script)
    }

    func testFallbackToExtensionCSS() {
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "styles.css"), .stylesheet)
    }

    func testFallbackToExtensionImage() {
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "image.png"), .image)
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "photo.jpg"), .image)
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "icon.svg"), .image)
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "animation.webp"), .image)
    }

    func testFallbackToExtensionFont() {
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "font.woff"), .font)
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "font.woff2"), .font)
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "font.ttf"), .font)
    }

    func testFallbackToOther() {
        XCTAssertEqual(ResourceType.from(initiatorType: "other", name: "unknown.xyz"), .other)
        XCTAssertEqual(ResourceType.from(initiatorType: "unknown", name: "file.dat"), .other)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(ResourceType.from(initiatorType: "SCRIPT", name: ""), .script)
        XCTAssertEqual(ResourceType.from(initiatorType: "Image", name: ""), .image)
    }
}

// MARK: - Navigation Timing Tests

final class NavigationTimingTests: XCTestCase {

    func testTTFBCalculation() {
        let timing = NavigationTiming(
            startTime: 0,
            redirectTime: 10,
            dnsTime: 20,
            tcpTime: 30,
            tlsTime: 15,
            requestTime: 100,
            responseTime: 50,
            domProcessingTime: 200,
            domContentLoadedTime: 500,
            loadEventTime: 1000,
            timeToFirstByte: 120
        )

        XCTAssertEqual(timing.ttfb, 120)
    }

    func testConnectionTimeCalculation() {
        let timing = NavigationTiming(
            startTime: 0,
            redirectTime: 0,
            dnsTime: 0,
            tcpTime: 30,
            tlsTime: 15,
            requestTime: 0,
            responseTime: 0,
            domProcessingTime: 0,
            domContentLoadedTime: 0,
            loadEventTime: 0
        )

        XCTAssertEqual(timing.connectionTime, 45)  // tcpTime + tlsTime
    }
}

// MARK: - Resource Timing Tests

final class ResourceTimingModelTests: XCTestCase {

    func testShortNameFromURL() {
        let resource = ResourceTiming(
            id: UUID(),
            name: "https://example.com/assets/script.js",
            initiatorType: "script",
            startTime: 0,
            duration: 100,
            transferSize: 1000,
            encodedBodySize: 900,
            decodedBodySize: 800
        )

        XCTAssertEqual(resource.shortName, "script.js")
    }

    func testShortNameFromHost() {
        // URL.lastPathComponent for "https://example.com/" is "/" (not empty)
        // So shortName returns "/" not "example.com"
        let resource = ResourceTiming(
            id: UUID(),
            name: "https://example.com/",
            initiatorType: "navigation",
            startTime: 0,
            duration: 100,
            transferSize: 1000,
            encodedBodySize: 900,
            decodedBodySize: 800
        )

        XCTAssertEqual(resource.shortName, "/")
    }

    func testDisplaySizePreference() {
        // Should prefer transferSize
        let resource1 = ResourceTiming(
            id: UUID(),
            name: "test",
            initiatorType: "script",
            startTime: 0,
            duration: 100,
            transferSize: 1000,
            encodedBodySize: 900,
            decodedBodySize: 800
        )
        XCTAssertEqual(resource1.displaySize, 1000)

        // Should fallback to encodedBodySize
        let resource2 = ResourceTiming(
            id: UUID(),
            name: "test",
            initiatorType: "script",
            startTime: 0,
            duration: 100,
            transferSize: 0,
            encodedBodySize: 900,
            decodedBodySize: 800
        )
        XCTAssertEqual(resource2.displaySize, 900)

        // Should fallback to decodedBodySize
        let resource3 = ResourceTiming(
            id: UUID(),
            name: "test",
            initiatorType: "script",
            startTime: 0,
            duration: 100,
            transferSize: 0,
            encodedBodySize: 0,
            decodedBodySize: 800
        )
        XCTAssertEqual(resource3.displaySize, 800)
    }
}

// MARK: - Performance Data Tests

final class PerformanceDataTests: XCTestCase {

    func testFirstContentfulPaint() {
        var data = PerformanceData()
        data.paints = [
            PaintTiming(name: "first-paint", startTime: 100),
            PaintTiming(name: "first-contentful-paint", startTime: 200)
        ]

        XCTAssertEqual(data.firstContentfulPaint, 200)
        XCTAssertEqual(data.firstPaint, 100)
    }

    func testLCPRating() {
        var data = PerformanceData()
        data.navigation = NavigationTiming(
            startTime: 0,
            redirectTime: 0,
            dnsTime: 0,
            tcpTime: 0,
            tlsTime: 0,
            requestTime: 0,
            responseTime: 0,
            domProcessingTime: 0,
            domContentLoadedTime: 0,
            loadEventTime: 2000  // Good LCP
        )

        data.largestContentfulPaint = 2000
        XCTAssertEqual(data.lcpRating, .good)
    }

    func testCLSRating() {
        var data = PerformanceData()
        data.cls = 0.05

        XCTAssertEqual(data.clsRating, .good)

        data.cls = 0.15
        XCTAssertEqual(data.clsRating, .needsImprovement)

        data.cls = 0.30
        XCTAssertEqual(data.clsRating, .poor)
    }

    func testCLSUnknown() {
        var data = PerformanceData()
        data.cls = -1  // Not measured

        XCTAssertEqual(data.clsRating, .unknown)
    }

    func testTotalResources() {
        var data = PerformanceData()
        data.resources = [
            ResourceTiming(id: UUID(), name: "a.js", initiatorType: "script", startTime: 0, duration: 0, transferSize: 1000, encodedBodySize: 0, decodedBodySize: 0),
            ResourceTiming(id: UUID(), name: "b.css", initiatorType: "link", startTime: 0, duration: 0, transferSize: 2000, encodedBodySize: 0, decodedBodySize: 0)
        ]

        XCTAssertEqual(data.totalResources, 2)
        XCTAssertEqual(data.totalTransferSize, 3000)
    }

    func testCoreWebVitalsPass() {
        var data = PerformanceData()

        // Good LCP (< 2500ms)
        data.navigation = NavigationTiming(
            startTime: 0,
            redirectTime: 0,
            dnsTime: 0,
            tcpTime: 0,
            tlsTime: 0,
            requestTime: 0,
            responseTime: 0,
            domProcessingTime: 0,
            domContentLoadedTime: 0,
            loadEventTime: 2000
        )

        data.largestContentfulPaint = 2000
        // Good CLS (< 0.1)
        data.cls = 0.05

        XCTAssertTrue(data.coreWebVitalsPass)
    }

    func testCoreWebVitalsFail() {
        var data = PerformanceData()

        // Poor LCP (> 4000ms)
        data.navigation = NavigationTiming(
            startTime: 0,
            redirectTime: 0,
            dnsTime: 0,
            tcpTime: 0,
            tlsTime: 0,
            requestTime: 0,
            responseTime: 0,
            domProcessingTime: 0,
            domContentLoadedTime: 0,
            loadEventTime: 5000
        )

        data.largestContentfulPaint = 5000
        data.cls = 0.05

        XCTAssertFalse(data.coreWebVitalsPass)
    }

    func testScoreRating() {
        var data = PerformanceData()

        XCTAssertEqual(data.scoreRating, .unknown)  // No data

        // Add good data
        data.navigation = NavigationTiming(
            startTime: 0,
            redirectTime: 0,
            dnsTime: 0,
            tcpTime: 0,
            tlsTime: 0,
            requestTime: 0,
            responseTime: 100,  // Good TTFB
            domProcessingTime: 0,
            domContentLoadedTime: 0,
            loadEventTime: 1500  // Good LCP
        )
        data.largestContentfulPaint = 1500
        data.navigation?.timeToFirstByte = 100
        data.cls = 0.05  // Good CLS
        data.paints = [PaintTiming(name: "first-contentful-paint", startTime: 1000)]  // Good FCP

        XCTAssertEqual(data.scoreRating, .good)
    }
}

// MARK: - Performance Rating Tests

final class PerformanceRatingTests: XCTestCase {

    func testRatingColors() {
        // Just ensure colors are defined (no crashes)
        XCTAssertNotNil(PerformanceRating.good.color)
        XCTAssertNotNil(PerformanceRating.needsImprovement.color)
        XCTAssertNotNil(PerformanceRating.poor.color)
        XCTAssertNotNil(PerformanceRating.unknown.color)
    }

    func testRatingIcons() {
        XCTAssertEqual(PerformanceRating.good.icon, "checkmark.circle.fill")
        XCTAssertEqual(PerformanceRating.needsImprovement.icon, "exclamationmark.circle.fill")
        XCTAssertEqual(PerformanceRating.poor.icon, "xmark.circle.fill")
        XCTAssertEqual(PerformanceRating.unknown.icon, "questionmark.circle")
    }

    func testRatingRawValues() {
        XCTAssertEqual(PerformanceRating.good.rawValue, "Good")
        XCTAssertEqual(PerformanceRating.needsImprovement.rawValue, "Needs Improvement")
        XCTAssertEqual(PerformanceRating.poor.rawValue, "Poor")
        XCTAssertEqual(PerformanceRating.unknown.rawValue, "N/A")
    }
}

final class PerformanceCollectionRegressionTests: XCTestCase {
    func testCollectedMeasurementsReachDisplayedValues() {
        let manager = PerformanceManager()
        manager.parseData(from: """
        {"navigation":{"startTime":0,"redirectTime":0,"dnsTime":100,"tcpTime":200,"tlsTime":100,
        "requestTime":100,"responseTime":5000,"domProcessingTime":100,"domContentLoadedTime":6500,
        "loadEventTime":7000,"timeToFirstByte":1200},"resources":[],"paints":[],"lcp":2100,"cls":0.05,"tbt":0}
        """)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(manager.data.largestContentfulPaint, 2100)
        XCTAssertEqual(manager.data.navigation?.ttfb, 1200)
        XCTAssertEqual(manager.data.lcpRating, .good)
    }

    func testCollectionUsesFirstByteTimestampBeforeBodyDownload() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var window = {__webVitals_lcp: 2100, __webVitals_cls: 0};
        var performance = {getEntriesByType: function(type) {
          return type === 'navigation' ? [{startTime: 50, responseStart: 1250, requestStart: 1150,
            responseEnd: 6250, redirectStart: 0, redirectEnd: 0, domainLookupStart: 50,
            domainLookupEnd: 150, connectStart: 150, connectEnd: 350, secureConnectionStart: 250,
            domComplete: 7000, domInteractive: 6500, domContentLoadedEventEnd: 7100, loadEventEnd: 7200}] : [];
        }};
        """)
        let json = try XCTUnwrap(context.evaluateScript(PerformanceManager.collectionScript)?.toString())
        XCTAssertNil(context.exception)
        let manager = PerformanceManager()
        manager.parseData(from: json)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(manager.data.navigation?.ttfb, 1200)
        XCTAssertEqual(manager.data.largestContentfulPaint, 2100)
        context.evaluateScript("window.__webVitals_lcp = -1")
        let unavailableJSON = try XCTUnwrap(context.evaluateScript(PerformanceManager.collectionScript)?.toString())
        manager.parseData(from: unavailableJSON)
        XCTAssertNil(manager.data.largestContentfulPaint)
        XCTAssertEqual(manager.data.lcpRating, .unknown)
    }

    func testUnavailableLCPIsNotReplacedByLoadCompletion() {
        let manager = PerformanceManager()
        manager.parseData(from: """
        {"navigation":null,"resources":[],"paints":[],"lcp":-1,"cls":-1,"tbt":-1}
        """)
        XCTAssertNil(manager.data.largestContentfulPaint)
        XCTAssertEqual(manager.data.lcpRating, .unknown)
    }
}
