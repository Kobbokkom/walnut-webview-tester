//
//  AdManagerTests.swift
//  winaTests
//
//  Tests for AdManager and AdOptions.
//

import GoogleMobileAds
import XCTest
@testable import wina

// MARK: - AdOptions Tests

final class AdOptionsTests: XCTestCase {

    func testDefaultProbability() {
        let options = AdOptions(id: "test")
        XCTAssertEqual(options.probability, 0.3)
    }

    func testCustomProbability() {
        let options = AdOptions(id: "test", probability: 0.5)
        XCTAssertEqual(options.probability, 0.5)
    }

    func testProbabilityClampedToMin() {
        let options = AdOptions(id: "test", probability: -0.5)
        XCTAssertEqual(options.probability, 0.0)
    }

    func testProbabilityClampedToMax() {
        let options = AdOptions(id: "test", probability: 1.5)
        XCTAssertEqual(options.probability, 1.0)
    }

    func testProbabilityAtBoundaries() {
        let zeroOptions = AdOptions(id: "test", probability: 0.0)
        XCTAssertEqual(zeroOptions.probability, 0.0)

        let oneOptions = AdOptions(id: "test", probability: 1.0)
        XCTAssertEqual(oneOptions.probability, 1.0)
    }

    func testIdIsPreserved() {
        let options = AdOptions(id: "unique_feature_id")
        XCTAssertEqual(options.id, "unique_feature_id")
    }
}

// MARK: - AdManager Tests

@MainActor
final class AdManagerTests: XCTestCase {

    var manager: AdManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = AdManager.shared
        manager.resetAllShownStates()
    }

    override func tearDown() async throws {
        manager.resetAllShownStates()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSharedInstanceExists() {
        XCTAssertNotNil(AdManager.shared)
    }

    func testSharedInstanceIsSingleton() {
        let manager1 = AdManager.shared
        let manager2 = AdManager.shared
        XCTAssertTrue(manager1 === manager2)
    }

    // MARK: - Ad Unit ID Tests

    func testInterstitialAdUnitIdIsValid() {
        #if DEBUG
        XCTAssertEqual(AdManager.interstitialAdUnitId, "ca-app-pub-3940256099942544/4411468910")
        #else
        XCTAssertEqual(AdManager.interstitialAdUnitId, "ca-app-pub-6737616702687889/5962304852")
        #endif
    }

    func testBannerAdUnitIdIsValid() {
        #if DEBUG
        XCTAssertEqual(AdManager.bannerAdUnitId, "ca-app-pub-3940256099942544/2435281174")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
                       "ca-app-pub-3940256099942544~1458002511")
        #else
        XCTAssertEqual(AdManager.bannerAdUnitId, "ca-app-pub-6737616702687889/6596869296")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
                       "ca-app-pub-6737616702687889~9215154150")
        #endif
    }

    func testBannerRequestsOncePerVisibleSettledSize() async throws {
        let coordinator = BannerAdView.BannerCoordinator()
        var sizes: [CGSize] = []
        let record: (AdSize) -> Void = { sizes.append($0.size) }
        coordinator.scheduleLoad(for: AdSizeBanner, load: record)
        coordinator.scheduleLoad(for: nil, load: record)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(sizes.isEmpty)

        coordinator.scheduleLoad(for: AdSizeLargeBanner, load: record)
        coordinator.scheduleLoad(for: AdSizeBanner, load: record)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(sizes, [AdSizeBanner.size])

        coordinator.scheduleLoad(for: nil, load: record)
        coordinator.scheduleLoad(for: AdSizeBanner, load: record)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(sizes, [AdSizeBanner.size])

        coordinator.scheduleLoad(for: AdSizeLargeBanner, load: record)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(sizes, [AdSizeBanner.size, AdSizeLargeBanner.size])
    }

    // MARK: - shownAdIds Tracking Tests

    func testHasShownAdReturnsFalseInitially() {
        XCTAssertFalse(manager.hasShownAd(for: "test_id"))
    }

    func testResetShownStateForSpecificId() {
        // We can't directly set shownAdIds, but we can test the reset methods
        // First test that hasShownAd returns false for a new id
        let testId = "reset_test_id"
        XCTAssertFalse(manager.hasShownAd(for: testId))

        // Reset should not crash even if id wasn't shown
        manager.resetShownState(for: testId)
        XCTAssertFalse(manager.hasShownAd(for: testId))
    }

    func testResetAllShownStates() {
        // Test that reset doesn't crash
        manager.resetAllShownStates()

        // After reset, all should return false
        XCTAssertFalse(manager.hasShownAd(for: "id1"))
        XCTAssertFalse(manager.hasShownAd(for: "id2"))
        XCTAssertFalse(manager.hasShownAd(for: "id3"))
    }

    func testMultipleIdsTrackedIndependently() {
        // Each id should be tracked independently
        let id1 = "feature_1"
        let id2 = "feature_2"

        // Both should be initially false
        XCTAssertFalse(manager.hasShownAd(for: id1))
        XCTAssertFalse(manager.hasShownAd(for: id2))

        // Reset one should not affect the other
        manager.resetShownState(for: id1)
        XCTAssertFalse(manager.hasShownAd(for: id1))
        XCTAssertFalse(manager.hasShownAd(for: id2))
    }
}
