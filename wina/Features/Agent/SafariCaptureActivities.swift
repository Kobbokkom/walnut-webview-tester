import AudioToolbox
import AVFoundation
import Observation
import SafariServices
import UIKit

@MainActor
enum SafariCaptureActivities {
    static func make(
        for controller: SFSafariViewController,
        recorder: WebViewRecorder,
        locale: Locale = .current,
        stopMacAgent: (() -> Void)? = nil,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> [UIActivity] {
        var actions: [CaptureActivity.Action] = AgentCapture.safariScreenshotUnavailableReason == nil ? [.screenshot] : []
        switch recorder.state {
        case .idle: actions.append(.startRecording)
        case .starting, .recording: actions.append(.stopRecording)
        case .finishing: break
        }
        if stopMacAgent != nil { actions.append(.stopMacAgent) }
        return actions.map {
            CaptureActivity($0, controller: controller, recorder: recorder, locale: locale, stopMacAgent: stopMacAgent, isCurrent: isCurrent)
        }
    }
}

private final class CaptureActivity: UIActivity {
    enum Action: String {
        case screenshot, startRecording, stopRecording, stopMacAgent

        var title: String.LocalizationValue {
            switch self {
            case .screenshot: "Save Screenshot"
            case .startRecording: "Start Recording"
            case .stopRecording: "Stop Recording"
            case .stopMacAgent: "Stop Mac Agent"
            }
        }

        var icon: String {
            switch self {
            case .screenshot: "camera"
            case .startRecording: "record.circle"
            case .stopRecording: "stop.circle"
            case .stopMacAgent: "network.slash"
            }
        }
    }

    private let action: Action
    private weak var controller: SFSafariViewController?
    private let recorder: WebViewRecorder
    private let locale: Locale
    private let stopMacAgent: (() -> Void)?
    private let isCurrent: @MainActor () -> Bool

    init(
        _ action: Action,
        controller: SFSafariViewController,
        recorder: WebViewRecorder,
        locale: Locale,
        stopMacAgent: (() -> Void)?,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        self.action = action
        self.controller = controller
        self.recorder = recorder
        self.locale = locale
        self.stopMacAgent = stopMacAgent
        self.isCurrent = isCurrent
        super.init()
    }

    override static var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.kobbokkom.wina.safari.\(action.rawValue)") }
    override var activityTitle: String? { localized(action.title) }
    override var activityImage: UIImage? { UIImage(systemName: action.icon) }
    override func canPerform(withActivityItems _: [Any]) -> Bool {
        MainActor.assumeIsolated {
            controller != nil && (action != .screenshot || AgentCapture.safariScreenshotUnavailableReason == nil)
        }
    }
    override func prepare(withActivityItems _: [Any]) {}

    override func perform() {
        MainActor.assumeIsolated {
            guard let window = controller?.viewIfLoaded?.window, isCurrent() else {
                activityDidFinish(false)
                return
            }
            if action == .stopMacAgent {
                stopMacAgent?()
                activityDidFinish(true)
                return
            }
            // Complete the handoff to Walnut so the share sheet leaves before any capture or permission prompt.
            activityDidFinish(true)
            Task { await capture(in: window) }
        }
    }

    @MainActor
    private func capture(in window: UIWindow) async {
        guard await waitForSafari(in: window) else { return }
        switch action {
        case .stopRecording:
            await stopRecording(in: window)
        case .screenshot:
            await saveScreenshot(in: window)
        case .startRecording:
            guard await authorizePhotos(in: window), recorder.state == .idle else { return }
            let started = await recorder.startRecording()
            guard isCurrent(), controller?.viewIfLoaded?.window === window else {
                if started { recorder.stopRecording() }
                return
            }
            if !started, await waitForSafari(in: window) {
                showFeedback(localized("Screen Recording Unavailable"), message: recorder.startFailure)
            }
        case .stopMacAgent:
            break
        }
    }

    @MainActor
    private func authorizePhotos(in window: UIWindow) async -> Bool {
        do {
            try await AgentCapture.requirePhotos()
            return await waitForSafari(in: window)
        } catch {
            if await waitForSafari(in: window) {
                showFeedback(
                    localized("Photo Access Required"),
                    message: localized("Allow Walnut to add to Photos in Settings."),
                    settings: true
                )
            }
            return false
        }
    }

    @MainActor
    private func saveScreenshot(in window: UIWindow) async {
        do {
            let image = try await AgentCapture.captureSafariDisplay(in: window) { [weak self] in
                guard self?.isSafariReady(in: window) == true else {
                    throw AgentError("The SafariVC window is no longer active.")
                }
            }
            guard WebViewNavigator.hasVisiblePixels(image), isSafariReady(in: window) else {
                throw AgentError("iOS did not capture visible pixels from the display.")
            }
            guard await authorizePhotos(in: window) else { return }
            AudioServicesPlaySystemSound(1108)
            try await AgentCapture.savePhoto(image)
            if await waitForSafari(in: window) { showFeedback(localized("Saved to Photos")) }
        } catch {
            if await waitForSafari(in: window) {
                showFeedback(localized("Screenshot Not Saved"), message: error.localizedDescription)
            }
        }
    }

