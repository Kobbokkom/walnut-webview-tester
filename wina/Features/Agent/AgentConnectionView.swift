import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AgentConnectionView: View {
    private enum ConnectionMethod: String {
        case wifi, usb

        func command(_ action: String) -> String {
            "walnut-agent \(action)\(self == .usb ? " --usb" : "")"
        }
    }

    private enum Status {
        case off, saved, starting, pairing, pairingEnded, waiting, connected
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AgentSession.autoConnectKey) private var autoConnect = false
    @AppStorage("macAgentConnectionMethod") private var connectionMethod = ConnectionMethod.wifi
    @AppStorage(AgentApprovalMode.defaultsKey) private var approvalMode = AgentApprovalMode.ask
    @State private var copyFeedback = CopiedFeedbackState()
    @State private var showPairingFileOptions = false
    @State private var showInstallOptions = false
    @AccessibilityFocusState private var focusStatus: Bool
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

    private var status: Status {
        if session.isConnected { return .connected }
        if session.isPairingAvailable { return .pairing }
        if session.isRunning, session.isPairingReady { return .waiting }
        if session.isRunning, session.pairingCode != nil, !session.hasRememberedMac { return .pairingEnded }
        if session.isRunning { return .starting }
        return session.hasRememberedMac ? .saved : .off
    }

    private var visibleError: String? {
        if let error = session.pairingStorageError ?? session.reconnectError { return error }
        if status == .pairingEnded { return session.pairingError }
        if !session.isRunning { return session.connectionError }
        return nil
    }

    var body: some View {
        @Bindable var feedback = copyFeedback
        NavigationStack {
            Form {
                if !session.hasRememberedMac { installSection }
                statusSection
                approvalSection
                if status != .connected { connectionMethodSection }
                if session.pairingCode != nil, !session.hasPairingGrant { pairingFileSection }
                if session.hasRememberedMac { thisMacSection }
                if session.hasRememberedMac || session.pairingStorageError != nil { forgetSection }
                if session.hasRememberedMac { installSection }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .animation(.smooth(duration: 0.3), value: status)
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
        } message: {
            Text("Copy the pairing token instead, or try again.")
        }
        .alert("Forget this Mac?", isPresented: $confirmForgetMac) {
            Button("Forget Mac", role: .destructive) { session.forgetRememberedMac() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Walnut removes the saved pairing. Pair again to use this Mac.")
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
                focusStatus = true
            }
        }
        .onChange(of: session.hasPairingGrant) { _, granted in
            if granted { announce("Mac paired") }
        }
        .onChange(of: visibleError) { _, error in
            if let error { UIAccessibility.post(notification: .announcement, argument: error) }
        }
        .onChange(of: session.isRunning) { _, _ in focusStatus = true }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            Group {
                statusHeader
                statusContent
                if let error = visibleError {
                    Label {
                        Text(verbatim: error)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                }
                if session.isRunning {
                    Button { session.stopManually() } label: {
                        Label("Stop connection", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .listRowSeparator(.hidden)
        } footer: {
            if !session.isRunning {
                Text("Diagnostics and approved data are sent to your Mac and may also be shared with the AI service you use.")
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Group {
                switch status {
                case .connected, .waiting, .saved:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .starting:
                    ProgressView()
                case .pairing:
                    Image(systemName: "number.circle.fill").foregroundStyle(Color.accentColor)
                case .off, .pairingEnded:
                    Image(systemName: "laptopcomputer.and.iphone").foregroundStyle(.secondary)
                }
            }
            .font(.title2)
            .frame(width: 32)
            .accessibilityHidden(true)
            Text(statusTitle)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusStatus)
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: LocalizedStringKey {
        switch status {
        case .connected: "Mac connected"
        case .waiting, .saved: "Mac paired"
        case .starting: "Starting connection"
        case .pairing: "Ready to pair"
        case .off, .pairingEnded: "Connect your Mac"
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch status {
        case .connected:
            Text("Keep Walnut open while your Mac uses it.")
                .foregroundStyle(.secondary)
        case .pairing:
            Text("Run this command in Terminal on your Mac.")
            commandRow(connectionMethod.command("pair"))
            Text("If the six digits match on both devices, confirm on iPhone, then enter y in Terminal.")
            if connectionMethod == .wifi, let name = session.pairingDeviceName {
                Text("Pairing name: \(Text(verbatim: name).font(.footnote.monospaced()))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .waiting:
            Text("Start a session in Terminal or ask your coding agent to use Walnut.")
            commandRow(connectionMethod.command("session"))
        case .pairingEnded:
            if session.pairingError == nil {
                Text("Start pairing again to connect a Mac.")
            }
            Button { session.startPairing() } label: {
                Text("Start pairing again").frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .starting:
            EmptyView()
        case .saved, .off:
            if status == .saved {
                Text("Start the connection to use your saved pairing.")
            }
            Button { start(false) } label: {
                Label("Start connection", systemImage: "link")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Sections

    private var approvalSection: some View {
        Section {
            Picker(selection: $approvalMode) {
                Text("Ask every time").tag(AgentApprovalMode.ask)
                Text("Allow page actions").tag(AgentApprovalMode.pageActions)
                Text("Allow everything").tag(AgentApprovalMode.all)
            } label: {
                Label("Approvals", systemImage: approvalMode == .all ? "exclamationmark.shield" : "checkmark.shield")
                    .foregroundStyle(approvalMode == .all ? Color.orange : Color.primary)
            }
            .pickerStyle(.menu)
        } footer: {
            switch approvalMode {
            case .ask:
                Text("Walnut asks on iPhone before each action.")
            case .pageActions:
                Text("Reading, interacting with and running scripts on the open page run without asking. Screenshots, recordings, data deletion and settings changes still ask.")
            case .all:
                Text("Every action runs without asking, including screenshots and settings changes. Use only with a Mac and agent you trust.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var connectionMethodSection: some View {
        Section {
            Picker("Connection method", selection: $connectionMethod) {
                Text(verbatim: "Wi-Fi").tag(ConnectionMethod.wifi)
                Text(verbatim: "USB").tag(ConnectionMethod.usb)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if connectionMethod == .usb {
                Text("For USB, install this helper once on your Mac.")
                commandRow("brew install libusbmuxd")
            }
        } header: {
            Text("Connection method")
        } footer: {
            if connectionMethod == .usb {
                Text("Connect your iPhone by USB, unlock it, and tap Trust if asked. A shared Wi-Fi network is not required.")
            } else {
                Text("Connect both devices to the same Wi-Fi network. No cable is needed. Allow Local Network access if asked.")
            }
        }
    }

    private var pairingFileSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showPairingFileOptions) {
                if let code = session.pairingCode { pairingFileOptions(code) }
            } label: {
                rowLabel("Pair with a file or token", icon: "doc.badge.arrow.up")
            }
        }
    }

    private var thisMacSection: some View {
        Section {
            Toggle(isOn: Binding(get: { autoConnect }, set: { enabled in
                autoConnect = enabled
                if enabled { start(true) }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect automatically")
                    Text("Start Mac Agent when Walnut opens.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var forgetSection: some View {
        Section {
            Button(role: .destructive) { confirmForgetMac = true } label: {
                Label("Forget Mac", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        }
    }

    private var installSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showInstallOptions) {
                Text("Install Walnut Agent once on your Mac for either connection method.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                commandRow(Self.installCommands)
                ShareLink(item: Self.setupGuide) {
                    Label("Share Mac setup guide", systemImage: "square.and.arrow.up")
                }
            } label: {
                rowLabel("Install on Mac", icon: "terminal")
            }
        }
    }

    // MARK: - Rows

    private func rowLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label(title, systemImage: icon)
            .foregroundStyle(.primary)
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
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy command")
            .accessibilityHint(Text(verbatim: command))
            .accessibilityInputLabels([Text("Copy command"), Text(verbatim: command)])
        }
        .padding(.leading, 12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func pairingFileOptions(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.setItems(
                        [[UTType.plainText.identifier: code]],
                        options: [.expirationDate: Date().addingTimeInterval(120)]
                    )
                    copyFeedback.show("Pairing token copied")
                    announce("Pairing token copied")
                } label: {
                    Label("Copy pairing token", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                Button {
                    do {
                        clearPairingFile()
                        pairingFile = try AgentPairingFile(code: code)
                    } catch {
                        pairingShareFailed = true
                    }
                } label: {
                    Label("Share pairing file", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
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
        .padding(.vertical, 4)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    Button { resolve(true) } label: {
                        Text(request.pairingConfirmation == nil ? LocalizedStringKey("Allow") : LocalizedStringKey("Numbers Match"))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { resolve(false) } label: {
                        Text("Deny").frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground))
            }
            .navigationTitle(request.pairingConfirmation == nil ? LocalizedStringKey("Allow Mac Agent action?") : LocalizedStringKey("Pair this Mac?"))
            .navigationBarTitleDisplayMode(.inline)
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
