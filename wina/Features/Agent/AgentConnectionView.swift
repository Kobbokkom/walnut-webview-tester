import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AgentSession.autoConnectKey) private var autoConnect = false
    @State private var copyFeedback = CopiedFeedbackState()
    @State private var showPairingFileOptions = false
    @State private var showInstallOptions = false
    @State private var showUSBOptions = false
    @AccessibilityFocusState private var focusNewCode: Bool
    @State private var pairingFile: AgentPairingFile?
    @State private var pairingShareFailed = false
    @State private var confirmForgetMac = false
    let session: AgentSession
    let start: (_ rememberedOnly: Bool) -> Void

    static let installCommands = """
    brew tap kobbokkom/tap
    brew install --cask kobbokkom/tap/walnut-agent
    """
    private static let setupGuide = URL(string: "https://github.com/Kobbokkom/walnut-webview-tester/tree/walnut-agent-v0.1.4/walnut-agent#install-on-mac")!

    var body: some View {
        @Bindable var feedback = copyFeedback
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionSection
                    connectionOptions
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
        .alert("Forget this Mac?", isPresented: $confirmForgetMac) {
            Button("Forget Mac", role: .destructive) { session.forgetRememberedMac() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current connection will end. Pair again to use this Mac.")
        }
        .onAppear { session.refreshRememberedMac() }
        .onChange(of: session.pairingCode) { _, _ in
            showPairingFileOptions = false
            clearPairingFile()
        }
        .onChange(of: session.isConnected) { _, connected in
            if connected {
                showPairingFileOptions = false
                clearPairingFile()
                announce("Mac connected")
            }
        }
        .onChange(of: session.isPairingAvailable) { wasAvailable, isAvailable in
            if isAvailable {
                announce("Ready to pair")
            } else if wasAvailable, session.isRunning, !session.isConnected, !session.hasPairingGrant {
                announce("Start pairing again to connect a Mac.")
                focusNewCode = true
            }
        }
        .onChange(of: session.hasPairingGrant) { _, granted in
            if granted { announce("Mac paired") }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.isConnected {
                Label("Mac connected", systemImage: "checkmark.circle.fill")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Keep Walnut open while your Mac uses it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect your Mac")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                connectionStatus
            }
            if let error = session.pairingStorageError ?? session.reconnectError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }
            if session.isRunning {
                Button(role: .destructive) { session.stopManually() } label: {
                    Label("Stop connection", systemImage: "stop.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 30))
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if session.isPairingAvailable {
            Text("Run this command in Terminal on your Mac.")
                .font(.subheadline)
            commandRow("walnut-agent pair")
            Text("Approve only if the confirmation number matches your Mac.")
                .font(.footnote)
            if let name = session.pairingDeviceName {
                Text("Pairing name: \(name)")
                    .font(.caption.monospaced())
            }
        } else if session.isRunning, session.isPairingReady {
            Label("Mac paired", systemImage: "checkmark.circle.fill")
                .font(.headline)
            Text("Start a session in Terminal or ask your coding agent to use Walnut.")
                .font(.subheadline)
            commandRow("walnut-agent session")
        } else if session.pairingCode != nil, !session.hasRememberedMac {
            if let error = session.pairingError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            } else {
                Text("Start pairing again to connect a Mac.")
                    .font(.subheadline)
            }
            Button("Start pairing again") { session.startPairing() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityFocused($focusNewCode)
        } else if session.isRunning {
            if session.reconnectError == nil {
                ProgressView("Starting connection")
            }
        } else {
            if session.hasRememberedMac {
                Label("Mac paired", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                Text("Start the connection to use your saved pairing.")
                    .font(.subheadline)
            } else {
                Text("Use the same Wi-Fi network or connect your iPhone to your Mac by USB.")
                    .font(.subheadline)
            }
            if session.pairingStorageError == nil, let error = session.connectionError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }
            Button { start(false) } label: {
                Label("Start connection", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("Diagnostics and approved data go to your Mac and may reach its AI service.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $showUSBOptions) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect and unlock your iPhone. Install the USB helper on your Mac, then run the pairing command.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    commandRow("brew install libusbmuxd")
                    commandRow("walnut-agent pair --usb")
                    commandRow("walnut-agent session --usb")
                }
                .padding(.bottom, 10)
            } label: {
                optionLabel("Connect over USB", icon: "cable.connector")
            }
            if let code = session.pairingCode, !session.isConnected {
                Divider()
                DisclosureGroup(isExpanded: $showPairingFileOptions) {
                    pairingFileOptions(code)
                        .padding(.bottom, 10)
                } label: {
                    optionLabel("Pair with a file or token", icon: "doc.badge.arrow.up")
                }
            }
            if session.hasRememberedMac {
                Divider()
                Toggle(isOn: Binding(get: { autoConnect }, set: { enabled in
                    autoConnect = enabled
                    if enabled { start(true) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect automatically")
                            .font(.subheadline.weight(.medium))
                        Text("Start Mac Agent when Walnut opens.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 48, alignment: .leading)
                }
                .tint(.accentColor)
            }
            if session.hasRememberedMac || session.pairingStorageError != nil {
                Divider()
                Button(role: .destructive) { confirmForgetMac = true } label: {
                    optionLabel("Forget Mac", icon: "link.badge.minus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            DisclosureGroup(isExpanded: $showInstallOptions) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run these commands in Terminal on your Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    commandRow(Self.installCommands)
                    ShareLink(item: Self.setupGuide) {
                        Label("Share Mac setup guide", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                }
                .padding(.bottom, 10)
            } label: {
                optionLabel("Install on Mac", icon: "terminal")
            }
        }
        .padding(.horizontal, 16)
        .tint(Color.primary)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func optionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .frame(minHeight: 48, alignment: .leading)
    }

    private func commandRow(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: command)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .leftToRight)
            Button {
                UIPasteboard.general.string = command
                announce("Command copied")
                copyFeedback.show("Command copied")
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy command")
            .accessibilityHint(Text(verbatim: command))
        }
        .padding(.leading, 12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func pairingFileOptions(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                UIPasteboard.general.setItems(
                    [[UTType.plainText.identifier: code]],
                    options: [.expirationDate: Date().addingTimeInterval(120)]
                )
                copyFeedback.show("Pairing token copied")
                announce("Pairing token copied")
            } label: {
                Label("Copy pairing token", systemImage: "doc.on.doc")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button {
                do {
                    clearPairingFile()
                    pairingFile = try AgentPairingFile(code: code)
                } catch {
                    pairingShareFailed = true
                }
            } label: {
                Label("Share pairing file", systemImage: "square.and.arrow.up")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            Text("Paste the token after running walnut-agent pair --token, or AirDrop the file to your Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            commandRow("walnut-agent pair --file ")
            Text("The token and file grant access to this session. Share only with your Mac. Stopping the connection or leaving Walnut invalidates them. Delete the received file after pairing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func announce(_ message: String.LocalizationValue) {
        UIAccessibility.post(notification: .announcement, argument: String(localized: message))
    }

    private func clearPairingFile() {
        pairingFile?.remove()
        pairingFile = nil
    }
}

private struct AgentPairingDigits: View {
    let code: String

    var body: some View {
        let grouped = "\(code.prefix(3)) \(code.suffix(3))"
        Text(verbatim: grouped)
            .font(.largeTitle.monospacedDigit().bold())
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .accessibilityLabel(code.map(String.init).joined(separator: " "))
            .environment(\.layoutDirection, .leftToRight)
    }
}

extension EnvironmentValues {
    @Entry var agentBrowserSettings: AgentBrowserSettings?
}

private struct AgentApprovalView: View {
    @AccessibilityFocusState private var focusConfirmation: Bool
    let request: AgentApprovalGate.Request
    let resolve: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: request.message).textSelection(.enabled)
                    if let confirmation = request.pairingConfirmation {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confirmation number").font(.subheadline.weight(.semibold))
                            AgentPairingDigits(code: confirmation)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityFocused($focusConfirmation)
                    }
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
            .navigationTitle(request.pairingConfirmation == nil ? "Allow Mac Agent action?" : "Pair this Mac?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Deny") { resolve(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.pairingConfirmation == nil ? "Allow" : "Numbers Match") { resolve(true) }
                }
            }
        }
        .accessibilityAction(.escape) { resolve(false) }
        .onAppear { focusConfirmation = request.pairingConfirmation != nil }
    }
}

struct BrowserSheetPresenter: UIViewControllerRepresentable {
    @Environment(\.locale) private var locale
    let request: () -> AgentApprovalGate.Request?
    let resolve: (UUID, Bool) -> Void
    let showsCallback: () -> Bool
    let dismissCallback: () -> Void
    var onSceneExit: () -> Void = {}
    var onWindowAttached: (UIWindow, Presenter) -> Void = { _, _ in }

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
        private var onWindowAttached: ((UIWindow, Presenter) -> Void)?
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
            onWindowAttached?(window, self)
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

        func dismissCallbackResult() async throws -> Bool {
            let deadline = ContinuousClock.now + .seconds(2)
            while callbackProvider != nil, callback != nil || callbackProvider?() == true {
                try Task.checkCancellation()
                if let callback = stableCallback {
                    guard approval == nil, callback.presentedViewController == nil else {
                        throw AgentError("Close the open sheet above the callback result in Walnut first.")
                    }
                    await withCheckedContinuation { continuation in
                        closeCallback(callback) { continuation.resume() }
                    }
                    return true
                }
                guard ContinuousClock.now < deadline else {
                    throw AgentError("The callback result sheet is still changing. Try again.")
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            return false
        }

        private var stableCallback: UIViewController? {
            guard !transitioning, let callback, callback.presentingViewController != nil, !callback.isBeingDismissed else { return nil }
            return callback
        }

        private func closeCallback() {
            guard approval == nil, let callback = stableCallback, callback.presentedViewController == nil else { return }
            closeCallback(callback)
        }

        private func closeCallback(_ controller: UIViewController, completion: @escaping () -> Void = {}) {
            clearCallbackRequest()
            dismiss(controller) { [weak self] in
                self?.callback = nil
                completion()
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            guard callback === presentationController.presentedViewController else { return }
            callback = nil
            clearCallbackRequest()
            reconcile()
        }

        private func clearCallbackRequest() {
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
