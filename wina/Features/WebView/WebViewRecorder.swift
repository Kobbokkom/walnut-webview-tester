//
//  WebViewRecorder.swift
//  wina
//
//  Screen recorder using ReplayKit for high-fps capture.
//

import AVFoundation
import Photos
import ReplayKit
import UIKit

// MARK: - Recording Types

enum RecordingResult: Equatable {
    case success
    case permissionDenied
    case failed(String)
}

enum RecordingState: Sendable {
    case idle
    case starting
    case recording
    case finishing
}

// MARK: - WebView Recorder

private final class WriterState {
    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var sessionStarted = false
    var firstSampleTime: CMTime?
    var captureURL: URL?

    func reset() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false
        firstSampleTime = nil
        captureURL = nil
    }

    func markInputsFinished() {
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
    }

    func processVideoSample(_ sampleBuffer: CMSampleBuffer, outputURL: URL?) {
        if assetWriter == nil {
            guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            let videoSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))

            guard setupAssetWriter(videoSize: videoSize, outputURL: outputURL) else { return }
        }

        guard let writer = assetWriter, let input = videoInput else { return }

        if !sessionStarted {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: presentationTime)
            firstSampleTime = presentationTime
            sessionStarted = true
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted else { return }
        guard let input = audioInput, input.isReadyForMoreMediaData else { return }

        input.append(sampleBuffer)
    }

    private func setupAssetWriter(videoSize: CGSize, outputURL: URL?) -> Bool {
        guard let url = outputURL else { return false }

        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            return false
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        guard let writer = assetWriter,
              let vInput = videoInput,
              let aInput = audioInput else { return false }

        if writer.canAdd(vInput) {
            writer.add(vInput)
        } else {
            return false
        }

        if writer.canAdd(aInput) {
            writer.add(aInput)
        }

        writer.startWriting()
        return true
    }
}

@Observable
@MainActor
final class WebViewRecorder {
    private static weak var activeRecorder: WebViewRecorder?

    private(set) var state: RecordingState = .idle
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var lastResult: RecordingResult?
    private(set) var startFailure: String?
    private(set) var failedOutputURL: URL?
    private(set) var stopRequested = false
    private(set) var isAgentCapture = false
    private var retainForAgent = false
    private var shouldSaveToPhotos = true
    private(set) var agentOutputURL: URL?

    func discardAgentRecording() {
        retainForAgent = false
        if let agentOutputURL { try? FileManager.default.removeItem(at: agentOutputURL) }
        agentOutputURL = nil
    }

    typealias CaptureHandler = (CMSampleBuffer, RPSampleBufferType, Error?) -> Void
    private let captureStart: (@escaping CaptureHandler) async throws -> Void
    private let captureStop: () async throws -> Void
    private let photoSave: (URL) async throws -> Void

    init(
        startCapture: ((@escaping CaptureHandler) async throws -> Void)? = nil,
        stopCapture: (() async throws -> Void)? = nil,
        saveToPhotos: ((URL) async throws -> Void)? = nil
    ) {
        captureStart = startCapture ?? Self.startSystemCapture
        captureStop = stopCapture ?? Self.stopSystemCapture
        photoSave = saveToPhotos ?? Self.saveSystemVideo
    }

    var isRecording: Bool { state == .recording }

