import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copyFeedback = CopiedFeedbackState()
    @State private var showPairingCode = false
    @State private var pairingFile: AgentPairingFile?
    @State private var pairingShareFailed = false
    let session: AgentSession
    let start: () -> Void

    private static let installCommands = """
    brew tap kobbokkom/tap
    brew install --cask kobbokkom/tap/walnut-agent
    """
    private static let setupGuide = URL(string: "https://github.com/Kobbokkom/walnut-webview-tester/tree/main/walnut-agent#install-on-mac")!

    var body: some View {
        @Bindable var feedback = copyFeedback
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !session.isRunning {
                        installSection
                    }
                    connectionSection
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Mac Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .copiedFeedbackOverlay($feedback.message)
        .sheet(item: $pairingFile) { file in
            ShareSheet(fileURL: file.url)
                .onDisappear { file.remove() }
        }
        .alert("Could not prepare pairing file", isPresented: $pairingShareFailed) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: session.pairingCode) { _, _ in
            showPairingCode = false
            clearPairingFile()
        }
        .onChange(of: session.isConnected) { _, connected in
            if connected {
                showPairingCode = false
                clearPairingFile()
            }
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Install on Mac")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Run these commands in Terminal on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("Homebrew", systemImage: "terminal")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = Self.installCommands
                        copyFeedback.show("Install commands copied")
                        UIAccessibility.post(notification: .announcement, argument: String(localized: "Install commands copied"))
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Copy Homebrew commands")
                }
                Divider()
                Text(verbatim: Self.installCommands)
                    .font(.footnote.monospaced())
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            ShareLink(item: Self.setupGuide) {
                Label("Share Mac setup guide", systemImage: "square.and.arrow.up")
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your Mac")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if session.isRunning {
                if session.isConnected {
                    Label("Mac connected", systemImage: "checkmark.circle.fill")
                } else if let code = session.pairingCode {
                    pairingOptions(code)
                    Text("After pairing, ask your coding agent to use Walnut or run `walnut-agent session` in Terminal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if session.connectionError == nil {
                    ProgressView("Starting connection")
                }
                Button("Stop connection", role: .destructive) { session.stop() }
                    .buttonStyle(.bordered)
            } else {
                Text("For Wi-Fi, connect your iPhone and Mac to the same network.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: start) {
                    Label("Start connection", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("Diagnostics and approved data go to your Mac and may reach its AI service.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = session.connectionError {
                Text(error)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("Connection details") {
                Text("The connected agent can navigate and reload test pages using your log retention settings. Walnut stops the connection when you turn it off or leave the app.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.footnote)
        }
    }

    private func pairingOptions(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On the Mac, run walnut-agent pair and paste the code. Keep the code private.")
                .font(.subheadline)
            Button {
                UIPasteboard.general.setItems(
                    [[UTType.plainText.identifier: code]],
                    options: [.expirationDate: Date().addingTimeInterval(120)]
                )
                copyFeedback.show("Pairing code copied")
                UIAccessibility.post(notification: .announcement, argument: String(localized: "Pairing code copied"))
            } label: {
                Label("Copy pairing code", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                do {
                    clearPairingFile()
                    pairingFile = try AgentPairingFile(code: code)
                } catch {
                    pairingShareFailed = true
                }
            } label: {
                Label("Share pairing file", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Text("If clipboard sharing is unavailable, AirDrop the pairing file to your Mac while keeping Walnut open.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: "walnut-agent pair --file")
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("In Terminal, type this command followed by a space, drag in the file you just received, and press Return.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            DisclosureGroup("Show pairing code", isExpanded: $showPairingCode) {
                Text(verbatim: code)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .font(.footnote)
            Text("The code and file allow a Mac to connect to this session. Share only with your Mac. Stopping the connection or leaving Walnut invalidates them. Delete the received file after pairing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func clearPairingFile() {
        pairingFile?.remove()
        pairingFile = nil
    }
}

extension EnvironmentValues {
    @Entry var agentBrowserSettings: AgentBrowserSettings?
}

private struct AgentApprovalView: View {
    let request: AgentApprovalGate.Request
    let resolve: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: request.message).textSelection(.enabled)
                    if let preview = request.preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .accessibilityLabel("Screenshot preview")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Allow Mac Agent action?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny") { resolve(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allow") { resolve(true) }
                }
            }
        }
    }
}

struct BrowserSheetPresenter: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    let request: () -> AgentApprovalGate.Request?
    let resolve: (UUID, Bool) -> Void
    let showsCallback: () -> Bool
    let dismissCallback: () -> Void
    var onSceneExit: () -> Void = {}
    var onWindowAttached: (UIWindow) -> Void = { _ in }

    func makeUIViewController(context: Context) -> Presenter { Presenter() }

    func updateUIViewController(_ controller: Presenter, context: Context) {
        controller.update(self)
    }

    static func dismantleUIViewController(_ controller: Presenter, coordinator: ()) {
        controller.detachFromScene()
    }

    final class Presenter: UIViewController, UISheetPresentationControllerDelegate {
        private final class WindowAnchor: UIView {
            var didAttach: ((UIWindow) -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if let window { didAttach?(window) }
            }
        }

        private var request: AgentApprovalGate.Request?
        private var requestProvider: (() -> AgentApprovalGate.Request?)?
        private var resolve: ((UUID, Bool) -> Void)?
        private var showsCallback = false
        private var callbackProvider: (() -> Bool)?
        private var dismissCallback: (() -> Void)?
        private var onSceneExit: (() -> Void)?
        private var onWindowAttached: ((UIWindow) -> Void)?
        private var locale = Locale.current
        private weak var sceneWindow: UIWindow?
        private weak var observedScene: UIWindowScene?
        private var approval: (id: UUID, controller: UIViewController)?
        private var callback: UIViewController?
        private var transitioning = false

        override func loadView() {
            let anchor = WindowAnchor()
            anchor.didAttach = { [weak self] window in self?.attach(to: window) }
            view = anchor
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if let window = view.window { attach(to: window) }
            reconcile()
        }

        func update(_ input: BrowserSheetPresenter) {
            let needsObservation = requestProvider == nil
            requestProvider = input.request
            resolve = input.resolve
            callbackProvider = input.showsCallback
            dismissCallback = input.dismissCallback
            onSceneExit = input.onSceneExit
            onWindowAttached = input.onWindowAttached
            locale = input.locale
            // Safari's full-screen presentation temporarily detaches this view from its window.
            if let window = viewIfLoaded?.window { attach(to: window) }
            if needsObservation { observeRequests() } else { reconcile() }
        }

        private func attach(to window: UIWindow) {
            sceneWindow = window
            onWindowAttached?(window)
            guard let scene = window.windowScene, scene !== observedScene else { return }
            let notification = UIScene.didEnterBackgroundNotification
            NotificationCenter.default.removeObserver(self, name: notification, object: observedScene)
            NotificationCenter.default.addObserver(self, selector: #selector(sceneDidEnterBackground), name: notification, object: scene)
            observedScene = scene
        }

        @objc private func sceneDidEnterBackground(_: Notification) { onSceneExit?() }

        func detachFromScene() {
            NotificationCenter.default.removeObserver(self, name: UIScene.didEnterBackgroundNotification, object: observedScene)
            requestProvider = nil
            callbackProvider = nil
            let exit = onSceneExit
            onSceneExit = nil
            Task { @MainActor in exit?() }
        }

        private func observeRequests() {
            // UIKit keeps its presentation even while the SwiftUI host stops updating.
            (request, showsCallback) = withObservationTracking {
                (requestProvider?(), callbackProvider?() ?? false)
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.observeRequests() }
            }
            reconcile()
        }

        private func reconcile() {
            guard !transitioning else { return }
            if let approval {
                if approval.controller.presentingViewController != nil {
                    if request?.id != approval.id {
                        dismiss(approval.controller) { [weak self] in self?.approval = nil }
                    }
                    return
                }
                self.approval = nil
                if request?.id == approval.id {
                    request = nil
                    resolve?(approval.id, false)
                }
            }
            if callback?.presentingViewController == nil { callback = nil }
            if let callback, !showsCallback {
                dismiss(callback) { [weak self] in self?.callback = nil }
                return
            }
            guard request != nil || (showsCallback && callback == nil),
                  var host = sceneWindow?.rootViewController else { return }
            while let presented = host.presentedViewController { host = presented }

            transitioning = true
            if let coordinator = host.transitionCoordinator,
               coordinator.animate(alongsideTransition: nil, completion: { [weak self] _ in
                   self?.finishTransition()
               }) { return }

            if let request {
                presentApproval(request, from: host)
            } else {
                presentCallback(from: host)
            }
        }

        private func presentApproval(_ request: AgentApprovalGate.Request, from host: UIViewController) {
            let id = request.id
            let controller = UIHostingController(rootView: AgentApprovalView(request: request) { [weak self] allow in
                self?.choose(id, allow: allow)
            }.environment(\.locale, locale))
            controller.isModalInPresentation = true
            controller.modalPresentationStyle = .formSheet
            approval = (id, controller)
            host.present(controller, animated: true) { [weak self] in self?.finishTransition() }
            if controller.presentingViewController == nil {
                approval = nil
                transitioning = false
                self.request = nil
                resolve?(id, false)
            }
        }

        private func presentCallback(from host: UIViewController) {
            let controller = UIHostingController(rootView: CallbackResultSheet { [weak self] in self?.closeCallback() }
                .environment(\.locale, locale))
            controller.modalPresentationStyle = .formSheet
            if let presentation = controller.sheetPresentationController {
                presentation.detents = [.custom { $0.maximumDetentValue * 0.35 }, .medium(), .large()]
                presentation.selectedDetentIdentifier = host.traitCollection.horizontalSizeClass == .regular ? .large : .medium
                presentation.prefersGrabberVisible = true
                presentation.delegate = self
            }
            callback = controller
            host.present(controller, animated: true) { [weak self] in self?.finishTransition() }
            if controller.presentingViewController == nil {
                callback = nil
                transitioning = false
            }
        }

        private func choose(_ id: UUID, allow: Bool) {
            guard !transitioning, let approval, approval.id == id, request?.id == id else { return }
            // Wait for UIKit to remove the approval sheet before the action captures the app window.
            dismiss(approval.controller) { [weak self] in
                guard let self else { return }
                self.approval = nil
                guard self.request?.id == id else { return }
                self.request = nil
                self.resolve?(id, allow)
            }
        }

        private func closeCallback() {
            guard !transitioning, approval == nil, let callback else { return }
            dismiss(callback) { [weak self] in self?.callbackClosed() }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard callback === presentationController.presentedViewController else { return }
            callbackClosed()
            reconcile()
        }

        private func callbackClosed() {
            callback = nil
            showsCallback = false
            dismissCallback?()
        }

        private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
            transitioning = true
            let finish = { [weak self] in
                completion()
                self?.finishTransition()
            }
            if controller.presentingViewController != nil {
                controller.dismiss(animated: true, completion: finish)
            } else {
                finish()
            }
        }

        private func finishTransition() {
            transitioning = false
            reconcile()
        }
    }
}
