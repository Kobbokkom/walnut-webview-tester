import Foundation
import Photos
import UIKit

@MainActor
enum AgentCapture {
    static let tools = [
        AgentTool.definition("walnut_screenshot", "Capture the WKWebView or SafariVC app window after approval on the iPhone.", [
            "saveToPhotos": ["type": "boolean"]
        ]),
        AgentTool.definition("walnut_recording", "Start or stop an approved screen recording, query status, or read a completed video in base64 chunks.", [
            "action": ["type": "string", "enum": ["start", "stop", "status", "read"]],
            "saveToPhotos": ["type": "boolean"],
            "offset": ["type": "integer", "minimum": 0]
        ], required: ["action"])
    ]

    static func screenshot(navigator: WebViewNavigator?, safariWindow: UIWindow?, saveToPhotos: Bool) async throws -> [String: Any] {
        let image: UIImage?
        if let navigator {
            image = await navigator.agentScreenshot()
        } else {
            image = safariWindow.map { window in
                UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
            }
        }
        guard let image, let png = image.pngData() else { throw AgentError("Screenshot unavailable.") }
        if saveToPhotos {
            try await requirePhotos()
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }
        }
        return ["mimeType": "image/png", "data": png.base64EncodedString()]
    }

    static func requirePhotos() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else {
            throw AgentError("Photos access was denied.")
        }
    }

    static func recordingStatus(_ recorder: WebViewRecorder) -> [String: Any] {
        var result: [String: Any] = [
            "state": String(describing: recorder.state),
            "duration": recorder.isRecording ? recorder.currentDuration : recorder.recordingDuration,
            "available": recorder.agentOutputURL != nil
        ]
        if case .failed(let message) = recorder.lastResult { result["error"] = message }
        return result
    }

    static func readRecording(_ recorder: WebViewRecorder, offset: Int) throws -> [String: Any] {
        guard let url = recorder.agentOutputURL,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              (0...size).contains(offset) else {
            throw AgentError("Recording unavailable or offset is out of range.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: UInt64(offset))
        let bytes = try file.read(upToCount: 512 * 1024) ?? Data()
        let nextOffset = offset + bytes.count
        return [
            "mimeType": "video/quicktime",
            "recordingId": url.lastPathComponent,
            "data": bytes.base64EncodedString(),
            "offset": offset,
            "nextOffset": nextOffset,
            "size": size,
            "done": nextOffset == size
        ]
    }
}