    @MainActor
    private func stopRecording(in window: UIWindow) async {
        recorder.stopRecording()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        while recorder.state == .starting || recorder.state == .finishing {
            guard isCurrent(), !Task.isCancelled, clock.now < deadline else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard recorder.state == .idle, let result = recorder.lastResult, await waitForSafari(in: window) else { return }
        switch result {
        case .success: showFeedback(localized("Recording Saved"))
        case .permissionDenied: showFeedback(localized("Photo Access Required"), settings: true)
        case .failed(let message): showFeedback(localized("Recording Not Saved"), message: message)
        }
    }

    @MainActor
    private func waitForSafari(in window: UIWindow) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(4)
        while !Task.isCancelled, clock.now < deadline {
            guard let controller, isCurrent(), !controller.isBeingDismissed,
                  controller.viewIfLoaded?.window === window else { return false }
            if isSafariReady(in: window) { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    @MainActor
    private func isSafariReady(in window: UIWindow) -> Bool {
        guard let controller, isCurrent(), !controller.isBeingDismissed, controller.viewIfLoaded?.window === window,
              controller.transitionCoordinator == nil, window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive else { return false }
        var front = window.rootViewController
        while let next = front?.presentedViewController { front = next }
        return front === controller
    }

    @MainActor
    private func showFeedback(_ title: String, message: String? = nil, settings: Bool = false) {
        guard let controller, isCurrent() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if settings {
            alert.addAction(UIAlertAction(title: localized("Open Settings"), style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            })
        }
        alert.addAction(UIAlertAction(title: localized("OK"), style: .cancel))
        controller.present(alert, animated: true)
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, locale: locale))
    }
}

@MainActor
final class SafariRecordingIndicator {
    private var indicatorWindow: UIWindow?
    private let speaker = AVSpeechSynthesizer()
    private weak var observedRecorder: WebViewRecorder?
    private var observedCaptureView: (() -> UIView?)?
    private var observedLocale = Locale.current

    func observe(recorder: WebViewRecorder, captureView: @escaping () -> UIView?, locale: Locale) {
        observedCaptureView = captureView
        observedLocale = locale
        guard observedRecorder !== recorder else { return }
        observedRecorder = recorder
        observeRecording(recorder)
    }

    private func observeRecording(_ recorder: WebViewRecorder) {
        let recording = withObservationTracking { recorder.isRecording } onChange: { [weak self, weak recorder] in
            Task { @MainActor in
                guard let self, let recorder, self.observedRecorder === recorder else { return }
                self.observeRecording(recorder)
            }
        }
        update(captureView: observedCaptureView?(), isRecording: recording, locale: observedLocale)
    }

    func update(captureView: UIView?, isRecording: Bool, locale: Locale = .current) {
        guard isRecording, let captureView, let host = captureView.window, let scene = host.windowScene else {
            indicatorWindow?.isHidden = true
            indicatorWindow = nil
            speaker.stopSpeaking(at: .immediate)
            return
        }
        guard indicatorWindow == nil else { return }
        let title = String(localized: LocalizedStringResource("Recording", locale: locale))
        let indicator = RecordingIndicatorView(captureView: captureView, title: title) { [weak self] in
            self?.announce(title, locale: locale)
        }
        let content = UIViewController()
        content.view = indicator
        let window = UIWindow(windowScene: scene)
        window.frame = host.frame
        window.windowLevel = .normal + 1
        window.isUserInteractionEnabled = false
        window.rootViewController = content
        indicatorWindow = window
        window.isHidden = false
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: title)
        }
    }

    static func indicatorFrame(in bounds: CGRect, safeArea: UIEdgeInsets, labelSize: CGSize) -> CGRect? {
        let margin: CGFloat = 6
        guard safeArea.bottom >= labelSize.height + 4, safeArea.bottom < bounds.height,
              safeArea.left + margin + labelSize.width <= bounds.width / 4 else { return nil }
        return CGRect(
            x: bounds.minX + safeArea.left + margin,
            y: bounds.maxY - (safeArea.bottom + labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
    }

    private func announce(_ title: String, locale: Locale) {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        speaker.usesApplicationAudioSession = false
        let utterance = AVSpeechUtterance(string: title)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier.replacingOccurrences(of: "_", with: "-"))
        speaker.speak(utterance)
    }
}

private final class RecordingIndicatorView: UIView {
    private weak var captureView: UIView?
    private let onHidden: () -> Void
    private let label = UILabel()
    private var shouldAnnounce = true

    init(captureView: UIView, title: String, onHidden: @escaping () -> Void) {
        self.captureView = captureView
        self.onHidden = onHidden
        super.init(frame: .zero)
        backgroundColor = .clear
        label.text = "  \(title)  "
        label.font = .preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.backgroundColor = UIColor(red: 0.65, green: 0.08, blue: 0.12, alpha: 1)
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.textAlignment = .center
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(captureView:title:onHidden:)") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let captureView, let host = captureView.window else { label.isHidden = true; return }
        var inset = host.safeAreaInsets
        inset.bottom = min(inset.bottom, captureView.safeAreaInsets.bottom)
        let size = label.intrinsicContentSize
        let frame = SafariRecordingIndicator.indicatorFrame(in: bounds, safeArea: inset, labelSize: size)
        label.isHidden = frame == nil
        if let frame { label.frame = frame }
        if frame == nil, shouldAnnounce { onHidden() }
        shouldAnnounce = frame != nil
    }
}
