//
//  CopyButton.swift
//  wina
//
//  Reusable button components for section headers and actions.
//

import SwiftUI
import SwiftUIBackports

// MARK: - Header Action Button

/// Compact action button for section headers with icon and text label
struct HeaderActionButton: View {
    let label: LocalizedStringKey
    let icon: String
    var isDisabled: Bool = false
    var accessibilityLabel: LocalizedStringKey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .backport.glassEffect(in: .capsule)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Copy Button (Header Style)

/// Copy button with icon and text label for section headers
struct CopyButton: View {
    let text: String
    var label: LocalizedStringKey = "Copy"
    var onCopy: (() -> Void)?

    var body: some View {
        Button {
            guard !text.isEmpty else { return }
            UIPasteboard.general.string = text
            onCopy?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                Text(label)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .backport.glassEffect(in: .capsule)
        .disabled(text.isEmpty)
        .accessibilityLabel("Copy to clipboard")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Copy Icon Button

/// Compact copy button with icon only
struct CopyIconButton: View {
    let text: String
    var size: GlassIconButton.Size = .small
    var onCopy: (() -> Void)?

    var body: some View {
        GlassIconButton(
            icon: "doc.on.doc",
            size: size,
            accessibilityLabel: "Copy to clipboard"
        ) {
            guard !text.isEmpty else { return }
            UIPasteboard.general.string = text
            onCopy?()
        }
        .disabled(text.isEmpty)
    }
}

// MARK: - Copied Feedback Toast

/// Toast message for copy feedback
struct CopiedFeedbackToast: View {
    private let text: Text

    /// Shows text that is already localized (for example from `CopiedFeedbackState`).
    @_disfavoredOverload
    init(message: String) {
        self.text = Text(verbatim: message)
    }

    /// Localizes a literal message key.
    init(message: LocalizedStringKey) {
        self.text = Text(message)
    }

    var body: some View {
        text
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.8), in: Capsule())
            .padding(.bottom, 20)
    }
}

// MARK: - Copied Feedback State

/// Observable state for managing copy feedback across views
@Observable
final class CopiedFeedbackState {
    /// Already-localized text shown by `copiedFeedbackOverlay`.
    var message: String?

    func show(_ message: String.LocalizationValue) {
        show(verbatim: String.app(message))
    }

    func show(verbatim message: String) {
        self.message = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                if self.message == message {
                    self.message = nil
                }
            }
        }
    }

    /// Pass a localized `label` (for example `String.app("Key")`); technical labels such as "URL" can stay as-is.
    func showCopied(_ label: String? = nil) {
        if let label { show("\(label) copied") } else { show("Copied") }
    }
}

// MARK: - Copied Feedback View Modifier

/// View modifier that provides copy feedback overlay and state management
struct CopiedFeedbackModifier: ViewModifier {
    @Binding var feedback: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = feedback {
                    CopiedFeedbackToast(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: feedback)
    }
}

extension View {
    /// Adds copy feedback overlay with auto-dismiss behavior
    /// Usage: .copiedFeedbackOverlay($copiedFeedback)
    func copiedFeedbackOverlay(_ feedback: Binding<String?>) -> some View {
        modifier(CopiedFeedbackModifier(feedback: feedback))
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            Text("Key")
            Spacer()
            CopyButton(text: "some-key-value")
        }

        HStack {
            Text("Actions")
            Spacer()
            HeaderActionButton(label: "Edit", icon: "pencil") { }
            HeaderActionButton(label: "Encode", icon: "arrow.right.circle") { }
        }

        HStack {
            Text("URL")
            Spacer()
            CopyIconButton(text: "https://example.com")
        }
    }
    .padding()
}
