import Foundation
import Photos
import UIKit

@MainActor
enum AgentCapture {
    static let tools = [
        AgentTool.definition("walnut_screenshot", "Capture the WKWebView or the SafariVC host window after approval on the iPhone. The SafariVC preview can omit the remote page. Review it before sharing.", [
            "saveToPhotos": ["type": "boolean"]
        ]),
        AgentTool.definition("walnut_recording", "Start or stop an approved screen recording, query status, or read a completed video in base64 chunks.", [
            "action": ["type": "string", "enum": ["start", "stop", "status", "read"]],
            "saveToPhotos": ["type": "boolean"],
            "offset": ["type": "integer", "minimum": 0]
        ], required: ["action"])
    ]

    static func screenshot(
        navigator: WebViewNavigator?,
        safariWindow: UIWindow?,
        saveToPhotos: Bool,
        approveSafariPreview: (UIImage) async -> Bool,
        validateTarget: () throws -> Void
    ) async throws -> [String: Any] {
        try validateTarget()
        let image: UIImage?
        if let navigator {
            image = await navigator.agentScreenshot()
        } else {
            guard let window = safariWindow, !window.bounds.isEmpty else { throw AgentError("Screenshot unavailable.") }
            var captured = false
            let frame = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                captured = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            image = captured ? frame : nil
        }
        try validateTarget()
        guard let image else {
            throw AgentError(navigator == nil ? "Screenshot unavailable." : "WebKit did not capture visible pixels from the page.")
        }
        if safariWindow != nil {
            guard await approveSafariPreview(image) else { throw AgentError("Screenshot sharing was denied.") }
            try validateTarget()
        }
        var result = try await exportScreenshot(image, saveToPhotos: saveToPhotos, validateTarget: validateTarget)
        result["captureScope"] = safariWindow == nil ? "wkWebView" : "hostWindow"
        return result
    }

    static func exportScreenshot(
        _ image: UIImage,
        saveToPhotos: Bool,
        validateTarget: () throws -> Void,
        requestPhotos: () async throws -> Void = { try await AgentCapture.requirePhotos() },
        savePhoto: (UIImage) async throws -> Void = { image in
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }
        }
    ) async throws -> [String: Any] {
        guard let png = image.pngData() else { throw AgentError("Screenshot unavailable.") }
        if saveToPhotos {
            try await requestPhotos()
            try validateTarget()
            try await savePhoto(image)
        }
        return ["mimeType": "image/png", "data": png.base64EncodedString(), "savedToPhotos": saveToPhotos]
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
