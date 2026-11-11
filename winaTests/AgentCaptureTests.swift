import UIKit
import XCTest
@testable import wina

@MainActor
final class AgentCaptureTests: XCTestCase {
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