    /// Computed duration for real-time display (used with TimelineView)
    var currentDuration: TimeInterval {
        guard let start = startTime, state == .recording else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // Recording state (main actor isolated)
    private var startTime: Date?
    private var outputURL: URL?

    // Duration update timer
    private var durationTimer: Timer?

    // Dedicated queue for AVAssetWriter operations (thread-safe)
    private let writerQueue = DispatchQueue(label: "com.wina.assetwriter", qos: .userInitiated)

    // Writer state (accessed only on writerQueue)
    private let writerState = WriterState()

    // MARK: - Recording Control

    func startRecording(retainForAgent: Bool = false, saveToPhotos: Bool = true) async -> Bool {
        guard let url = prepareRecording(retainForAgent: retainForAgent, saveToPhotos: saveToPhotos) else { return false }
        return await completeStart(outputURL: url)
    }

    func beginRecording(retainForAgent: Bool, saveToPhotos: Bool) -> Task<Bool, Never>? {
        guard let url = prepareRecording(retainForAgent: retainForAgent, saveToPhotos: saveToPhotos) else { return nil }
        return Task { await completeStart(outputURL: url) }
    }

    private func prepareRecording(retainForAgent: Bool, saveToPhotos: Bool) -> URL? {
        guard state == .idle else { return nil }
        startFailure = nil
        guard Self.activeRecorder == nil else {
            startFailure = "A screen recording is already active or awaiting approval."
            return nil
        }

        // Note: Photo library permission should be checked by caller before calling this method
        // This avoids race conditions where permission was just granted but status hasn't propagated

        // Setup output URL
        let fileName = "ScreenRecording_\(UUID().uuidString).mov"
        let directory = retainForAgent ? FileManager.default.temporaryDirectory
            : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(fileName)
        outputURL = url

        // Reset state
        let writerState = writerState
        writerQueue.sync {
            writerState.reset()
            writerState.captureURL = url
        }

        discardAgentRecording()
        isAgentCapture = retainForAgent
        self.retainForAgent = retainForAgent
        shouldSaveToPhotos = saveToPhotos
        Self.activeRecorder = self
        state = .starting
        stopRequested = false
        lastResult = nil
        failedOutputURL = nil
        startTime = nil
        recordingDuration = 0

        return url
    }

    private func completeStart(outputURL: URL) async -> Bool {
        do {
            if stopRequested { throw CancellationError() }
            try await startReplayKitCapture(outputURL: outputURL)
            state = .recording

            if stopRequested {
                stopRecording()
            } else {
                startTime = Date()
                startDurationTimer()
            }
            return true
        } catch {
            startFailure = stopRequested ? "Recording was stopped before it started." : error.localizedDescription
            discardPendingCapture(outputURL: outputURL)
            completeRecording()
            return false
        }
    }

    func stopRecording() {
        if state == .starting {
            stopRequested = true
            let writerState = writerState
            writerQueue.async { writerState.captureURL = nil }
            return
        }
        guard state == .recording else { return }
        state = .finishing

        let writerState = writerState
        writerQueue.async {
            writerState.captureURL = nil
        }

        // Stop duration timer
        durationTimer?.invalidate()
        durationTimer = nil

        // Retain the recorder until its writer and Photos operation have completed.
        Task {
            var captureError: Error?
            do { try await captureStop() } catch { captureError = error }
            await finishRecording(captureError: captureError)
        }
    }

    // MARK: - ReplayKit Capture

    private func startReplayKitCapture(outputURL: URL) async throws {
        let writerState = writerState
        let queue = writerQueue
        try await captureStart { sampleBuffer, sampleBufferType, _ in
            queue.async {
                guard writerState.captureURL == outputURL else { return }
                switch sampleBufferType {
                case .video:
                    writerState.processVideoSample(sampleBuffer, outputURL: outputURL)
                case .audioApp:
                    writerState.processAudioSample(sampleBuffer)
                case .audioMic:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private static func startSystemCapture(handler: @escaping CaptureHandler) async throws {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !recorder.isRecording else {
            throw NSError(domain: "ScreenRecording", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Screen recording is unavailable."])
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture(handler: handler) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func stopSystemCapture() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            RPScreenRecorder.shared().stopCapture { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func saveSystemVideo(url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        // Use Timer on main RunLoop explicitly for @MainActor context
        durationTimer = Timer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(handleDurationTick),
            userInfo: nil,
            repeats: true
        )
        if let durationTimer {
            RunLoop.main.add(durationTimer, forMode: .common)
        }
    }

    @objc private func handleDurationTick() {
        guard let start = startTime else { return }
        recordingDuration = Date().timeIntervalSince(start)
    }

    // MARK: - Finish Recording

    private func finishRecording(captureError: Error?) async {
        defer { completeRecording() }
        if stopRequested {
            discardPendingCapture(outputURL: outputURL)
            lastResult = .failed(captureError?.localizedDescription ?? "Recording was stopped before it started.")
            return
        }
        let writerState = writerState
        let writer = writerQueue.sync { writerState.assetWriter }
        guard let writer, let url = outputURL else {
            lastResult = .failed("No video frames were recorded.")
            return
        }
        if writer.status == .writing {
            writerQueue.sync { writerState.markInputsFinished() }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
        }
        guard writer.status == .completed, captureError == nil else {
            if shouldSaveToPhotos && !isAgentCapture {
                failedOutputURL = url
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            lastResult = .failed(captureError?.localizedDescription ?? writer.error?.localizedDescription ?? "Could not finish the recording.")
            return
        }
        do {
            if shouldSaveToPhotos { try await photoSave(url) }
            if retainForAgent {
                agentOutputURL = url
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            lastResult = .success
        } catch {
            if retainForAgent {
                agentOutputURL = url
            } else if isAgentCapture {
                try? FileManager.default.removeItem(at: url)
            } else {
                failedOutputURL = url
            }
            let kept = retainForAgent || !isAgentCapture ? " The recording file was kept." : ""
            lastResult = .failed("Could not save to Photos.\(kept) \(error.localizedDescription)")
        }
    }

    private func cleanupWriter() {
        let writerState = writerState
        writerQueue.sync {
            writerState.reset()
        }
    }

    private func discardPendingCapture(outputURL: URL?) {
        let writerState = writerState
        writerQueue.sync {
            writerState.captureURL = nil
            if let writer = writerState.assetWriter, writer.status == .writing { writer.cancelWriting() }
        }
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    }

    private func completeRecording() {
        cleanupWriter()
        startTime = nil
        outputURL = nil
        if Self.activeRecorder === self { Self.activeRecorder = nil }
        state = .idle
    }
}

#if DEBUG
extension WebViewRecorder {
    func test_prepareRecording(writer: AVAssetWriter, input: AVAssetWriterInput, url: URL, retainForAgent: Bool = false) {
        outputURL = url
        isAgentCapture = retainForAgent
        self.retainForAgent = retainForAgent
        writerQueue.sync {
            writerState.assetWriter = writer
            writerState.videoInput = input
            writerState.captureURL = url
        }
        state = .recording
    }

    func test_setStartTime(_ date: Date?) {
        startTime = date
    }

    func test_handleDurationTick() {
        handleDurationTick()
    }
}
#endif
