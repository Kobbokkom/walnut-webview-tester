import SafariServices
import SwiftUI

struct SafariModalPresenter: UIViewControllerRepresentable {
    @Environment(\.agentBrowserSettings) private var agentSettings

    let url: URL?
    var revision: UUID?
    var navigation: AgentNavigation?
    var usesBrowserSettings = true
    var observeRequest: (() -> (url: URL?, revision: UUID?))?
    var observeSettings: (() -> AgentBrowserSettings?)?
    let onDismiss: (UUID?) -> Void
    var activities: ((SFSafariViewController, UUID?) -> [UIActivity])?

    func makeUIViewController(context: Context) -> Presenter { Presenter() }

    func updateUIViewController(_ presenter: Presenter, context: Context) {
        presenter.navigation = navigation
        presenter.onDismiss = onDismiss
        presenter.activities = activities
        presenter.update { configuration() }
    }

    private func configuration() -> Configuration {
        let target = observeRequest?() ?? (url: url, revision: revision)
        let settings: AgentBrowserSettings?
        if !usesBrowserSettings {
            settings = nil
        } else if let observeSettings {
            settings = observeSettings()
        } else {
            settings = agentSettings
        }
        let defaults = UserDefaults.standard
        let entersReader = defaults.bool(forKey: "safariEntersReaderIfAvailable")
        let collapsesBar = defaults.object(forKey: "safariBarCollapsingEnabled") as? Bool ?? true
        let dismissStyle = defaults.integer(forKey: "safariDismissButtonStyle")
        let controlTint = defaults.string(forKey: "safariControlTintColorHex") ?? ""
        let barTint = defaults.string(forKey: "safariBarTintColorHex") ?? ""
        let request = target.url.map {
            Request(
                url: $0,
                revision: target.revision,
                entersReader: usesBrowserSettings && (settings?.value("safariEntersReaderIfAvailable", fallback: entersReader) ?? entersReader),
                collapsesBar: !usesBrowserSettings || (settings?.value("safariBarCollapsingEnabled", fallback: collapsesBar) ?? collapsesBar)
            )
        }
        let control = settings?.value("safariControlTintColorHex", fallback: controlTint) ?? controlTint
        let bar = settings?.value("safariBarTintColorHex", fallback: barTint) ?? barTint
        let style = usesBrowserSettings ? settings?.value("safariDismissButtonStyle", fallback: dismissStyle) ?? dismissStyle : 0
        let appearance = Appearance(
            dismissStyle: style,
            controlTint: usesBrowserSettings ? UIColor(hex: control) : .systemBlue,
            barTint: usesBrowserSettings ? UIColor(hex: bar) : nil
        )
        return Configuration(request: request, appearance: appearance)
    }

    static func dismantleUIViewController(_ presenter: Presenter, coordinator: ()) {
        presenter.dismantle()
    }

    fileprivate struct Configuration {
        let request: Request?
        let appearance: Appearance
    }

