//
//  ContentView+URLInput.swift
//  wina
//
//  URL input view components for ContentView.
//

import GoogleMobileAds
import SwiftUI
import SwiftUIBackports

// MARK: - URL Input Views

extension ContentView {
    var urlInputView: some View {
        GeometryReader { geometry in
            // Background tap to dismiss keyboard and dropdown
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    textFieldFocused = false
                    showDropdown = false
                }

            ScrollView {
                VStack(spacing: 16) {
                    // Walnut logo
                    Image("walnut")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .padding(.bottom, -12)

                    // URL parts chips - FlowLayout for wrapping
                    FlowLayout(spacing: 8, alignment: .center) {
                        ForEach(urlParts, id: \.self) { part in
                            ChipButton(label: part) {
                                urlText += part
                            }
                        }
                    }
                    .frame(width: inputWidth)
                    .contentShape(Rectangle())
                    .onTapGesture {}  // Prevent background tap propagation

                    // WebView Type Toggle
                    Picker("WebView Type", selection: Binding(get: { useSafariWebView }, set: { useSafariWebView = $0 })) {
                        Text("WKWebView")
                            .tag(false)
                        Text(verbatim: "SafariVC")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: inputWidth)

                    // URL Input
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: isCallbackTestPageActive ? "checkmark.circle.fill" : urlValidationState.iconName)
                                .foregroundStyle(isCallbackTestPageActive ? .green : urlValidationState.iconColor)
                                .font(.system(size: 16))
                                .contentTransition(.symbolEffect(.replace))

                            TextField(
                                isCallbackTestPageActive ? "Callback Test Page" : "Enter URL",
                                text: isCallbackTestPageActive
                                    ? .constant(CallbackTestManager.testPageURL.absoluteString) : $urlText
                            )
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .font(.system(size: 16))
                            .focused($textFieldFocused)
                            .disabled(isCallbackTestPageActive)
                            .foregroundStyle(isCallbackTestPageActive ? .secondary : .primary)
                            .onSubmit {
                                if submitURL() {
                                    textFieldFocused = false
                                    showDropdown = false
                                }
                            }
                            .onChange(of: urlText) { _, _ in
                                // Debounced URL validation
                                validationTask?.cancel()
                                validationTask = Task {
                                    try? await Task.sleep(for: .milliseconds(150))
                                    guard !Task.isCancelled else { return }
                                    validateURL()
                                }
                            }

                            Button {
                                urlText = ""
                                textFieldFocused = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .opacity(urlText.isEmpty || isCallbackTestPageActive ? 0 : 1)
                            .disabled(urlText.isEmpty || isCallbackTestPageActive)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(width: (urlValidationState == .valid || isCallbackTestPageActive) ? max(0, inputWidth - 60) : inputWidth)
                        .contentShape(Capsule())
                        .onTapGesture {
                            if !isCallbackTestPageActive {
                                textFieldFocused = true
                            }
                        }
                        .backport.glassEffect(in: .capsule)

                        if isPreparingCleanStart {
                            ProgressView()
                                .frame(width: 48, height: 48)
                                .accessibilityLabel("Preparing WebView")
                        } else if urlValidationState == .valid || isCallbackTestPageActive {
                            Button {
                                textFieldFocused = false
                                showDropdown = false
                                submitURL()
                            } label: {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .backport.glassEffect(in: .circle)
                            .transition(.opacity.animation(.easeOut(duration: 0.15)))
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: urlValidationState)
                    .animation(.easeOut(duration: 0.25), value: isCallbackTestPageActive)
                    .overlay(alignment: .bottom) {
                        // Dropdown (higher layer, overlays quick options)
                        dropdownOverlay
                            .alignmentGuide(.bottom) { $0[.top] }
                    }
                    .zIndex(1)

                    quickOptionsOverlay
                        .frame(minHeight: showDropdown ? dropdownHeight : 0, alignment: .top)
                        .animation(.easeOut(duration: 0.15), value: useSafariWebView)
                }
                .padding(.top, max(72, geometry.size.height * 0.32 - 130))
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !StoreManager.shared.isAdRemoved {
                    let adSize = currentOrientationAnchoredAdaptiveBanner(width: geometry.size.width)
                    BannerAdView(adUnitId: AdManager.bannerAdUnitId, availableWidth: geometry.size.width)
                        .frame(width: adSize.size.width, height: adSize.size.height)
                        .background(.background)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: textFieldFocused) { _, newValue in
                withAnimation(.easeOut(duration: 0.15)) {
                    showDropdown = newValue && !filteredURLs.isEmpty
                }
            }
            .onChange(of: filteredURLs) { _, newValue in
                if textFieldFocused {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showDropdown = !newValue.isEmpty
                    }
                }
            }
        }
    }

