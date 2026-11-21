import SwiftUI

@Observable
final class ConsoleSheetPresentation {
    fileprivate(set) var isAttached = false
    @ObservationIgnored fileprivate var resumePendingPresentation: (() -> Void)?

    func siblingSheetDidDismiss() {
        resumePendingPresentation?()
    }

    func deferUntilDismissed(_ binding: Binding<Bool>) -> Binding<Bool> {
        isAttached ? .constant(false) : binding
    }
}

extension View {
    @ViewBuilder
    func consoleSheet<Content: View>(
        isPresented: Binding<Bool>,
        presentation: ConsoleSheetPresentation,
        colorScheme: ColorScheme?,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .phone {
            // SwiftUI's sheet can hang during phone rotation after the Console keyboard is dismissed.
            background {
                ConsoleSheetAnchor(
                    isPresented: isPresented, presentation: presentation, colorScheme: colorScheme, content: content()
                )
                    .frame(width: 0, height: 0)
            }
        } else {
            sheet(isPresented: isPresented) {
                content().devToolsSheet().preferredColorScheme(colorScheme)
            }
        }
    }
}

private struct ConsoleSheetAnchor<Content: View>: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Binding var isPresented: Bool
    let presentation: ConsoleSheetPresentation
    let colorScheme: ColorScheme?
    let content: Content

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.didAttach = { [weak coordinator = context.coordinator] in coordinator?.scheduleUpdate() }
        return anchor
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: Anchor, context: Context) {
        // Track the requested sheet while UIKit presents it outside the SwiftUI hierarchy.
        _ = isPresented
        let coordinator = context.coordinator
        let binding = $isPresented
        let hostedContent = AnyView(content.environment(\.locale, locale)
            .environment(\.closeDevTools, { binding.wrappedValue = false }))
        coordinator.update(self, content: hostedContent, from: view)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Anchor: UIView {
        var didAttach: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { didAttach?() }
        }
    }

    final class Coordinator: NSObject, UISheetPresentationControllerDelegate {
        private weak var anchor: UIView?
        private var isPresented: Binding<Bool>?
        private var presentation: ConsoleSheetPresentation?
        private var content: AnyView?
        private var colorScheme: ColorScheme?
        private var host: ConsoleHost?
        private var transitioning = false
        private var updateScheduled = false

        func update(_ input: ConsoleSheetAnchor, content: AnyView, from anchor: UIView) {
            self.anchor = anchor
            isPresented = input.$isPresented
            presentation = input.presentation
            self.content = content
            colorScheme = input.colorScheme
            input.presentation.resumePendingPresentation = { [weak self] in self?.scheduleUpdate() }
            scheduleUpdate()
        }

        func detach() {
            anchor = nil
            isPresented = nil
            presentation?.resumePendingPresentation = nil
            content = nil
            host?.presentingViewController?.dismiss(animated: false)
            host = nil
            Task { @MainActor [presentation] in presentation?.isAttached = false }
            presentation = nil
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                updateScheduled = false
                updatePresentation()
            }
        }

        private func updatePresentation() {
            guard !transitioning else { return }
            if let host, host.presentingViewController == nil { finishDismissal() }
            guard isPresented?.wrappedValue == true, let content else {
                guard let host, let presenter = host.presentingViewController, !waitForTransition(of: host) else { return }
                transitioning = true
                presenter.dismiss(animated: true) { [weak self] in
                    self?.finishDismissal()
                    self?.finishTransition()
                }
                return
            }

            let style = colorScheme.map { $0 == .dark ? UIUserInterfaceStyle.dark : .light } ?? .unspecified
            if let host {
                host.rootView = content
                host.overrideUserInterfaceStyle = style
                return
            }

            guard let presenter = anchor?.window?.rootViewController else { return }
            if let presented = presenter.presentedViewController {
                _ = waitForTransition(of: presented)
                return
            }

            let host = ConsoleHost(rootView: content)
            host.overrideUserInterfaceStyle = style
            host.modalPresentationStyle = .formSheet
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.custom { $0.maximumDetentValue * BarConstants.compactSheetFraction }, .medium(), .large()]
                let traits = presenter.traitCollection
                sheet.selectedDetentIdentifier = traits.horizontalSizeClass == .regular || traits.verticalSizeClass == .compact
                    ? .large : .medium
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                sheet.prefersGrabberVisible = true
                sheet.largestUndimmedDetentIdentifier = .medium
                sheet.delegate = self
            }
            self.host = host
            transitioning = true
            presenter.present(host, animated: true) { [weak self] in self?.finishTransition() }
            if host.presentingViewController == nil {
                self.host = nil
                transitioning = false
                if let presented = presenter.presentedViewController { _ = waitForTransition(of: presented) }
                return
            }
            presentation?.isAttached = true
        }

        private func waitForTransition(of controller: UIViewController) -> Bool {
            guard let coordinator = controller.transitionCoordinator else { return false }
            transitioning = coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.finishTransition() }
            return transitioning
        }

        private func finishTransition() {
            transitioning = false
            scheduleUpdate()
        }

        private func finishDismissal() {
            host = nil
            presentation?.isAttached = false
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard presentationController.presentedViewController === host else { return }
            isPresented?.wrappedValue = false
            finishDismissal()
        }
    }

    private final class ConsoleHost: UIHostingController<AnyView> {
        override var childForStatusBarHidden: UIViewController? { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            NotificationCenter.default.addObserver(
                self, selector: #selector(expandForKeyboard), name: UIResponder.keyboardWillShowNotification, object: nil
            )
        }

        @objc private func expandForKeyboard() {
            guard let sheet = sheetPresentationController, sheet.selectedDetentIdentifier != .large else { return }
            sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
        }
    }
}
