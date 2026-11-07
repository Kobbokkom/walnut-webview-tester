//
//  DevToolsHeader.swift
//  wina
//
//  Shared header component for Console, Network, Storage views.
//

import SwiftUI
import SwiftUIBackports

struct DevToolsHeader: View {
    let title: LocalizedStringKey
    let leftButtons: [HeaderButton]
    let rightButtons: [HeaderButton]

    /// Convenience init for dynamic string titles (e.g., filenames)
    init(
        title: String,
        leftButtons: [HeaderButton],
        rightButtons: [HeaderButton]
    ) {
        // Use verbatim to prevent localization lookup for dynamic strings
        self.title = LocalizedStringKey(stringLiteral: title)
        self.leftButtons = leftButtons
        self.rightButtons = rightButtons
    }

    /// Primary init for localized titles
    init(
        title: LocalizedStringKey,
        leftButtons: [HeaderButton],
        rightButtons: [HeaderButton]
    ) {
        self.title = title
        self.leftButtons = leftButtons
        self.rightButtons = rightButtons
    }

    struct HeaderButton: Identifiable {
        let id = UUID()
        let icon: String
        let activeIcon: String?
        let color: Color
        let activeColor: Color?
        let isActive: Bool
        let isDisabled: Bool
        let action: () -> Void

        init(
            icon: String,
            activeIcon: String? = nil,
            color: Color = .primary,
            activeColor: Color? = nil,
            isActive: Bool = false,
            isDisabled: Bool = false,
            action: @escaping () -> Void
        ) {
            self.icon = icon
            self.activeIcon = activeIcon
            self.color = color
            self.activeColor = activeColor
            self.isActive = isActive
            self.isDisabled = isDisabled
            self.action = action
        }

        var currentIcon: String {
            if isActive, let activeIcon {
                return activeIcon
            }
            return icon
        }

        var currentColor: Color {
            if isActive, let activeColor {
                return activeColor
            }
            return isDisabled ? Color.secondary.opacity(0.5) : color
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Row 1: Title
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            ViewThatFits(in: .horizontal) {
                buttonRow
                ScrollView(.horizontal) { buttonRow }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var buttonRow: some View {
        HStack(spacing: 16) {
            buttonGroup(leftButtons)
            Spacer(minLength: 0)
            buttonGroup(rightButtons)
        }
    }

    @ViewBuilder
    private func buttonGroup(_ buttons: [HeaderButton]) -> some View {
        HStack(spacing: 2) {
            ForEach(buttons) { button in
                Button {
                    button.action()
                } label: {
                    Image(systemName: button.currentIcon)
                        .font(.system(size: 17))
                        .foregroundStyle(button.currentColor.opacity(button.isDisabled ? 0.4 : 0.8))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .disabled(button.isDisabled)
                .accessibilityIdentifier(button.icon == "xmark.circle.fill" ? "closeDevTools" : button.icon)
            }
        }
    }
}

#Preview {
    VStack {
        DevToolsHeader(
            title: "Console",
            leftButtons: [
                .init(icon: "xmark.circle.fill", color: .secondary) {},
                .init(icon: "trash", isDisabled: true) {},
                .init(icon: "square.and.arrow.up") {}
            ],
            rightButtons: [
                .init(
                    icon: "play.fill",
                    activeIcon: "pause.fill",
                    color: .green,
                    activeColor: .red,
                    isActive: true
                ) {},
                .init(
                    icon: "gearshape",
                    activeIcon: "gearshape.fill",
                    color: .secondary,
                    activeColor: .blue,
                    isActive: false
                ) {}
            ]
        )
        Spacer()
    }
}
