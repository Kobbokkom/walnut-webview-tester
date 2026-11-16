import SwiftUI
import SwiftUIBackports

struct ChipButton: View {
    private let label: Text
    private let accessibilityText: Text
    let action: () -> Void

    /// UI text: literals are localized.
    init(label: LocalizedStringKey, accessibilityLabel: LocalizedStringKey? = nil, action: @escaping () -> Void) {
        self.label = Text(label)
        self.accessibilityText = Text(accessibilityLabel ?? label)
        self.action = action
    }

    /// Runtime data (URL parts, page-provided names): shown verbatim.
    init<S: StringProtocol>(label: S, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.label = Text(verbatim: String(label))
        self.accessibilityText = accessibilityLabel.map { Text(verbatim: $0) } ?? Text("Insert \(String(label))")
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .backport.glassEffect(in: .capsule)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}
