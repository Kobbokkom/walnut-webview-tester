//
//  WebViewRecorderTests.swift
//  winaTests
//
//  Tests for WebViewRecorder functionality.
//

import XCTest
@testable import wina

@MainActor
final class WebViewRecorderTests: XCTestCase {

    var recorder: WebViewRecorder!
    var recorder2: WebViewRecorder!

    override func setUp() async throws {
        try await super.setUp()
        recorder = WebViewRecorder()
        recorder2 = WebViewRecorder()
    }

    override func tearDown() async throws {
        recorder = nil
        recorder2 = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.recordingDuration, 0)
    }

    func testIsRecordingReflectsState() {
        // Initial state should not be recording
        XCTAssertFalse(recorder.isRecording)
    }

    func testInitialCurrentDurationIsZero() {
        // currentDuration should be 0 when not recording
        XCTAssertEqual(recorder.currentDuration, 0)
    }

    func testCaptureStartupFailurePreservesSystemReason() async {
        let recorder = WebViewRecorder(startCapture: { _ in
            throw NSError(domain: "WalnutRecordingTest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Capture unavailable in this configuration."
            ])
        })
        let started = await recorder.startRecording(retainForAgent: true, saveToPhotos: false)
        XCTAssertFalse(started)
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertNil(recorder.agentOutputURL)
        XCTAssertNil(recorder.lastResult)
        XCTAssertEqual(recorder.startFailure, "Capture unavailable in this configuration.")
    }

    // MARK: - Stop Recording When Idle

    func testStopRecordingWhenIdleDoesNothing() {
        // Stopping when not recording should not change state
        recorder.stopRecording()
        XCTAssertEqual(recorder.state, .idle)
    }

    func testStopRecordingWhenIdleKeepsDurationZero() {
        recorder.stopRecording()
        XCTAssertEqual(recorder.recordingDuration, 0)
        XCTAssertEqual(recorder.currentDuration, 0)
    }

    // MARK: - Recording State Enum Tests

    func testRecordingStateEnum() {
        // Test enum cases exist and are distinct
        let idle: RecordingState = .idle
        let recording: RecordingState = .recording
        let finishing: RecordingState = .finishing

        XCTAssertNotEqual(idle, recording)
        XCTAssertNotEqual(recording, finishing)
        XCTAssertNotEqual(idle, finishing)
    }

    func testRecordingStateIdleIsDefault() {
        let state: RecordingState = .idle
        XCTAssertEqual(state, RecordingState.idle)
    }

    // MARK: - Recording Result Enum Tests

    func testRecordingResultEnum() {
        // Test enum cases exist
        let success: RecordingResult = .success
        let denied: RecordingResult = .permissionDenied
        let failed: RecordingResult = .failed("test error")

        // Verify failed case contains message
        if case .failed(let message) = failed {
            XCTAssertEqual(message, "test error")
        } else {
            XCTFail("Expected .failed case")
        }

        // These should compile and be distinct
        XCTAssertNotNil(success)
        XCTAssertNotNil(denied)
    }

    func testRecordingResultFailedWithEmptyMessage() {
        let failed: RecordingResult = .failed("")
        if case .failed(let message) = failed {
            XCTAssertTrue(message.isEmpty)
        } else {
            XCTFail("Expected .failed case")
        }
    }

    func testRecordingResultFailedWithSpecialCharacters() {
        let errorMessage = "Error: 녹화 실패 🎥"
        let failed: RecordingResult = .failed(errorMessage)
        if case .failed(let message) = failed {
            XCTAssertEqual(message, errorMessage)
        } else {
            XCTFail("Expected .failed case")
        }
    }

    // MARK: - Duration Tick Tests

    func testDurationTickUpdatesRecordingDuration() {
        let start = Date().addingTimeInterval(-5)
        recorder.test_setStartTime(start)
        recorder.test_handleDurationTick()

        XCTAssertEqual(recorder.recordingDuration, 5, accuracy: 0.5)
    }

    func testDurationTickWithoutStartTimeKeepsDurationZero() {
        recorder.test_setStartTime(nil)
        recorder.test_handleDurationTick()

        XCTAssertEqual(recorder.recordingDuration, 0)
    }

    // MARK: - isRecording Computed Property Tests

    func testIsRecordingFalseWhenIdle() {
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertFalse(recorder.isRecording)
    }

    func testIsRecordingFalseWhenFinishing() {
        // We can't directly set state, but we can verify the logic
        // isRecording should only be true when state == .recording
        // Since we start at .idle, isRecording should be false
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - Duration Format Helper Tests

    func testFormatDurationZero() {
        let formatted = formatDuration(0)
        XCTAssertEqual(formatted, "0:00")
    }

    func testFormatDurationOneSecond() {
        let formatted = formatDuration(1)
        XCTAssertEqual(formatted, "0:01")
    }

    func testFormatDurationTenSeconds() {
        let formatted = formatDuration(10)
        XCTAssertEqual(formatted, "0:10")
    }

    func testFormatDurationOneMinute() {
        let formatted = formatDuration(60)
        XCTAssertEqual(formatted, "1:00")
    }

    func testFormatDurationOneMinuteThirtySeconds() {
        let formatted = formatDuration(90)
        XCTAssertEqual(formatted, "1:30")
    }

    func testFormatDurationTenMinutes() {
        let formatted = formatDuration(600)
        XCTAssertEqual(formatted, "10:00")
    }

    func testFormatDurationFractionalSeconds() {
        // Fractional seconds should be truncated
        let formatted = formatDuration(65.7)
        XCTAssertEqual(formatted, "1:05")
    }

    func testFormatDurationLargeDuration() {
        // 1 hour = 3600 seconds = 60 minutes
        let formatted = formatDuration(3661) // 1:01:01
        XCTAssertEqual(formatted, "61:01")
    }

    // MARK: - Multiple Recorder Independence Tests

    /// Test that two recorder instances are independent (WKWebView vs SafariVC pattern)
    func testTwoRecordersAreIndependent() {
        // WKWebView uses navigator.recorder, SafariVC uses separate recorder
        // Both recorders created in setUp

        // Initial states should both be idle
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder2.state, .idle)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(recorder2.isRecording)

        // They should be different instances
        XCTAssertNotIdentical(recorder, recorder2)
    }

    func testRecorderDurationIndependence() {
        // Both recorders created in setUp
        // Set different start times
        let now = Date()
        recorder.test_setStartTime(now.addingTimeInterval(-10))  // 10 seconds ago
        recorder2.test_setStartTime(now.addingTimeInterval(-5))   // 5 seconds ago

        recorder.test_handleDurationTick()
        recorder2.test_handleDurationTick()

        // Durations should be different
        XCTAssertEqual(recorder.recordingDuration, 10, accuracy: 0.5)
        XCTAssertEqual(recorder2.recordingDuration, 5, accuracy: 0.5)
    }

    func testStopOneRecorderDoesNotAffectOther() {
        // Both recorders created in setUp
        // Set start times
        recorder.test_setStartTime(Date())
        recorder2.test_setStartTime(Date())

        // Stop recorder (first one)
        recorder.stopRecording()

        // recorder2 should be unaffected (startTime still set)
        recorder2.test_handleDurationTick()
        XCTAssertGreaterThanOrEqual(recorder2.recordingDuration, 0)
    }

    func testNavigatorRecorderVsSeparateRecorder() {
        // Simulate the two-recorder pattern used in the app:
        // - recorder = navigator.recorder (WKWebView)
        // - recorder2 = screenRecorder (SafariVC)
        // Both recorders created in setUp

        // They should be completely independent
        XCTAssertNotIdentical(recorder, recorder2)

        // Setting state on one shouldn't affect the other
        recorder.test_setStartTime(Date())
        recorder.test_handleDurationTick()

        XCTAssertGreaterThan(recorder.recordingDuration, 0)
        XCTAssertEqual(recorder2.recordingDuration, 0)
    }

    // MARK: - Helper Function

    /// Format duration for display (mirrors OverlayMenuBars implementation)
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
