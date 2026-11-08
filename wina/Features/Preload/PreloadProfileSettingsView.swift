//
//  PreloadProfileSettingsView.swift
//  wina
//
//  Home-screen preload profile editor.
//

import SwiftUI

// MARK: - Preload Profile Settings

struct PreloadProfileSettingsState {
    var profile: WebViewPreloadProfile = .empty
    var savedProfiles: [WebViewPreloadProfile] = []
    private(set) var hasLoaded = false

    var validationMessage: String? {
        PreloadProfileValidation.message(for: profile)
    }

    mutating func loadIfNeeded(
        activeProfile: () -> WebViewPreloadProfile = { PreloadProfileStore.activeProfile() },
        savedProfiles: () -> [WebViewPreloadProfile] = { PreloadProfileStore.savedProfiles() }
    ) {
        guard !hasLoaded else { return }
        hasLoaded = true
        profile = activeProfile()
        self.savedProfiles = savedProfiles()
    }

    mutating func saveCurrentProfile(
        defaults: UserDefaults = .standard
    ) {
        guard validationMessage == nil else { return }

        var reusable = profile
        if reusable.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reusable.name = "Untitled Setup"
        }
        // Save only adds the draft to the saved list. It must NOT write the active profile —
        // otherwise Cancel could not roll back, and an explicit Home OFF would be overridden.
        // Apply is the only action that changes what is active.
        profile = PreloadProfileStore.upsertSavedProfile(reusable, defaults: defaults)
        savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)
    }

    mutating func applyCurrentProfile(
        defaults: UserDefaults = .standard
    ) {
        guard validationMessage == nil else { return }

        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.name = "Untitled Setup"
        }

        // Persist whatever enabled state the user chose (the Enable toggle / loading a saved
        // setup). Apply no longer force-enables, so editing a disabled setup keeps it off.
        PreloadProfileStore.saveActiveProfile(profile, defaults: defaults)
    }

    mutating func deleteSavedProfiles(
        at offsets: IndexSet,
        defaults: UserDefaults = .standard
    ) {
        savedProfiles.remove(atOffsets: offsets)
        PreloadProfileStore.saveProfiles(savedProfiles, defaults: defaults)
        savedProfiles = PreloadProfileStore.savedProfiles(defaults: defaults)
    }

    mutating func startEmptySetup() {
        profile = WebViewPreloadProfile(name: "Untitled Setup")
    }
}

enum PreloadProfileValidation {
    static func message(for profile: WebViewPreloadProfile) -> String? {
        guard profile.isEnabled else { return nil }

        for channel in profile.bridgeChannels where channel.isEnabled {
            if !BridgeChannelNameValidator.isValid(channel.name)
                || BridgeChannelNameValidator.reservedNames.contains(channel.name)
            {
                return String(localized: "Channel name must be valid and not reserved.")
            }

            for rule in channel.responseRules where rule.isEnabled {
                if !BridgeResponseBodyValidator.isValidTemplate(rule.response.bodyTemplate) {
                    return String(localized: "Response JSON syntax and placeholders must be valid before applying.")
                }

                if rule.response.target == .callback,
                   !JavaScriptPath.isValid(rule.response.callbackName)
                {
                    return String(localized: "Callback name must be a valid JavaScript path.")
                }
            }
        }

        return nil
    }
}