    private var dropdownHeight: CGFloat {
        min(CGFloat(filteredURLs.count) * 40, 160)
    }

    @ViewBuilder
    var dropdownOverlay: some View {
        if showDropdown && !filteredURLs.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(filteredURLs.enumerated()), id: \.element) { index, url in
                        dropdownRow(url: url, isLast: index == filteredURLs.count - 1)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: inputWidth, height: dropdownHeight)
            .backport.glassEffect(in: .rect(cornerRadius: 16))
            .padding(.top, 8)
            .transition(.opacity)
        }
    }

    func dropdownRow(url: String, isLast: Bool) -> some View {
        Button {
            urlText = url
            textFieldFocused = false
            showDropdown = false
        } label: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Text(url)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            UIPasteboard.general.string = url
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .overlay(alignment: .trailing) {
            Button {
                removeURL(url)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    var quickOptionsOverlay: some View {
        if useSafariWebView {
            // SafariVC mode: Callback test page toggle
            VStack(spacing: 8) {
                ToggleChipButton(isOn: $useCallbackTestPage, label: "Use callback test page")
            }
            .frame(width: inputWidth)
            .padding(.top, 12)
            .transition(.opacity)
        } else {
            // WKWebView mode: Clean start and private browsing toggles
            VStack(spacing: 8) {
                ToggleChipButton(
                    isOn: Binding(get: { effectiveCleanStart }, set: setLocalCleanStart), label: "Start with fresh data"
                )
                ToggleChipButton(
                    isOn: Binding(get: { effectivePrivateBrowsing }, set: setLocalPrivateBrowsing), label: "Browse in private session"
                )
                .disabled(agentRequiresPrivateBrowsing)
                HStack(spacing: 0) {
                    // Tapping the row toggles enable/disable — same behavior as the chips above.
                    Button {
                        setPreloadProfileEnabledFromHome(!isPreloadProfileEnabled)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isPreloadProfileEnabled ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(isPreloadProfileEnabled ? .primary : .tertiary)
                                .contentTransition(.symbolEffect(.replace))

                            Text("Page Startup Setup")
                                .foregroundStyle(isPreloadProfileEnabled ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .allowsTightening(true)

                            Spacer()

                            Text(preloadProfileSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page Startup Setup")
                    .accessibilityValue(isPreloadProfileEnabled ? "On" : "Off")

                    // Gear opens the editor — works whether enabled or disabled.
                    Button {
                        openPreloadSettingsFromHome()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Page Startup Setup")
                    .accessibilityAddTraits(.isButton)
                }
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.08), value: preloadProfileSummary)
                .backport.glassEffect(in: .rect(cornerRadius: 12))
            }
            .frame(width: inputWidth)
            .padding(.top, 12)
            .transition(.opacity)
        }
    }

    var topBar: some View {
        HStack {
            HStack(spacing: 12) {
                if showWebView {
                    BackButton {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showWebView = false
                        }
                    }
                } else {
                    BookmarkButton(showBookmarks: $showBookmarks, hasBookmarks: !urlStorage.bookmarks.isEmpty)
                    AboutButton(showAbout: $showAbout)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                GlassIconButton(
                    icon: "network",
                    color: agentSession.isRunning ? .green : .primary,
                    accessibilityLabel: "Mac Agent"
                ) {
                    showAgentConnection = true
                }
                InfoSheetButton(showInfo: $showInfo)
                SettingsButton(showSettings: $showSettings)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
