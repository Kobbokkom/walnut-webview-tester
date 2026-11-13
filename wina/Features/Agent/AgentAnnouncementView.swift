import SwiftUI
import UIKit

extension View {
    func agentAnnouncement(openConnection: Binding<Bool>, canPresent: Bool, preferredScheme: ColorScheme?) -> some View {
        modifier(AgentAnnouncementPresentation(
            openConnection: openConnection, canPresent: canPresent, preferredScheme: preferredScheme
        ))
    }
}

private struct AgentAnnouncementPresentation: ViewModifier {
    @Binding var openConnection: Bool
    let canPresent: Bool
    let preferredScheme: ColorScheme?
    @State private var isPresented = false
    @State private var opensConnectionOnDismiss = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: openConnectionIfRequested) {
                AgentAnnouncementView {
                    opensConnectionOnDismiss = true
                    isPresented = false
                }
                .preferredColorScheme(preferredScheme)
            }
            .task(id: canPresent) {
                guard canPresent, !UserDefaults.standard.bool(forKey: AgentAnnouncementView.seenKey) else { return }
                isPresented = true
            }
    }

    private func openConnectionIfRequested() {
        guard opensConnectionOnDismiss else { return }
        opensConnectionOnDismiss = false
        openConnection = true
    }
}

struct AgentAnnouncementView: View {
    static let seenKey = "hasSeenMacAgentAnnouncement"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var copyFeedback = CopiedFeedbackState()

    let openMacAgent: () -> Void
    private var usesTabletForm: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        @Bindable var feedback = copyFeedback
        ScrollView {
            VStack(alignment: .leading, spacing: usesTabletForm ? 12 : 18) {
                introduction
                installation
                location
                if !usesTabletForm { actions }
            }
            .frame(maxWidth: 472, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, usesTabletForm ? 16 : 20)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesTabletForm {
                actions
                    .frame(maxWidth: 472)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .background(Color(uiColor: .systemBackground))
        .copiedFeedbackOverlay($feedback.message)
        .presentationDetents([dynamicTypeSize.isAccessibilitySize ? .large : .fraction(0.80)])
        .presentationSizing(.form)
        .presentationDragIndicator(.visible)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear {
            UserDefaults.standard.set(true, forKey: Self.seenKey)
            headingFocused = true
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(.macAgentAnnouncement)
                .resizable()
                .scaledToFit()
                .frame(width: 165, height: usesTabletForm ? 72 : 96)
                .accessibilityHidden(true)
            Text("Test web pages from your Mac")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text("Use your Mac’s terminal or coding agent to interact with pages in Walnut’s WKWebView and inspect console and network logs.")
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.72))
        }
    }

    private var installation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Install on your Mac")
                .font(.callout.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("If you have Homebrew, run these commands in Terminal.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.72))

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: AgentConnectionView.installCommands)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.vertical, 10)
                Divider()
                Button {
                    UIPasteboard.general.string = AgentConnectionView.installCommands
                    copyFeedback.show("Install commands copied")
                    UIAccessibility.post(notification: .announcement, argument: String(localized: "Install commands copied"))
                } label: {
                    Label("Copy install commands", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 13)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private var location: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "network")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Find Mac Agent again")
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("On the home screen, tap the network icon at the top to open Mac Agent.")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.72))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 2) {
            Button(action: openMacAgent) {
                Text("Open Mac Agent")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)

            Button { dismiss() } label: {
                Text("Not now")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .multilineTextAlignment(.center)
    }
}
