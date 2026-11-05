//
//  DeviceUtilitiesTests.swift
//  winaTests
//
//  Tests for DeviceUtilities: SettingsFormatter and ByteFormatter
//

import XCTest
import SwiftUI
import UIKit
@testable import wina

// MARK: - Settings Formatter Tests

final class SettingsFormatterTests: XCTestCase {

    // MARK: - Content Mode Tests

    func testContentModeTextMobile() {
        XCTAssertEqual(SettingsFormatter.contentModeText(1), "Mobile")
    }

    func testContentModeTextDesktop() {
        XCTAssertEqual(SettingsFormatter.contentModeText(2), "Desktop")
    }

    func testContentModeTextRecommended() {
        XCTAssertEqual(SettingsFormatter.contentModeText(0), "Recommended")
        XCTAssertEqual(SettingsFormatter.contentModeText(99), "Recommended")  // Unknown value
    }

    // MARK: - Data Detectors Tests

    func testActiveDataDetectorsNone() {
        let result = SettingsFormatter.activeDataDetectors(
            phone: false,
            links: false,
            address: false,
            calendar: false
        )
        XCTAssertEqual(result, "None")
    }

    func testActiveDataDetectorsSingle() {
        XCTAssertEqual(
            SettingsFormatter.activeDataDetectors(phone: true, links: false, address: false, calendar: false),
            "Phone"
        )
        XCTAssertEqual(
            SettingsFormatter.activeDataDetectors(phone: false, links: true, address: false, calendar: false),
            "Links"
        )
    }

    func testActiveDataDetectorsMultiple() {
        let result = SettingsFormatter.activeDataDetectors(
            phone: true,
            links: true,
            address: false,
            calendar: false
        )
        XCTAssertEqual(result, "Phone, Links")
    }

    func testActiveDataDetectorsAll() {
        let result = SettingsFormatter.activeDataDetectors(
            phone: true,
            links: true,
            address: true,
            calendar: true
        )
        XCTAssertEqual(result, "Phone, Links, Address, Calendar")
    }

    // MARK: - Enabled Status Tests

    func testEnabledStatusTrue() {
        XCTAssertEqual(SettingsFormatter.enabledStatus(true), "Enabled")
    }

    func testEnabledStatusFalse() {
        XCTAssertEqual(SettingsFormatter.enabledStatus(false), "Disabled")
    }

    // MARK: - Dismiss Button Style Tests

    func testDismissButtonStyleClose() {
        XCTAssertEqual(SettingsFormatter.dismissButtonStyleText(1), "Close")
    }

    func testDismissButtonStyleCancel() {
        XCTAssertEqual(SettingsFormatter.dismissButtonStyleText(2), "Cancel")
    }

    func testDismissButtonStyleDone() {
        XCTAssertEqual(SettingsFormatter.dismissButtonStyleText(0), "Done")
        XCTAssertEqual(SettingsFormatter.dismissButtonStyleText(99), "Done")  // Unknown value
    }
}

// MARK: - Byte Formatter Tests

final class ByteFormatterTests: XCTestCase {

    func testFormatBytes() {
        XCTAssertEqual(ByteFormatter.format(0), "0 B")
        XCTAssertEqual(ByteFormatter.format(500), "500 B")
        XCTAssertEqual(ByteFormatter.format(999), "999 B")
    }

    func testFormatKilobytes() {
        XCTAssertEqual(ByteFormatter.format(1000), "1.0 KB")
        XCTAssertEqual(ByteFormatter.format(1500), "1.5 KB")
        XCTAssertEqual(ByteFormatter.format(10_000), "10.0 KB")
        XCTAssertEqual(ByteFormatter.format(999_999), "1000.0 KB")
    }

    func testFormatMegabytes() {
        XCTAssertEqual(ByteFormatter.format(1_000_000), "1.0 MB")
        XCTAssertEqual(ByteFormatter.format(1_500_000), "1.5 MB")
        XCTAssertEqual(ByteFormatter.format(10_000_000), "10.0 MB")
    }

    func testFormatLargeMegabytes() {
        XCTAssertEqual(ByteFormatter.format(100_000_000), "100.0 MB")
        XCTAssertEqual(ByteFormatter.format(1_000_000_000), "1000.0 MB")
    }

    func testFormatDecimalPrecision() {
        // Check decimal precision (%.1f uses banker's rounding - 1.25 → 1.2)
        XCTAssertEqual(ByteFormatter.format(1_234), "1.2 KB")  // 1.234 → 1.2
        XCTAssertEqual(ByteFormatter.format(1_250_000), "1.2 MB")  // 1.25 → 1.2 (banker's rounding)
    }
}

@MainActor
final class AdaptiveWebViewSizeTests: XCTestCase {
    func testAppPresetFitsAvailableContainer() {
        for height: CGFloat in [320, 568, 852, 1024] {
            let ratio = BarConstants.appContainerHeightRatio(for: height)
            XCTAssertEqual(CGFloat(ratio) * height, height - BarConstants.totalUIHeight, accuracy: 0.001)
            XCTAssertTrue((0.25...1).contains(ratio))
        }
    }

