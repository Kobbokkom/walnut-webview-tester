import Foundation
import Photos
import UIKit
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

@MainActor
enum AgentCapture {
    static let tools = [
        AgentTool.definition("walnut_screenshot", "Capture the WKWebView after approval. SafariVC requires iOS 27 or later and a Walnut build with ScreenCaptureKit; the iPhone user approves a display capture in the system picker and reviews it before sharing.", [
            "saveToPhotos": ["type": "boolean"]
        ]),
        AgentTool.definition("walnut_recording", "Start or stop an approved screen recording, query status, or read a completed video in base64 chunks. With waitForStart=false, poll status while iOS waits for screen-capture approval.", [
            "action": ["type": "string", "enum": ["start", "stop", "status", "read"]],
            "saveToPhotos": ["type": "boolean"],
            "waitForStart": ["type": "boolean", "default": true, "description": "For start, return starting after Walnut and any Photos approval, then poll for recording or an error."],
            "offset": ["type": "integer", "minimum": 0]
        ], required: ["action"])
    ]

    enum ScreenshotSource {
        case wkWebView(WebViewNavigator)
        case safariDisplay(() async throws -> UIImage)
    }

    static let safariScreenshotRequiresScreenCaptureKit = "SafariVC display screenshots require iOS 27 or later and a Walnut build with ScreenCaptureKit."
    static let safariScreenshotUnavailableOnDevice = "iOS display capture is currently unavailable on this device."

    static var safariScreenshotUnavailableReason: String? {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return SCContentSharingPicker.shared.isAvailable ? nil : safariScreenshotUnavailableOnDevice
        }
        #endif
        return safariScreenshotRequiresScreenCaptureKit
    }

    static func captureSafariDisplay(in window: UIWindow, validateTarget: @escaping @MainActor () throws -> Void) async throws -> UIImage {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return try await SafariDisplayFrameCapture.capture(in: window, validateTarget: validateTarget)
        }
        #endif
        throw AgentError(safariScreenshotRequiresScreenCaptureKit)
    }

    static func screenshot(
        source: ScreenshotSource,
        saveToPhotos: Bool,
        evidence: [String: Any] = [:],
        approveSafariPreview: (UIImage) async -> Bool,
        validateTarget: () throws -> Void
    ) async throws -> [String: Any] {
        try validateTarget()
        let image: UIImage
        let encodedPNG: String?
        let scope: String
        switch source {
        case .wkWebView(let navigator):
            guard let screenshot = await navigator.agentScreenshot() else {
                throw AgentError("WebKit did not capture visible pixels from the page.")
            }
            image = screenshot
            encodedPNG = nil
            scope = "wkWebView"
        case .safariDisplay(let capture):
            let screenshot = try await capture()
            try validateTarget()
            guard WebViewNavigator.hasVisiblePixels(screenshot) else {
                throw AgentError("iOS did not capture visible pixels from the display.")
            }
            let budget = try safariScreenshotBudget(evidence: evidence, saveToPhotos: saveToPhotos)
            (image, encodedPNG) = try safariScreenshotForExport(screenshot, maximumEncodedBytes: budget)
            guard await approveSafariPreview(image) else { throw AgentError("Screenshot sharing was denied.") }
            scope = "display"
        }
        try validateTarget()
        var result = try await exportScreenshot(image, saveToPhotos: saveToPhotos, encodedPNG: encodedPNG, validateTarget: validateTarget)
        result["captureScope"] = scope
        return result
    }

    static func safariScreenshotBudget(evidence: [String: Any], saveToPhotos: Bool) throws -> Int {
        var envelope = evidence
        var screenshot = screenshotData("", savedToPhotos: saveToPhotos)
        screenshot["captureScope"] = "display"
        envelope["data"] = screenshot
        let overhead = try JSONSerialization.data(withJSONObject: ["id": "", "result": envelope]).count
        // One UTF-8 byte in a request ID can grow to six JSON bytes. The bridge rejects responses at its limit.
        return AgentSession.maxResponse - overhead - AgentRequest.maximumIDBytes * 6 - 1
    }

    static func safariScreenshotForExport(_ original: UIImage, maximumEncodedBytes: Int) throws -> (UIImage, String) {
        var image = original
        for attempt in 0..<4 {
            try Task.checkCancellation()
            guard maximumEncodedBytes > 0, let png = image.pngData() else { break }
            if (png.count + 2) / 3 * 4 <= maximumEncodedBytes {
                let base64 = png.base64EncodedString()
                // Foundation escapes slashes when serializing the bridge response.
                let bytes = base64.utf8
                let slashes = bytes.reduce(0) { $0 + ($1 == UInt8(ascii: "/") ? 1 : 0) }
                if bytes.count + slashes <= maximumEncodedBytes { return (image, base64) }
            }
            guard attempt < 3 else { break }
            let size = CGSize(
                width: max(1, (image.size.width * image.scale * 0.75).rounded(.down)),
                height: max(1, (image.size.height * image.scale * 0.75).rounded(.down))
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.preferredRange = .standard
            let previous = image
            image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                previous.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        throw AgentError("The SafariVC screenshot could not fit the Mac Agent transfer limit.")
    }

    static func exportScreenshot(
        _ image: UIImage,
        saveToPhotos: Bool,
        encodedPNG: String? = nil,
        validateTarget: () throws -> Void,
        requestPhotos: () async throws -> Void = { try await AgentCapture.requirePhotos() },
        savePhoto: (UIImage) async throws -> Void = { try await AgentCapture.savePhoto($0) }
    ) async throws -> [String: Any] {
        guard let png = encodedPNG ?? image.pngData()?.base64EncodedString() else { throw AgentError("Screenshot unavailable.") }
        if saveToPhotos {
            try await requestPhotos()
            try validateTarget()
            try await savePhoto(image)
        }
        return screenshotData(png, savedToPhotos: saveToPhotos)
    }

    private static func screenshotData(_ png: String, savedToPhotos: Bool) -> [String: Any] {
        ["mimeType": "image/png", "data": png, "savedToPhotos": savedToPhotos]
    }

    static func savePhoto(_ image: UIImage) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAsset(from: image)
        }
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
        if recorder.state == .starting, recorder.stopRequested { result["stopRequested"] = true }
        if let failure = recorder.startFailure { result["error"] = failure }
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