struct PreloadProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var state = PreloadProfileSettingsState()
    @State private var showSavedSetupLoader = false
    @State private var feedbackState = CopiedFeedbackState()

    var body: some View {
        NavigationStack {
            List {
                experimentalWarningSection
                profileSection
                savedProfilesSection
                cookiesSection
                windowItemsSection
                bridgeSection
                customScriptsSection
            }
            .navigationTitle("Page Startup Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        state.applyCurrentProfile()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(state.validationMessage != nil)
                }
            }
            .onAppear(perform: loadIfNeeded)
            .sheet(isPresented: $showSavedSetupLoader) {
                savedSetupLoaderSheet
            }
            .copiedFeedbackOverlay($feedbackState.message)
        }
    }

    @ViewBuilder
    private var experimentalWarningSection: some View {
        Section {
            Text("Experimental feature. This setup may be unstable across pages.")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section {
            Toggle("Enable this setup", isOn: $state.profile.isEnabled)

            PreloadTextField(title: "Profile name", text: $state.profile.name)

            if let validationMessage = state.validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                state.saveCurrentProfile()
                feedbackState.show(String(localized: "Setup saved"))
            } label: {
                Text("Save Current Setup")
            }
            .disabled(state.validationMessage != nil)

            Button("Start Empty Setup") {
                state.startEmptySetup()
            }
        } header: {
            Text("Current Setup")
        } footer: {
            Text("Apply cookies, window values, bridge mocks, and custom scripts before each new WKWebView page loads. Turning setup off stops every injection in this setup. Saving with a name adds it to Saved Setups.")
        }
    }

    @ViewBuilder
    private var savedProfilesSection: some View {
        Section(
            content: {
                Button("Load Saved Setup") {
                    showSavedSetupLoader = true
                }
            },
            header: {
                Text("Saved Setups")
            },
            footer: {
            Text("Reload saved startup setups as-is. Swipe left in the list to delete a saved setup.")
            }
        )
    }

    @ViewBuilder
    private var savedSetupLoaderSheet: some View {
        NavigationStack {
            List {
                ForEach(state.savedProfiles) { saved in
                    Button {
                        state.profile = saved
                        showSavedSetupLoader = false
                feedbackState.show(String(localized: "Setup loaded"))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(saved.name)
                                .foregroundStyle(.primary)
                            if let summary = savedSetupSummary(for: saved) {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSavedProfiles)
            }
            .navigationTitle("Load Saved Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showSavedSetupLoader = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var cookiesSection: some View {
        Section {
            ForEach(state.profile.cookies) { cookie in
                NavigationLink {
                    PreloadCookieEditorView(cookie: binding(forCookieID: cookie.id))
                } label: {
                PreloadEditableRow(
                    title: cookieTitle(for: cookie),
                    subtitle: cookieSubtitle(for: cookie),
                    isEnabled: cookie.isEnabled
                )
                }
            }
            .onDelete { state.profile.cookies.remove(atOffsets: $0) }

            Button {
                state.profile.cookies.append(PreloadCookie(name: "session", value: "demo"))
            } label: {
                Label("Add Cookie", systemImage: "plus.circle")
            }
        } header: {
            Text("Cookies")
        } footer: {
            Text("Register cookies to set before the page opens. Only enabled cookies are injected before the first load, with domain, path, expiration, SameSite, Secure, and HTTP Only options.")
        }
    }

    @ViewBuilder
    private var windowItemsSection: some View {
        Section {
            ForEach(state.profile.windowItems) { item in
                NavigationLink {
                    WindowInjectionEditorView(item: binding(forWindowItemID: item.id))
                } label: {
                PreloadEditableRow(
                    title: windowItemTitle(for: item),
                    subtitle: item.kind.localizedTitle,
                    isEnabled: item.isEnabled
                )
                }
            }
            .onDelete { state.profile.windowItems.remove(atOffsets: $0) }

            Button {
                state.profile.windowItems.append(WindowInjectionItem(name: "appVersion", value: "1.0.0"))
            } label: {
                Label("Add Window Item", systemImage: "plus.circle")
            }
        } header: {
            Text("Window")
        } footer: {
            Text("Inject values or functions into window before page scripts run. Use dotted paths like window.appVersion to set variables, return-value functions, or raw function bodies at document start.")
        }
    }

    @ViewBuilder
    private var bridgeSection: some View {
        Section {
            Toggle("Capture window.postMessage", isOn: $state.profile.capturesWindowPostMessage)

            ForEach(state.profile.bridgeChannels) { channel in
                NavigationLink {
                    BridgeChannelEditorView(channel: binding(forBridgeChannelID: channel.id))
                } label: {
                PreloadEditableRow(
                    title: channelTitle(for: channel),
                    subtitle: String(localized: "\(channel.responseRules.filter(\.isEnabled).count) rules"),
                    isEnabled: channel.isEnabled
                )
                }
            }
            .onDelete { state.profile.bridgeChannels.remove(atOffsets: $0) }

            Button {
                state.profile.bridgeChannels.append(
                    BridgeChannel(
                        name: "request",
                        responseRules: [BridgeResponseRule(name: "Log only", matcher: .any)]
                    )
                )
            } label: {
                Label("Add Channel", systemImage: "plus.circle")
            }
        } header: {
            Text("Bridge Mock")
        } footer: {
            Text("Mock a native bridge. Channels are exposed as window.webkit.messageHandlers.<name>, and response rules can reply to matching messages by any message, type, or JSON path. Enabling Capture window.postMessage shows page postMessage calls as badges in Console.")
        }
    }

    @ViewBuilder
    private var customScriptsSection: some View {
        Section {
            ForEach(state.profile.customScripts) { script in
                NavigationLink {
                    CustomPreloadScriptEditorView(script: binding(forCustomScriptID: script.id))
                } label: {
                PreloadEditableRow(
                    title: script.name,
                    subtitle: customScriptSubtitle(for: script),
                    isEnabled: script.isEnabled
                )
                }
            }
            .onDelete { state.profile.customScripts.remove(atOffsets: $0) }

            Button {
                state.profile.customScripts.append(PreloadCustomScript())
            } label: {
                Label("Add Custom Script", systemImage: "plus.circle")
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Run custom JavaScript before the page loads at document start. Each script is wrapped in try/catch, so errors remain console warnings, and scripts can target only the main frame or all frames.")
        }
    }

    private func loadIfNeeded() {
        state.loadIfNeeded()
    }

    private func deleteSavedProfiles(at offsets: IndexSet) {
        state.deleteSavedProfiles(at: offsets)
    }

    private func savedSetupSummary(for profile: WebViewPreloadProfile) -> String? {
        let count =
            profile.cookies.count + profile.windowItems.count
            + profile.bridgeChannels.count + profile.customScripts.count
            + (profile.capturesWindowPostMessage ? 1 : 0)
        guard count > 0 else { return nil }
        return count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
    }

    private func cookieTitle(for cookie: PreloadCookie) -> String {
        cookie.name.isEmpty ? String(localized: "Cookie") : cookie.name
    }

    private func cookieSubtitle(for cookie: PreloadCookie) -> String {
        cookie.domainMode == .currentHost ? String(localized: "Current host") : cookie.customDomain
    }

    private func windowItemTitle(for item: WindowInjectionItem) -> String {
        item.name.isEmpty ? String(localized: "Window Item") : "window.\(item.name)"
    }

    private func channelTitle(for channel: BridgeChannel) -> String {
        channel.name.isEmpty ? String(localized: "Channel") : channel.name
    }

    private func customScriptSubtitle(for script: PreloadCustomScript) -> String {
        script.forMainFrameOnly ? String(localized: "Main frame") : String(localized: "All frames")
    }

    private func binding(forCookieID id: UUID) -> Binding<PreloadCookie> {
        Binding {
            state.profile.cookies.first { $0.id == id } ?? PreloadCookie(id: id, isEnabled: false)
        } set: { updated in
            guard let index = state.profile.cookies.firstIndex(where: { $0.id == id }) else { return }
            state.profile.cookies[index] = updated
        }
    }

    private func binding(forWindowItemID id: UUID) -> Binding<WindowInjectionItem> {
        Binding {
            state.profile.windowItems.first { $0.id == id } ?? WindowInjectionItem(id: id, isEnabled: false)
        } set: { updated in
            guard let index = state.profile.windowItems.firstIndex(where: { $0.id == id }) else { return }
            state.profile.windowItems[index] = updated
        }
    }

    private func binding(forBridgeChannelID id: UUID) -> Binding<BridgeChannel> {
        Binding {
            state.profile.bridgeChannels.first { $0.id == id } ?? BridgeChannel(id: id, isEnabled: false)
        } set: { updated in
            guard let index = state.profile.bridgeChannels.firstIndex(where: { $0.id == id }) else { return }
            state.profile.bridgeChannels[index] = updated
        }
    }

    private func binding(forCustomScriptID id: UUID) -> Binding<PreloadCustomScript> {
        Binding {
            state.profile.customScripts.first { $0.id == id } ?? PreloadCustomScript(id: id, isEnabled: false)
        } set: { updated in
            guard let index = state.profile.customScripts.firstIndex(where: { $0.id == id }) else { return }
            state.profile.customScripts[index] = updated
        }
    }
}

// MARK: - Shared Rows

private struct PreloadEditableRow: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isEnabled ? Color.blue : Color.gray)
        }
    }
}

