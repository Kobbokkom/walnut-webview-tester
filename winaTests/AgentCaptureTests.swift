import SafariServices
import UIKit
import XCTest
@testable import wina

@MainActor
final class AgentCaptureTests: XCTestCase {
    func testSafariShareActionsFollowRecorderAndAgentState() async {
        let safari = SFSafariViewController(url: URL(string: "https://example.com")!)
        let recorder = WebViewRecorder(startCapture: { _ in }, stopCapture: {})
        func actionNames(_ actions: [UIActivity]) -> [String] {
            actions.compactMap { $0.activityType?.rawValue.components(separatedBy: ".").last }
        }

        let idle = SafariCaptureActivities.make(for: safari, recorder: recorder) { true }
        XCTAssertEqual(actionNames(idle), ["screenshot", "startRecording"])

        let started = await recorder.startRecording()
        XCTAssertTrue(started)
        defer { recorder.stopRecording() }
        let active = SafariCaptureActivities.make(for: safari, recorder: recorder, stopMacAgent: {}, isCurrent: { true })
        XCTAssertEqual(actionNames(active), ["screenshot", "stopRecording", "stopMacAgent"])
    }

    func testSafariRecordingIndicatorRespectsTheReservedSystemInset() throws {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let label = CGSize(width: 62, height: 16)
        let inset = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        let frame = try XCTUnwrap(SafariRecordingIndicator.indicatorFrame(in: bounds, safeArea: inset, labelSize: label))
        XCTAssertGreaterThanOrEqual(frame.minY, bounds.maxY - inset.bottom)
        XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY)
        XCTAssertLessThanOrEqual(frame.maxX, bounds.width / 4)
        XCTAssertNil(SafariRecordingIndicator.indicatorFrame(in: bounds, safeArea: .zero, labelSize: label))
        XCTAssertNil(SafariRecordingIndicator.indicatorFrame(in: bounds, safeArea: inset, labelSize: CGSize(width: 120, height: 16)))
    }

    func testTransparentScreenshotIsRejectedWithoutRejectingOpaqueBlackPage() {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30), format: format)
        let transparent = renderer.image { _ in }
        let black = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        }
        XCTAssertFalse(WebViewNavigator.hasVisiblePixels(transparent))
        XCTAssertTrue(WebViewNavigator.hasVisiblePixels(black))
    }

    func testSafariRejectsTransparentWindowBeforePreview() async {
        let window = EmptyDrawingWindow(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        do {
            _ = try await AgentCapture.screenshot(navigator: nil, safariWindow: window, saveToPhotos: false) { _ in
                XCTFail("A transparent window must not be offered for sharing.")
                return true
            } validateTarget: {}
            XCTFail("A transparent window must not be exported.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "iOS did not capture visible pixels from the SafariVC host window.")
        }
    }

    func testNavigationDuringPhotoSaveStillReportsTheCommittedImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        var targetChanged = false
        let result = try await AgentCapture.exportScreenshot(image, saveToPhotos: true) {
            if targetChanged { throw AgentError("Page changed") }
        } requestPhotos: {} savePhoto: { saved in
            XCTAssertTrue(saved === image)
            targetChanged = true
        }

        XCTAssertTrue(targetChanged)
        XCTAssertEqual(result["savedToPhotos"] as? Bool, true)
        XCTAssertEqual(result["data"] as? String, image.pngData()?.base64EncodedString())
    }
}

@MainActor
private final class EmptyDrawingWindow: UIWindow {
    override func drawHierarchy(in rect: CGRect, afterScreenUpdates afterUpdates: Bool) -> Bool {
        true
    }
}