    fileprivate struct Request: Equatable {
        let url: URL
        let revision: UUID?
        let entersReader: Bool
        let collapsesBar: Bool

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.url == rhs.url && lhs.revision == rhs.revision
        }
    }

    fileprivate struct Appearance {
        var dismissStyle = 0
        var controlTint: UIColor?
        var barTint: UIColor?

        func apply(to safari: SFSafariViewController) {
            switch dismissStyle {
            case 1: safari.dismissButtonStyle = .close
            case 2: safari.dismissButtonStyle = .cancel
            default: safari.dismissButtonStyle = .done
            }
            if #unavailable(iOS 26.0) {
                safari.preferredControlTintColor = controlTint
                safari.preferredBarTintColor = barTint
            }
        }
    }

    final class Presenter: UIViewController, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private struct Presentation {
            let request: Request
            let controller: SFSafariViewController
            let navigation: AgentNavigation?

            func clearCaptureView() {
                if navigation?.captureController === controller { navigation?.captureController = nil }
            }
        }

        fileprivate weak var navigation: AgentNavigation?
        fileprivate var onDismiss: ((UUID?) -> Void)?
        fileprivate var activities: ((SFSafariViewController, UUID?) -> [UIActivity])?
        private var appearance = Appearance()
        private var readConfiguration: (() -> Configuration)?
        private var observing = false
        private var request: Request?
        private var dismissedRequest: Request?
        private var current: Presentation?
        private weak var nativeDismissal: SFSafariViewController?
        private var transitioning = false
        private var reconciliationScheduled = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            scheduleReconciliation()
        }

        fileprivate func update(_ readConfiguration: @escaping () -> Configuration) {
            self.readConfiguration = readConfiguration
            if observing {
                apply(readConfiguration())
            } else {
                observeConfiguration()
            }
        }

        fileprivate func dismantle() {
            onDismiss = nil
            activities = nil
            readConfiguration = nil
            updateRequest(nil)
        }

        private func observeConfiguration() {
            guard let readConfiguration else { return }
            observing = true
            // UIKit detaches the SwiftUI host during full-screen Safari. Keep tracking its requested page.
            let configuration = withObservationTracking(readConfiguration) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.observing = false
                    self?.observeConfiguration()
                }
            }
            apply(configuration)
        }

        private func apply(_ configuration: Configuration) {
            appearance = configuration.appearance
            updateRequest(configuration.request)
        }

        private func updateRequest(_ request: Request?) {
            if request != dismissedRequest { dismissedRequest = nil }
            self.request = request == dismissedRequest ? nil : request
            scheduleReconciliation()
        }

        private func scheduleReconciliation() {
            guard !reconciliationScheduled else { return }
            reconciliationScheduled = true
            Task { @MainActor in
                reconciliationScheduled = false
                reconcile()
            }
        }

        private func reconcile() {
            guard !transitioning else { return }
            if let current {
                if let host = current.controller.presentingViewController {
                    if nativeDismissal === current.controller {
                        _ = waitForTransition(of: current.controller)
                    } else if current.request == request {
                        appearance.apply(to: current.controller)
                    } else if !waitForTransition(of: current.controller) {
                        dismiss(current, from: host)
                    }
                    return
                }
                notifyUserDismissal(of: current)
                finishDismissal(current)
            }
            guard let request, var host = view.window?.rootViewController else { return }
            while let presented = host.presentedViewController { host = presented }
            guard !waitForTransition(of: host), !(host is SFSafariViewController), !host.isBeingDismissed else { return }
            present(request, from: host)
        }

        private func waitForTransition(of controller: UIViewController) -> Bool {
            guard let coordinator = controller.transitionCoordinator else { return false }
            transitioning = true
            if coordinator.animate(alongsideTransition: nil, completion: { _ in
                self.transitionCompleted()
            }) { return true }
            transitioning = false
            return false
        }

        private func present(_ request: Request, from host: UIViewController) {
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = request.entersReader
            configuration.barCollapsingEnabled = request.collapsesBar
            let safari = SFSafariViewController(url: request.url, configuration: configuration)
            safari.delegate = self
            safari.presentationController?.delegate = self
            appearance.apply(to: safari)
            current = Presentation(request: request, controller: safari, navigation: navigation)
            navigation?.start(safari, url: request.url)
            navigation?.captureController = safari

            transitioning = true
            host.present(safari, animated: true) {
                self.transitionCompleted()
            }
            if safari.presentingViewController == nil {
                navigation?.finish(safari, url: nil, error: URLError(.cannotLoadFromNetwork))
                current?.clearCaptureView()
                current = nil
                transitioning = false
            }
        }

        private func dismiss(_ presentation: Presentation, from host: UIViewController) {
            presentation.clearCaptureView()
            transitioning = true
            host.dismiss(animated: true) {
                self.finishDismissal(presentation)
                self.transitionCompleted()
            }
        }

        private func finishDismissal(_ presentation: Presentation) {
            guard current?.controller === presentation.controller, presentation.controller.presentingViewController == nil else { return }
            presentation.navigation?.dismiss(presentation.controller)
            current = nil
        }

        private func transitionCompleted() {
            transitioning = false
            scheduleReconciliation()
        }

        private func active(_ controller: SFSafariViewController) -> Presentation? {
            guard let current, current.controller === controller, current.request == request else { return nil }
            return current
        }

        func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo url: URL) {
            active(controller)?.navigation?.redirect(controller, url: url)
        }

        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            let error = didLoadSuccessfully ? nil : URLError(.cannotLoadFromNetwork)
            active(controller)?.navigation?.finish(controller, url: nil, error: error)
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            // Safari dismisses the controller after notifying the delegate.
            handleUserDismissal(controller)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard let safari = presentationController.presentedViewController as? SFSafariViewController else { return }
            handleUserDismissal(safari)
        }

        private func handleUserDismissal(_ controller: SFSafariViewController) {
            guard let current, current.controller === controller, nativeDismissal !== controller else {
                scheduleReconciliation()
                return
            }
            nativeDismissal = controller
            current.clearCaptureView()
            notifyUserDismissal(of: current)
            scheduleReconciliation()
        }

        private func notifyUserDismissal(of presentation: Presentation) {
            guard presentation.request == request else { return }
            dismissedRequest = request
            request = nil
            onDismiss?(presentation.request.revision)
        }

        func safariViewController(
            _ controller: SFSafariViewController, activityItemsFor url: URL, title: String?
        ) -> [UIActivity] {
            guard let presentation = active(controller) else { return [] }
            return activities?(controller, presentation.request.revision) ?? []
        }
    }
}
