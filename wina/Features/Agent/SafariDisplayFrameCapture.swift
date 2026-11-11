#if canImport(ScreenCaptureKit)
import CoreImage
import CoreMedia
@preconcurrency import ScreenCaptureKit
import UIKit

@available(iOS 27.0, *)
@MainActor
final class SafariDisplayFrameCapture: NSObject {
    private enum Phase {
        case picking
        case waitingForForeground(SCContentFilter)
        case starting(SCStream, UIImage?)
        case capturing(SCStream)
        case stopping(SCStream)
    }

    private static var owner: SafariDisplayFrameCapture?
    private let picker = SCContentSharingPicker.shared
    private let window: UIWindow
    private let scene: UIWindowScene
    private let validateTarget: @MainActor () throws -> Void
    private var phase: Phase = .picking
    private var originalConfiguration: SCContentSharingPickerConfiguration?
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var deadline: Task<Void, Never>?

    private init(window: UIWindow, scene: UIWindowScene, validateTarget: @escaping @MainActor () throws -> Void) {
        self.window = window
        self.scene = scene
        self.validateTarget = validateTarget
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    static func capture(in window: UIWindow, validateTarget: @escaping @MainActor () throws -> Void) async throws -> UIImage {
        guard let scene = window.windowScene else { throw AgentError("The SafariVC window is no longer visible.") }
        let capture = SafariDisplayFrameCapture(window: window, scene: scene, validateTarget: validateTarget)
        try Task.checkCancellation()
        try capture.requireForeground()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation(capture.begin)
        } onCancel: {
            Task { @MainActor in capture.cancel(CancellationError()) }
        }
    }

    private func begin(_ continuation: CheckedContinuation<UIImage, Error>) {
        guard !Task.isCancelled else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard picker.isAvailable else {
            continuation.resume(throwing: AgentError(AgentCapture.safariScreenshotUnavailableOnDevice))
            return
        }
        guard Self.owner == nil, !picker.isActive else {
            continuation.resume(throwing: AgentError("The iOS screen capture picker is already open."))
            return
        }
        Self.owner = self
        self.continuation = continuation
        originalConfiguration = picker.defaultConfiguration
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(startIfForeground), name: UIScene.didActivateNotification, object: scene)
        notifications.addObserver(self, selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: scene)
        notifications.addObserver(self, selector: #selector(sceneLeftForeground), name: UIScene.didEnterBackgroundNotification, object: scene)
        notifications.addObserver(self, selector: #selector(sceneLeftForeground), name: UIScene.didDisconnectNotification, object: scene)
        picker.add(self)
        picker.isActive = true
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            self?.cancel(AgentError("Display capture timed out. Close the iOS screen capture picker before retrying."))
        }
        picker.present(using: .display)
    }

    private func requireForeground() throws {
        guard window.windowScene === scene, window.isKeyWindow, scene.activationState == .foregroundActive else {
            throw AgentError("The SafariVC window is no longer active.")
        }
        try validateTarget()
    }

    @objc private func startIfForeground() {
        guard case .waitingForForeground(let filter) = phase, scene.activationState == .foregroundActive else { return }
        do {
            try requireForeground()
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = false
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            phase = .starting(stream, nil)
            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    complete(.failure(error))
                    if stream.isCapturing {
                        stop(stream)
                    } else {
                        finishStream(stream)
                    }
                    return
                }
                guard case .starting(_, let frame) = phase else { return }
                phase = .capturing(stream)
                if continuation == nil || frame != nil { stop(stream, frame: frame) }
            }
        } catch {
            complete(.failure(error))
            releasePicker()
        }
    }

    @objc private func sceneDeactivated() {
        switch phase {
        case .starting, .capturing, .stopping: sceneLeftForeground()
        case .picking, .waitingForForeground: break
        }
    }

    @objc private func sceneLeftForeground() {
        cancel(AgentError("The SafariVC window is no longer active."))
    }

    private func receive(_ buffer: CMSampleBuffer, from stream: SCStream) {
        guard continuation != nil, buffer.isValid, CMSampleBufferDataIsReady(buffer),
              let pixels = buffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: status) == .complete else { return }
        switch phase {
        case .starting(let current, nil) where current === stream, .capturing(let current) where current === stream:
            do {
                try requireForeground()
                let input = CIImage(cvPixelBuffer: pixels)
                guard !input.extent.isEmpty, let image = CIContext().createCGImage(input, from: input.extent) else {
                    throw AgentError("iOS did not return a display image.")
                }
                let frame = UIImage(cgImage: image)
                if case .starting = phase {
                    phase = .starting(stream, frame)
                } else {
                    stop(stream, frame: frame)
                }
            } catch {
                cancel(error)
            }
        default: break
        }
    }

    private func stop(_ stream: SCStream, frame: UIImage? = nil) {
        phase = .stopping(stream)
        Task {
            do {
                try await stream.stopCapture()
                if let frame, continuation != nil {
                    try requireForeground()
                    complete(.success(frame))
                }
            } catch {
                complete(.failure(error))
                if stream.isCapturing { try? await stream.stopCapture() }
            }
            finishStream(stream)
        }
    }

    private func finishStream(_ stream: SCStream) {
        try? stream.removeStreamOutput(self, type: .screen)
        if !stream.isCapturing { releasePicker() }
    }

    private func cancel(_ error: Error) {
        guard continuation != nil else { return }
        complete(.failure(error))
        switch phase {
        // Keep ownership until the system replies so a late selection cannot authorize a later request.
        case .picking, .starting, .stopping: break
        case .waitingForForeground: releasePicker()
        case .capturing(let stream): stop(stream)
        }
    }

    private func complete(_ result: Result<UIImage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        continuation.resume(with: result)
    }

    private func releasePicker() {
        guard Self.owner === self else { return }
        picker.remove(self)
        picker.isActive = false
        if let originalConfiguration { picker.defaultConfiguration = originalConfiguration }
        Self.owner = nil
    }
}

@available(iOS 27.0, *)
extension SafariDisplayFrameCapture: SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?
    ) {
        guard stream == nil else { return }
        Task { @MainActor in
            guard Self.owner === self, case .picking = phase else { return }
            guard continuation != nil, filter.style == .display, !filter.isMicrophoneEnabled, !filter.isCameraEnabled else {
                complete(.failure(AgentError("Select the display without camera or microphone access.")))
                releasePicker()
                return
            }
            phase = .waitingForForeground(filter)
            startIfForeground()
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard stream == nil else { return }
        contentSharingPickerStartDidFailWithError(AgentError("iOS screen capture was cancelled."))
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in
            guard Self.owner === self, case .picking = phase else { return }
            complete(.failure(error))
            releasePicker()
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        // The stream delivers these samples on the main queue.
        MainActor.assumeIsolated { receive(buffer, from: stream) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard Self.owner === self else { return }
            if case .stopping(let current) = phase, current === stream, !stream.isCapturing {
                complete(.failure(error))
                finishStream(stream)
            } else {
                cancel(error)
            }
        }
    }
}
#endif
