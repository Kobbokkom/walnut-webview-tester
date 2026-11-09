import UIKit
import XCTest
@testable import wina

@MainActor
final class AgentCaptureTests: XCTestCase {
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