    func testAppPresetAdaptsWhileCustomAndFullscreenRatiosRemainUnchanged() {
        let original = BarConstants.appContainerHeightRatio(for: 900)
        XCTAssertEqual(BarConstants.heightRatioAfterResize(widthRatio: 1, heightRatio: original, from: 900, to: 400),
                       BarConstants.appContainerHeightRatio(for: 400))
        XCTAssertEqual(BarConstants.heightRatioAfterResize(widthRatio: 1, heightRatio: 0.75, from: 900, to: 400), 0.75)
        XCTAssertEqual(BarConstants.heightRatioAfterResize(widthRatio: 0.75, heightRatio: original, from: 900, to: 400), original)
        XCTAssertEqual(BarConstants.heightRatioAfterResize(widthRatio: 1, heightRatio: 1, from: 900, to: 400), 1)
        XCTAssertEqual(BarConstants.heightRatioAfterResize(widthRatio: 1, heightRatio: original, from: 0, to: 400), original)
    }

    func testAppPresetRemainsValidInShortOrUnmeasuredWindows() {
        for height: CGFloat in [-1, 0, 1, 100, 192, 240] {
            XCTAssertEqual(BarConstants.appContainerHeightRatio(for: height), 0.25)
        }
    }
}

@MainActor
final class NetworkTextResizeTests: XCTestCase {
    func testTextReflowsWhenContainerNarrows() {
        let scrollView = NetworkTextScrollView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        let textView = UITextView()
        textView.tag = 100
        textView.isScrollEnabled = false
        textView.text = String(repeating: "Response body content ", count: 100)
        scrollView.addSubview(textView)
        scrollView.layoutSubviews()
        let wideHeight = scrollView.contentSize.height
        XCTAssertEqual(textView.frame.width, 800)

        scrollView.frame.size.width = 320
        scrollView.layoutSubviews()
        XCTAssertEqual(textView.frame.width, 320)
        XCTAssertGreaterThan(scrollView.contentSize.height, wideHeight)
    }
}

@MainActor
final class AdaptiveDevToolsPresentationTests: XCTestCase {
    func testDockingPreservesSelectedToolWhenSheetDismisses() {
        let state = DevToolsOverlayState()
        state.open(.network)
        let sheet = state.presentationBinding(for: .network)
        XCTAssertTrue(sheet.wrappedValue)
        state.isDocked = true
        XCTAssertFalse(sheet.wrappedValue)
        sheet.wrappedValue = false
        XCTAssertEqual(state.selectedTool, .network)
        state.isDocked = false
        XCTAssertTrue(sheet.wrappedValue)
        sheet.wrappedValue = false
        XCTAssertNil(state.selectedTool)
    }

    func testSwitchingToolsPreservesIndependentPageSearch() {
        let state = DevToolsOverlayState()
        state.open(.console)
        state.open(.searchText)
        state.toggle(.network)
        XCTAssertEqual(state.active, [.network, .searchText])
        state.toggle(.network)
        XCTAssertEqual(state.active, [.searchText])
        state.open(.editor)
        state.closeAll()
        XCTAssertTrue(state.active.isEmpty)
    }
}

final class DevToolsWorkspaceLayoutTests: XCTestCase {
    func testUnfoldedLayoutUsesSideBySidePanes() {
        let frames = DevToolsWorkspaceLayout.frames(in: CGSize(width: 1000, height: 800), division: nil)
        XCTAssertEqual(frames.browser, CGRect(x: 0, y: 0, width: 580, height: 800))
        XCTAssertEqual(frames.tools, CGRect(x: 580, y: 0, width: 420, height: 800))
    }

    func testBookFoldKeepsPanesClearOfReservedRegion() {
        let fold = CGRect(x: 480, y: -20, width: 40, height: 840)
        let frames = DevToolsWorkspaceLayout.frames(in: CGSize(width: 1000, height: 800), division: fold)
        XCTAssertEqual(frames.browser.maxX, 480)
        XCTAssertEqual(frames.tools.minX, 520)
        XCTAssertFalse(frames.browser.intersects(fold))
        XCTAssertFalse(frames.tools.intersects(fold))
    }

    func testTabletopFoldStacksPanesAboveAndBelowFold() {
        let fold = CGRect(x: -20, y: 380, width: 1040, height: 40)
        let frames = DevToolsWorkspaceLayout.frames(in: CGSize(width: 1000, height: 800), division: fold)
        XCTAssertEqual(frames.browser.maxY, 380)
        XCTAssertEqual(frames.tools.minY, 420)
        XCTAssertEqual(frames.tools.height, 380)
    }

    func testNonintersectingDivisionDoesNotAffectLayout() {
        let size = CGSize(width: 1000, height: 800)
        let frames = DevToolsWorkspaceLayout.frames(in: size, division: CGRect(x: 2000, y: 0, width: 30, height: 800))
        XCTAssertEqual(frames.tools, DevToolsWorkspaceLayout.frames(in: size, division: nil).tools)
    }
}
