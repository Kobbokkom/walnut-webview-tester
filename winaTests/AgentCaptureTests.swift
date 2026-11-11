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
        let screenshot = AgentCapture.safariScreenshotUnavailableReason() == nil ? ["screenshot"] : []
        XCTAssertEqual(actionNames(idle), screenshot + ["startRecording"])

        let started = await recorder.startRecording()
        XCTAssertTrue(started)
        defer { recorder.stopRecording() }
        let active = SafariCaptureActivities.make(for: safari, recorder: recorder, stopMacAgent: {}, isCurrent: { true })
        XCTAssertEqual(actionNames(active), screenshot + ["stopRecording", "stopMacAgent"])
    }

    func testSafariScreenshotSharingGuidanceRequiresAnInactiveCapturedScene() {
        XCTAssertEqual(
            AgentCapture.safariScreenshotInactiveSharingReason(activationState: .foregroundInactive, captureState: .active),
            "End iPhone Mirroring or the active screen sharing session, then open Walnut on the iPhone."
        )
        XCTAssertNil(AgentCapture.safariScreenshotInactiveSharingReason(activationState: .foregroundActive, captureState: .active))
        XCTAssertNil(AgentCapture.safariScreenshotInactiveSharingReason(activationState: .foregroundInactive, captureState: .inactive))
        XCTAssertNil(AgentCapture.safariScreenshotInactiveSharingReason(activationState: .background, captureState: .active))
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

    func testSafariRejectsTransparentDisplayBeforePreview() async {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30), format: format).image { _ in }
        do {
            _ = try await AgentCapture.screenshot(source: .safariDisplay { image }, saveToPhotos: false) { _ in
                XCTFail("A transparent display must not be offered for sharing.")
                return true
            } validateTarget: {}
            XCTFail("A transparent display must not be exported.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "iOS did not capture visible pixels from the display.")
        }
    }

    func testSafariExportRequiresPreviewApprovalAndReportsDisplayScope() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        }
        let source = AgentCapture.ScreenshotSource.safariDisplay { image }
        do {
            _ = try await AgentCapture.screenshot(source: source, saveToPhotos: false) { preview in
                XCTAssertTrue(preview === image)
                return false
            } validateTarget: {}
            XCTFail("A declined preview must not be exported.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Screenshot sharing was denied.")
        }

        let result = try await AgentCapture.screenshot(source: source, saveToPhotos: false) { preview in
            XCTAssertTrue(preview === image)
            return true
        } validateTarget: {}
        XCTAssertEqual(result["captureScope"] as? String, "display")
        XCTAssertEqual(result["data"] as? String, image.pngData()?.base64EncodedString())
        XCTAssertEqual(result["savedToPhotos"] as? Bool, false)
    }

    func testSafariSystemPickerCancellationNeverPromptsToShare() async {
        do {
            let source = AgentCapture.ScreenshotSource.safariDisplay { throw AgentError("iOS screen capture was cancelled.") }
            _ = try await AgentCapture.screenshot(source: source, saveToPhotos: false) { _ in
                XCTFail("A cancelled system capture cannot be offered for sharing.")
                return true
            } validateTarget: {}
            XCTFail("A cancelled system capture must not be exported.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "iOS screen capture was cancelled.")
        }
    }

    func testSafariPageChangeDuringPreviewPreventsExport() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        }
        var targetChanged = false
        do {
            _ = try await AgentCapture.screenshot(source: .safariDisplay { image }, saveToPhotos: false) { _ in
                targetChanged = true
                return true
            } validateTarget: {
                if targetChanged { throw AgentError("Page changed") }
            }
            XCTFail("Approval for the old page must not export its image after navigation.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Page changed")
        }
    }

    func testSafariScreenshotRetainsNativeSizeUntilItsEscapedPNGExceedsTheBudget() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 96, height: 80)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 10, y: 10, width: 42, height: 54))
        }
        func jsonSize(_ value: String) throws -> Int {
            try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]).count - 2
        }
        let original = try XCTUnwrap(image.pngData()).base64EncodedString()
        let nativeBudget = try jsonSize(original)
        let (nativeImage, nativePNG) = try AgentCapture.safariScreenshotForExport(image, maximumEncodedBytes: nativeBudget)
        XCTAssertTrue(nativeImage === image)
        XCTAssertEqual(nativePNG, original)

        let (smallerImage, smallerPNG) = try AgentCapture.safariScreenshotForExport(image, maximumEncodedBytes: nativeBudget - 1)
        XCTAssertLessThan(smallerImage.size.width, image.size.width)
        XCTAssertLessThanOrEqual(try jsonSize(smallerPNG), nativeBudget - 1)
        XCTAssertEqual(smallerPNG, try XCTUnwrap(smallerImage.pngData()).base64EncodedString())
        XCTAssertThrowsError(try AgentCapture.safariScreenshotForExport(image, maximumEncodedBytes: 4))
    }

    func testSafariScreenshotBudgetIncludesTheActualEvidenceAndLargestEscapedRequestID() throws {
        var evidence: [String: Any] = ["navigation": ["url": "https://example.com/a/b"], "runId": UUID().uuidString]
        let budget = try AgentCapture.safariScreenshotBudget(evidence: evidence, saveToPhotos: true)
        evidence["data"] = ["data": "", "mimeType": "image/png", "captureScope": "display", "savedToPhotos": true]
        let longestEscapedID = String(repeating: "\0", count: AgentRequest.maximumIDBytes)
        let response = try JSONSerialization.data(withJSONObject: ["id": longestEscapedID, "result": evidence])
        XCTAssertEqual(budget + response.count, AgentSession.maxResponse - 1)
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
