#if canImport(ScreenCaptureKit)
import CoreImage
import CoreMedia
@preconcurrency import ScreenCaptureKit
import UIKit

@available(iOS 27.0, *)
@MainActor
final class SafariDisplayFrameCapture: NSObject {
    private enum Phase {
        case waitingToPresent
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
    private var phase: Phase = .waitingToPresent
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
        if let owner = Self.owner {
            continuation.resume(throwing: AgentError(owner.busyMessage))
            return
        }
        do {
            try requireAttachedTarget()
            try requirePicker()
        } catch {
            continuation.resume(throwing: error)
            return
        }
        Self.owner = self
        self.continuation = continuation
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(windowReady), name: UIScene.didActivateNotification, object: scene)
        notifications.addObserver(self, selector: #selector(windowReady), name: UIWindow.didBecomeKeyNotification, object: window)
        notifications.addObserver(self, selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: scene)
        notifications.addObserver(self, selector: #selector(sceneDeactivated), name: UIWindow.didResignKeyNotification, object: window)
        notifications.addObserver(self, selector: #selector(sceneLeftForeground), name: UIScene.didEnterBackgroundNotification, object: scene)
        notifications.addObserver(self, selector: #selector(sceneLeftForeground), name: UIScene.didDisconnectNotification, object: scene)
        startDeadline(after: .seconds(3))
        windowReady()
    }

    private var busyMessage: String {
        if continuation != nil { return "A display capture is already in progress." }
        if case .picking = phase {
            return "The previous iOS screen capture picker has not closed. Close it on the device, or relaunch Walnut if it never appeared."
        }
        return "iOS is still finishing the previous display capture."
    }

    private func requirePicker() throws {
        guard picker.isAvailable else { throw AgentError(AgentCapture.safariScreenshotUnavailableOnDevice) }
        guard !picker.isActive else { throw AgentError("The iOS screen capture picker is already open.") }
    }

    private func presentPicker() throws {
        try requireForeground()
        try requirePicker()
        originalConfiguration = picker.defaultConfiguration
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        phase = .picking
        picker.add(self)
        picker.isActive = true
        startDeadline(after: .seconds(25))
        picker.present()
    }

    private func startDeadline(after delay: Duration) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            cancel(AgentError(timeoutMessage))
        }
    }

    private var timeoutMessage: String {
        switch phase {
        case .waitingToPresent: "The SafariVC window did not become active before opening the iOS screen capture picker."
        case .picking: "The iOS screen capture picker did not respond. Close it on the device, or relaunch Walnut if it never appeared."
        case .waitingForForeground: "The SafariVC window did not become active after iOS display selection."
        case .starting: "iOS did not start the display stream in time."
        case .capturing: "iOS did not return a complete display frame in time."
        case .stopping: "iOS did not stop the display stream in time."
        }
    }

    private func requireAttachedTarget() throws {
        guard window.windowScene === scene, scene.activationState != .background, scene.activationState != .unattached else {
            throw AgentError("The SafariVC window is no longer in the foreground.")
        }
        try validateTarget()
    }

    private func requireForeground() throws {
        try requireAttachedTarget()
        guard window.isKeyWindow, scene.activationState == .foregroundActive else {
            throw AgentError("The SafariVC window is no longer active.")
        }
    }

    @objc private func windowReady() {
        guard continuation != nil, window.isKeyWindow, scene.activationState == .foregroundActive else { return }
        switch phase {
        case .waitingToPresent:
            do { try presentPicker() } catch { cancel(error) }
        case .waitingForForeground(let filter):
            startCapture(filter)
        default: break
        }
    }

    private func startCapture(_ filter: SCContentFilter) {
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
        case .waitingToPresent, .picking, .waitingForForeground: break
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
        case .waitingToPresent, .waitingForForeground: releasePicker()
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
        if let originalConfiguration {
            picker.remove(self)
            picker.isActive = false
            picker.defaultConfiguration = originalConfiguration
        }
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
            windowReady()
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
