import AVFoundation
import XCTest
@testable import wina

@MainActor
final class RecordingCompletionTests: XCTestCase {
    private var outputFiles: [URL] = []

    override func tearDown() async throws {
        for file in outputFiles { try? FileManager.default.removeItem(at: file) }
        outputFiles = []
        try await super.tearDown()
    }

    func testSuccessWaitsForWriterAndPhotoCompletion() async throws {
        let saving = expectation(description: "Real writer finished before Photos boundary")
        var resumeSave: CheckedContinuation<Void, Never>?
        let recorder = WebViewRecorder(stopCapture: {}, saveToPhotos: { url in
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            saving.fulfill()
            await withCheckedContinuation { resumeSave = $0 }
        })
        let url = try await prepareVideo(recorder)
        recorder.stopRecording()
        XCTAssertEqual(recorder.state, .finishing)
        XCTAssertNil(recorder.lastResult)
        await fulfillment(of: [saving], timeout: 10)
        XCTAssertNil(recorder.lastResult)
        XCTAssertEqual(recorder.state, .finishing)
        resumeSave?.resume()
        await waitForIdle(recorder)
        XCTAssertEqual(recorder.lastResult, .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(recorder.failedOutputURL)
    }

    func testPhotoFailureKeepsFinishedVideoAndReportsFailure() async throws {
        let recorder = WebViewRecorder(stopCapture: {}, saveToPhotos: { _ in
            throw NSError(domain: "PhotosFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Storage full"])
        })
        let url = try await prepareVideo(recorder)
        recorder.stopRecording()
        await waitForIdle(recorder)
        guard case .failed(let message) = recorder.lastResult else { return XCTFail("Expected save failure") }
        XCTAssertTrue(message.contains("Storage full"))
        XCTAssertEqual(recorder.failedOutputURL, url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testDisconnectDiscardsAgentVideoEvenWhenPhotoSaveFails() async throws {
        let saving = expectation(description: "Photos operation in progress")
        var finishSave: CheckedContinuation<Void, Never>?
        let recorder = WebViewRecorder(stopCapture: {}, saveToPhotos: { _ in
            saving.fulfill()
            await withCheckedContinuation { finishSave = $0 }
            throw NSError(domain: "PhotosFixture", code: 1)
        })
        let url = try await prepareVideo(recorder, retainForAgent: true)
        recorder.stopRecording()
        await fulfillment(of: [saving], timeout: 10)
        recorder.discardAgentRecording()
        finishSave?.resume()
        await waitForIdle(recorder)
        XCTAssertNil(recorder.agentOutputURL)
        XCTAssertNil(recorder.failedOutputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLeavingWhileCaptureStartsStopsItAsSoonAsStartCompletes() async {
        let starting = expectation(description: "Capture start suspended")
        var resumeStart: CheckedContinuation<Void, Never>?
        var stopCalls = 0
        var saveCalls = 0
        let recorder = WebViewRecorder(startCapture: { _ in
            starting.fulfill()
            await withCheckedContinuation { resumeStart = $0 }
        }, stopCapture: { stopCalls += 1 }, saveToPhotos: { _ in saveCalls += 1 })
        let task = Task { await recorder.startRecording() }
        await fulfillment(of: [starting], timeout: 2)
        XCTAssertEqual(recorder.state, .starting)
        recorder.stopRecording()
        resumeStart?.resume()
        let started = await task.value
        XCTAssertTrue(started)
        await waitForIdle(recorder)
        XCTAssertEqual(stopCalls, 1)
        XCTAssertEqual(saveCalls, 0)
        guard case .failed = recorder.lastResult else { return XCTFail("Empty captures must never claim success") }
    }

    func testStartFailureReturnsToIdleWithoutClaimingSaved() async {
        let recorder = WebViewRecorder(startCapture: { _ in
            throw NSError(domain: "CaptureFixture", code: 1)
        })
        let started = await recorder.startRecording()
        XCTAssertFalse(started)
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertNil(recorder.lastResult)
    }

    private func prepareVideo(_ recorder: WebViewRecorder, retainForAgent: Bool = false) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("walnut-recording-\(UUID()).mov")
        outputFiles.append(url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        for _ in 0..<100 {
            if input.isReadyForMoreMediaData { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: .zero))
        recorder.test_prepareRecording(writer: writer, input: input, url: url, retainForAgent: retainForAgent)
        return url
    }

    private func waitForIdle(_ recorder: WebViewRecorder) async {
        for _ in 0..<500 {
            if recorder.state == .idle { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Recording never completed")
    }
}
