//
//  OverlayMenuBars+URLInput.swift
//  wina
//
//  URL Input overlay view for OverlayMenuBars.
//

import SwiftUI
import SwiftUIBackports

// MARK: - URL Input Overlay View

struct URLInputOverlayView: View {
    @Binding var urlInputText: String
    @Binding var showURLInput: Bool
    @Binding var showBookmarks: Bool
    let urlStorage: URLStorageManager
    let currentURL: String?
    let onURLChange: (String) -> Bool

    @FocusState private var urlInputFocused: Bool
    @State private var feedbackState = CopiedFeedbackState()

    private var urlValidationState: URLValidationState {
        guard !urlInputText.isEmpty else { return .empty }
        return URLValidator.isValidURL(urlInputText) ? .valid : .invalid
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    urlInputFocused = false
                    showURLInput = false
                }

            // Input card
            VStack(spacing: 8) {
                // Bookmark controls (moved up to free input space)
                bookmarkRow

                // URL input row
                urlInputRow

                // History section - 4 items height with scroll
                ScrollView {
                    historySection
                }
                .frame(height: 220)  // Taller list for better scan
                .scrollBounceBehavior(.basedOnSize)

                // Cancel button
                Button {
                    urlInputFocused = false
                    showURLInput = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .frame(width: 340)
            .backport.glassEffect(in: .rect(cornerRadius: 24))
            .copiedFeedbackOverlay($feedbackState.message)
        }
        .onAppear {
            urlInputFocused = true
        }
    }

    // MARK: - Bookmark Row

    private var bookmarkRow: some View {
        HStack {
            // Copy current URL button
            if let currentURL, !currentURL.isEmpty {
                Button {
                    UIPasteboard.general.string = currentURL
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    feedbackState.showCopied()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                urlInputFocused = false
                showURLInput = false
                showBookmarks = true
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            if let currentURL, !currentURL.isEmpty {
                let isBookmarked = urlStorage.isBookmarked(currentURL)
                Button {
                    urlStorage.toggleBookmark(currentURL)
                } label: {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(isBookmarked ? .yellow : .secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
    }

    // MARK: - URL Input Row

    // Fixed widths to prevent layout shift (matching Home pattern)
    private let inputRowWidth: CGFloat = 308  // 340 card - 32 padding
    private let goButtonSpace: CGFloat = 60   // 48 button + 12 spacing

    private var urlInputRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: urlValidationState.iconName)
                    .foregroundStyle(urlValidationState.iconColor)
                    .font(.system(size: 16))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeOut(duration: 0.2), value: urlValidationState)

                // URL TextField
                TextField("Enter URL", text: $urlInputText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .font(.system(size: 16))
                    .focused($urlInputFocused)
                    .onSubmit {
                        submitURL()
                    }

                // Clear button
                if !urlInputText.isEmpty {
                    Button {
                        urlInputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .frame(width: urlValidationState == .valid ? inputRowWidth - goButtonSpace : inputRowWidth)
            .backport.glassEffect(in: .capsule)

            // Go button - matching Home design
            if urlValidationState == .valid {
                Button {
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
        .frame(height: 48)
        .animation(.easeOut(duration: 0.25), value: urlValidationState)
    }

    private func submitURL() {
        guard urlValidationState == .valid, onURLChange(urlInputText) else { return }
        showURLInput = false
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        let history = urlStorage.history
        let filtered = urlInputText.isEmpty ? history : history.filter {
            $0.localizedCaseInsensitiveContains(urlInputText)
        }

        if filtered.isEmpty {
            Text(history.isEmpty ? "No history yet" : "No matches")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element) { index, url in
                    historyRow(url: url, isLast: index == filtered.count - 1)
                }
            }
        }
    }

    private func historyRow(url: String, isLast: Bool) -> some View {
        Button {
            // Only fill input, user submits manually
            urlInputText = url
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Text(url)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
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
                urlStorage.removeFromHistory(url)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
                    .padding(.horizontal, 12)
            }
        }
    }
}
