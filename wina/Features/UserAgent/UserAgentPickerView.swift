import SwiftUI
import SwiftUIBackports

struct UserAgentPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("customUserAgent") private var storedCustomUserAgent: String = ""
    @AppStorage("cachedSystemUserAgent") private var cachedSystemUserAgent: String = ""

    // Local binding support for Apply-based settings
    private var localUserAgentBinding: Binding<String>?

    private var customUserAgent: Binding<String> {
        localUserAgentBinding ?? $storedCustomUserAgent
    }

    @State private var showingCustomEditor = false

    // Quick Picks: 가장 많이 사용되는 프리셋들
    private let quickPicks: [UserAgentPreset] = [
        UserAgentPresets.safariMobileiPhone,
        UserAgentPresets.chromeDesktopWindows,
        UserAgentPresets.firefoxDesktopWindows,
        UserAgentPresets.safariDesktopMac,
        UserAgentPresets.chromeMobileAndroid,
    ]

    init() {
        self.localUserAgentBinding = nil
    }

    init(localUserAgent: Binding<String>) {
        self.localUserAgentBinding = localUserAgent
    }

    var body: some View {
        List {
            currentPreviewSection
            quickPicksSection
            browseAllSection
        }
        .navigationTitle(Text(verbatim: "User Agent"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCustomEditor) {
            CustomUserAgentEditor(userAgent: customUserAgent)
        }
    }

    // MARK: - Current Preview Section

    private var currentUserAgentValue: String {
        customUserAgent.wrappedValue.isEmpty ? cachedSystemUserAgent : customUserAgent.wrappedValue
    }

    private var currentPreviewSection: some View {
        Section {
            Button {
                showingCustomEditor = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            if customUserAgent.wrappedValue.isEmpty {
                                Text("Default")
                                    .font(.subheadline.weight(.medium))
                            } else {
                                Text(detectBrowserName(customUserAgent.wrappedValue))
                                    .font(.subheadline.weight(.medium))
                                Text("Custom")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue, in: Capsule())
                            }
                        }
                        if currentUserAgentValue.isEmpty {
                            Text("System default (view Info to detect)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            HighlightedUserAgent(userAgent: currentUserAgentValue)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)

                    if !customUserAgent.wrappedValue.isEmpty {
                        Button {
                            withAnimation { customUserAgent.wrappedValue = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Current")
        }
    }

    // MARK: - Quick Picks Section

    private var quickPicksSection: some View {
        Section {
            ForEach(quickPicks) { preset in
                QuickPickRow(
                    preset: preset,
                    isActive: customUserAgent.wrappedValue == preset.userAgent
                ) {
                    withAnimation { customUserAgent.wrappedValue = preset.userAgent }
                }
            }
        } header: {
            Label("Quick Picks", systemImage: "sparkles")
        } footer: {
            Text("Tap to apply. Changes take effect on next page load.")
        }
    }

    // MARK: - Browse All Section

    private var browseAllSection: some View {
        Section {
            NavigationLink {
                AllPresetsView(customUserAgent: customUserAgent)
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.blue)
                    Text("Browse All Presets")
                    Spacer()
                    Text("\(UserAgentPresets.allPresets.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func detectBrowserName(_ ua: String) -> String {
        let parsed = UserAgentParser.parse(ua)
        if parsed.browser.isEmpty { return "Custom" }
        return "\(parsed.browser) on \(parsed.osName)"
    }
}

// MARK: - Quick Pick Row

private struct QuickPickRow: View {
    let preset: UserAgentPreset
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: preset.browser.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(isActive ? Color.blue : Color.clear)
                    .clipShape(Circle())
                    .overlay {
                        if !isActive {
                            Circle().strokeBorder(.quaternary, lineWidth: 1)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - All Presets View

private struct AllPresetsView: View {
    @Binding var customUserAgent: String
    @State private var searchText = ""
    @State private var selectedBrowser: UserAgentBrowser?

    private var filteredPresets: [UserAgentPreset] {
        UserAgentPresets.search(searchText, browser: selectedBrowser)
    }

    private var groupedPresets: [(browser: UserAgentBrowser, presets: [UserAgentPreset])] {
        let grouped = Dictionary(grouping: filteredPresets) { $0.browser }
        return UserAgentBrowser.allCases
            .compactMap { browser in
                guard let presets = grouped[browser], !presets.isEmpty else { return nil }
                return (browser, presets)
            }
    }

    var body: some View {
        List {
            // Browser filter chips
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All", isSelected: selectedBrowser == nil) {
                            selectedBrowser = nil
                        }
                        ForEach(UserAgentBrowser.allCases) { browser in
                            FilterChip(
                                label: browser.rawValue,
                                icon: browser.icon,
                                isSelected: selectedBrowser == browser
                            ) {
                                selectedBrowser = browser
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowBackground(Color.clear)
            }

            // Grouped presets
            ForEach(groupedPresets, id: \.browser) { group in
                Section {
                    ForEach(group.presets) { preset in
                        PresetDetailRow(
                            preset: preset,
                            isActive: customUserAgent == preset.userAgent
                        ) {
                            withAnimation { customUserAgent = preset.userAgent }
                        }
                    }
                } header: {
                    Label(group.browser.rawValue, systemImage: group.browser.icon)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search presets...")
        .navigationTitle(Text(verbatim: "All Presets"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .backport.glassEffect(in: .capsule)
    }
}

// MARK: - Preset Detail Row

private struct PresetDetailRow: View {
    let preset: UserAgentPreset
    let isActive: Bool
    let onSelect: () -> Void

    @State private var showingDetail = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: preset.browser.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(isActive ? Color.blue : Color.clear)
                    .clipShape(Circle())
                    .overlay {
                        if !isActive {
                            Circle().strokeBorder(.quaternary, lineWidth: 1)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preset.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Image(systemName: preset.platform.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }

                Button {
                    showingDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.body)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingDetail) {
                    PresetDetailPopover(preset: preset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preset Detail Popover

private struct PresetDetailPopover: View {
    let preset: UserAgentPreset
    @State private var feedbackState = CopiedFeedbackState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: preset.browser.icon)
                    .foregroundStyle(.blue)
                Text(preset.name)
                    .font(.headline)
            }

            HighlightedUserAgent(userAgent: preset.userAgent)

            Button {
                UIPasteboard.general.string = preset.userAgent
                feedbackState.showCopied("User Agent")
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(maxWidth: 320)
        .presentationCompactAdaptation(.popover)
        .copiedFeedbackOverlay($feedbackState.message)
    }
}

// MARK: - Custom User Agent Editor

private struct CustomUserAgentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var userAgent: String

    @State private var mode: EditorMode = .preset
    @State private var inputText = ""
    @State private var selectedBrowser: UserAgentBrowser = .chrome
    @State private var selectedPlatform: PlatformOption = .windowsDesktop
    @State private var browserVersion = "131.0.0.0"

    enum EditorMode: String, CaseIterable {
        case preset = "Builder"
        case manual = "Manual"
    }

    enum PlatformOption: String, CaseIterable, Identifiable {
        case windowsDesktop = "Windows"
        case macDesktop = "macOS"
        case linux = "Linux"
        case android = "Android"
        case iphone = "iPhone"
        case ipad = "iPad"

        var id: String { rawValue }

        var platformToken: UserAgentBuilder.PlatformToken {
            switch self {
            case .windowsDesktop: return .windowsDesktop
            case .macDesktop: return .macDesktop
            case .linux: return .linux
            case .android: return .android
            case .iphone: return .iphone
            case .ipad: return .ipad
            }
        }
    }

    private var builtUserAgent: String {
        switch selectedBrowser {
        case .chrome:
            return UserAgentBuilder.chrome(version: browserVersion, platform: selectedPlatform.platformToken).build()
        case .safari:
            return UserAgentBuilder.safari(version: browserVersion, platform: selectedPlatform.platformToken).build()
        case .firefox:
            return UserAgentBuilder.firefox(version: browserVersion, platform: selectedPlatform.platformToken).build()
        case .edge:
            return UserAgentBuilder.edge(version: browserVersion, platform: selectedPlatform.platformToken).build()
        case .opera, .brave:
            var builder = UserAgentBuilder.chrome(version: browserVersion, platform: selectedPlatform.platformToken)
            if selectedBrowser == .opera {
                builder.additionalTokens = ["OPR/116.0.0.0"]
            }
            return builder.build()
        }
    }

    private var currentOutput: String {
        mode == .preset ? builtUserAgent : inputText
    }

    var body: some View {
        NavigationStack {
            List {
                // Mode picker
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(EditorMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if mode == .preset {
                    builderSection
                } else {
                    manualSection
                }

                // Preview
                Section("Preview") {
                    if currentOutput.isEmpty {
                        Text("No User Agent")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HighlightedUserAgent(userAgent: currentOutput)
                        UserAgentPreviewRow(userAgent: currentOutput)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Custom User Agent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        userAgent = currentOutput
                        dismiss()
                    }
                    .disabled(currentOutput.isEmpty)
                }
            }
            .onAppear {
                inputText = userAgent
                if !userAgent.isEmpty {
                    mode = .manual
                    let parsed = UserAgentParser.parse(userAgent)
                    if !parsed.browserVersion.isEmpty {
                        browserVersion = parsed.browserVersion
                    }
                }
            }
        }
    }

    private var builderSection: some View {
        Section {
            // Browser picker with icons
            HStack {
                Text("Browser")
                Spacer()
                Picker("Browser", selection: $selectedBrowser) {
                    ForEach(UserAgentBrowser.allCases) { browser in
                        Label(browser.rawValue, systemImage: browser.icon).tag(browser)
                    }
                }
                .pickerStyle(.menu)
            }

            // Platform picker
            HStack {
                Text("Platform")
                Spacer()
                Picker("Platform", selection: $selectedPlatform) {
                    ForEach(PlatformOption.allCases) { platform in
                        Text(platform.rawValue).tag(platform)
                    }
                }
                .pickerStyle(.menu)
            }

            // Version
            HStack {
                Text("Version")
                Spacer()
                TextField("Version", text: $browserVersion)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14, design: .monospaced))
                    .frame(maxWidth: 120)
            }
        } header: {
            Text("Configuration")
        }
    }

    private var manualSection: some View {
        Section {
            ZStack(alignment: .topTrailing) {
                TextEditor(text: $inputText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 100)

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("User Agent String")
        } footer: {
            Text("Enter any valid User Agent string")
        }
    }
}

// MARK: - User Agent Preview Row

private struct UserAgentPreviewRow: View {
    let userAgent: String

    private var parsed: UserAgentParser.ParsedUserAgent {
        UserAgentParser.parse(userAgent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Browser", value: "\(parsed.browser) \(parsed.browserVersion)")
            LabeledContent("Engine", value: "\(parsed.engine) \(parsed.engineVersion)")
            LabeledContent("OS", value: parsed.osName)
            LabeledContent("Type", value: parsed.isMobile ? "Mobile" : (parsed.isTablet ? "Tablet" : "Desktop"))
        }
        .font(.caption)
    }
}

// MARK: - Highlighted User Agent Text

private struct HighlightedUserAgent: View {
    let userAgent: String

    var body: some View {
        Text(formattedUserAgent)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
    }

    private var formattedUserAgent: AttributedString {
        let patterns: [(pattern: String, color: Color)] = [
            ("Mozilla/[\\d.]+", .blue),
            ("AppleWebKit/[\\d.]+", .orange),
            ("Chrome/[\\d.]+", .green),
            ("CriOS/[\\d.]+", .green),
            ("Safari/[\\d.]+", .pink),
            ("Version/[\\d.]+", .purple),
            ("Firefox/[\\d.]+", .orange),
            ("FxiOS/[\\d.]+", .orange),
            ("Edg/[\\d.]+", .cyan),
            ("EdgA/[\\d.]+", .cyan),
            ("EdgiOS/[\\d.]+", .cyan),
            ("OPR/[\\d.]+", .red),
            ("Mobile/[\\w]+", .mint),
            ("\\([^)]+\\)", .secondary),
        ]

        var text = userAgent
        text = text.replacingOccurrences(of: ") ", with: ")\n")

        var attributed = AttributedString(text)

        for (pattern, color) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsRange = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: nsRange) {
                    if let range = Range(match.range, in: text),
                       let attrRange = Range(range, in: attributed)
                    {
                        attributed[attrRange].foregroundColor = color
                    }
                }
            }
        }

        return attributed
    }
}

#Preview {
    UserAgentPickerView()
}