// MARK: - Editor Fields

private struct PreloadTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var example: String?
    var isTechnical = false

    var body: some View {
        LabeledContent {
            TextField(title, text: $text, prompt: Text(verbatim: example ?? ""))
                .accessibilityLabel(title)
                .textFieldStyle(.plain)
                .font(.system(.body, design: isTechnical ? .monospaced : .default))
                .textInputAutocapitalization(isTechnical ? .never : .words)
                .autocorrectionDisabled(isTechnical)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.quaternary, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } label: {
            Text(title)
                .frame(minWidth: 90, alignment: .leading)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Cookie Editor

private struct PreloadCookieEditorView: View {
    @Binding var cookie: PreloadCookie

    var body: some View {
        Form {
            Section {
                Toggle("Enable cookie", isOn: $cookie.isEnabled)
                PreloadTextField(title: "Cookie name", text: $cookie.name, example: "session", isTechnical: true)
                PreloadTextField(title: "Cookie value", text: $cookie.value, example: "demo", isTechnical: true)
            } header: {
                Text("Cookie details")
            } footer: {
                Text("When enabled, this cookie is set before the page opens.")
            }

            Section {
                Picker("Domain", selection: $cookie.domainMode) {
                    ForEach(PreloadCookieDomainMode.allCases, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                if cookie.domainMode == .custom {
                    PreloadTextField(title: "Custom domain", text: $cookie.customDomain, example: "example.com", isTechnical: true)
                }
                PreloadTextField(title: "Path", text: $cookie.path, example: "/", isTechnical: true)
            } header: {
                Text("Cookie scope")
            } footer: {
                Text("Use / to apply the cookie to all paths on the selected domain.")
            }

            Section {
                Picker("Expires", selection: $cookie.expires) {
                    ForEach(PreloadCookieExpiration.allCases, id: \.self) { expiration in
                        if expiration == .session {
                            Text("Browser session").tag(expiration)
                        } else {
                            Text(expiration.localizedTitle).tag(expiration)
                        }
                    }
                }
                Picker("SameSite", selection: $cookie.sameSite) {
                    ForEach(PreloadCookieSameSite.allCases, id: \.self) { sameSite in
                        Text(sameSite.localizedTitle).tag(sameSite)
                    }
                }
                Toggle("HTTPS only", isOn: $cookie.isSecure)
                Toggle("HTTP Only", isOn: $cookie.isHTTPOnly)
            } header: {
                Text("Advanced options")
            }
        }
        .navigationTitle("Cookie")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Window Editor

private struct WindowInjectionEditorView: View {
    @Binding var item: WindowInjectionItem

    var body: some View {
        let valueTitle: LocalizedStringKey = item.kind == .functionBody ? "Function Body" : "Window value"
        Form {
            Section {
                Toggle("Enabled", isOn: $item.isEnabled)
                PreloadTextField(title: "Window property", text: $item.name, example: "appVersion", isTechnical: true)
                Picker("Type", selection: $item.kind) {
                    ForEach(WindowInjectionKind.allCases, id: \.self) { kind in
                        Text(kind.localizedTitle).tag(kind)
                    }
                }
                if item.kind != .functionBody {
                    Picker("Value type", selection: $item.valueKind) {
                        ForEach(PreloadValueKind.allCases, id: \.self) { kind in
                        Text(kind.localizedTitle).tag(kind)
                        }
                    }
                }
            } footer: {
                Text("Use dotted names like app.bridge.getToken to create nested window values.")
            }

            Section {
                TextEditor(text: $item.value)
                    .accessibilityLabel(valueTitle)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
            } header: {
                Text(valueTitle)
            }
        }
        .navigationTitle("Window Item")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Bridge Editors

private struct BridgeChannelEditorView: View {
    @Binding var channel: BridgeChannel

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $channel.isEnabled)
                PreloadTextField(title: "Channel name", text: $channel.name, example: "request", isTechnical: true)

                if !BridgeChannelNameValidator.isValid(channel.name)
                    || BridgeChannelNameValidator.reservedNames.contains(channel.name)
                {
                    Label(
                        "Use a JavaScript identifier that is not reserved.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(channel.responseRules) { rule in
                    NavigationLink {
                        BridgeRuleEditorView(rule: binding(forRuleID: rule.id))
                    } label: {
                        PreloadEditableRow(
                            title: rule.name,
                            subtitle: rule.response.target.localizedTitle,
                            isEnabled: rule.isEnabled
                        )
                    }
                }
                .onDelete { channel.responseRules.remove(atOffsets: $0) }

                Button {
                    channel.responseRules.append(
                        BridgeResponseRule(
                            name: "Reply",
                            matcher: .any,
                            response: BridgeResponse(target: .postMessage)
                        )
                    )
                } label: {
                    Label("Add Response Rule", systemImage: "plus.circle")
                }
            } header: {
                Text("Response Rules")
            }
        }
        .navigationTitle("Channel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(forRuleID id: UUID) -> Binding<BridgeResponseRule> {
        Binding {
            channel.responseRules.first { $0.id == id } ?? BridgeResponseRule(id: id, isEnabled: false)
        } set: { updated in
            guard let index = channel.responseRules.firstIndex(where: { $0.id == id }) else { return }
            channel.responseRules[index] = updated
        }
    }
}

private struct BridgeRuleEditorView: View {
    @Binding var rule: BridgeResponseRule

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $rule.isEnabled)
                PreloadTextField(title: "Rule name", text: $rule.name)
                BridgeMatcherEditor(matcher: $rule.matcher)
                Picker("Respond with", selection: $rule.response.target) {
                    ForEach(BridgeResponseTarget.allCases, id: \.self) { target in
                        Text(target.localizedTitle).tag(target)
                    }
                }
                Picker("Delay", selection: $rule.delayMilliseconds) {
                    Text("Instant").tag(0)
                    Text("300ms").tag(300)
                    Text("1s").tag(1_000)
                }
            }

            Section {
                TextEditor(text: $rule.response.bodyTemplate)
                    .accessibilityLabel("Response JSON")
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)

                if !BridgeResponseBodyValidator.isValidTemplate(rule.response.bodyTemplate) {
                    Label("Response JSON syntax and placeholders must be valid.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Response JSON")
            } footer: {
                Text("Available values: {{message}}, {{message.id}}, {{message.type}}, {{message.payload.token}}")
            }

            responseTargetSection
        }
        .navigationTitle("Response Rule")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var responseTargetSection: some View {
        switch rule.response.target {
        case .postMessage:
            EmptyView()

        case .customEvent:
            Section {
                PreloadTextField(title: "Event name", text: $rule.response.eventName, example: "nativeResponse", isTechnical: true)
            }

        case .callback:
            Section {
                PreloadTextField(title: "Callback name", text: $rule.response.callbackName, example: "app.onNativeResponse", isTechnical: true)

                if !JavaScriptPath.isValid(rule.response.callbackName) {
                    Label("Use a dotted JavaScript function path.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Use a dotted function path like app.onNativeResponse.")
            }

        case .customJavaScript:
            Section {
                TextEditor(text: $rule.response.customJavaScript)
                    .accessibilityLabel("Custom JavaScript")
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
            } header: {
                Text("Custom JavaScript")
            } footer: {
                Text("Use {{message}}, {{response}}, and {{channel}} placeholders.")
            }
        }
    }
}

private struct BridgeMatcherEditor: View {
    @Binding var matcher: BridgeMatcher

    @State private var mode: BridgeMatcherMode = .any
    @State private var value: String = ""
    @State private var path: String = "type"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Match", selection: $mode) {
                ForEach(BridgeMatcherMode.allCases, id: \.self) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            }

            if mode == .typeEquals {
                PreloadTextField(title: "Expected type", text: $value, example: "request", isTechnical: true)
            } else if mode == .jsonPathEquals {
                PreloadTextField(title: "JSON path", text: $path, example: "payload.token", isTechnical: true)
                PreloadTextField(title: "Expected value", text: $value, isTechnical: true)
            }
        }
        .onAppear(perform: load)
        .onChange(of: matcher) { _, _ in load() }
        .onChange(of: mode) { _, _ in save() }
        .onChange(of: path) { _, _ in save() }
        .onChange(of: value) { _, _ in save() }
    }

    private func load() {
        switch matcher {
        case .any:
            mode = .any
            path = "type"
            value = ""
        case .typeEquals(let expected):
            mode = .typeEquals
            path = "type"
            value = expected
        case .jsonPathEquals(let currentPath, let expected):
            mode = .jsonPathEquals
            path = currentPath
            value = expected
        }
    }

    private func save() {
        switch mode {
        case .any:
            matcher = .any
        case .typeEquals:
            matcher = .typeEquals(value)
        case .jsonPathEquals:
            matcher = .jsonPathEquals(path: path, value: value)
        }
    }
}

private enum BridgeMatcherMode: CaseIterable {
    case any
    case typeEquals
    case jsonPathEquals

    var title: String {
        switch self {
        case .any: "Any message"
        case .typeEquals: "type equals"
        case .jsonPathEquals: "JSON path equals"
        }
    }

    var localizedTitle: String {
        switch self {
        case .any: String(localized: "Any message")
        case .typeEquals: String(localized: "type equals")
        case .jsonPathEquals: String(localized: "JSON path equals")
        }
    }
}

// MARK: - Custom Script Editor

private struct CustomPreloadScriptEditorView: View {
    @Binding var script: PreloadCustomScript

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $script.isEnabled)
                PreloadTextField(title: "Script name", text: $script.name)
                Toggle("Main frame only", isOn: $script.forMainFrameOnly)
            }

            Section {
                TextEditor(text: $script.source)
                    .accessibilityLabel("Source")
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 240)
            } header: {
                Text("Source")
            }
        }
        .navigationTitle("Custom Script")
        .navigationBarTitleDisplayMode(.inline)
    }
}
