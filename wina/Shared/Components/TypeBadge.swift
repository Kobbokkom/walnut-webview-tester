//
//  TypeBadge.swift
//  wina
//
//  Reusable type badge component for content type indicators.
//

import SwiftUI

struct TypeBadge: View {
    private let text: Text
    let color: Color
    var icon: String?

    /// UI text: literals are localized.
    init(text: LocalizedStringKey, color: Color, icon: String? = nil) {
        self.text = Text(text)
        self.color = color
        self.icon = icon
    }

    /// Runtime data (e.g. a content-type token): shown verbatim.
    init<S: StringProtocol>(text: S, color: Color, icon: String? = nil) {
        self.text = Text(verbatim: String(text))
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            text
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color, in: RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    HStack(spacing: 8) {
        TypeBadge(text: "JSON", color: .purple, icon: "curlybraces")
        TypeBadge(text: "#", color: .blue)
        TypeBadge(text: "Bool", color: .green, icon: "checkmark")
    }
    .padding()
}
