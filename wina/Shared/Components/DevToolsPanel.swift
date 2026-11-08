import SwiftUI

struct DevToolsPanel<Content: View>: View {
    @Environment(\.agentBrowserSettings) private var agentSettings
    let state: DevToolsOverlayState
    @ViewBuilder let content: () -> Content
    @AppStorage("toolbarItemsOrder") private var toolbarItemsOrder = Data()

    private var tools: [DevToolsOverlay] {
        let order = agentSettings?.value("toolbarItemsOrder", fallback: toolbarItemsOrder) ?? toolbarItemsOrder
        return state.dockedTools(in: ToolbarSettings.visibleItems(from: order))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tools, id: \.self) { tool in
                        if let item = tool.menuItem {
                            Button {
                                state.open(tool)
                            } label: {
                                Label(item.label, systemImage: item.icon)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 44)
                                    .background(state.selectedTool == tool ? Color.accentColor.opacity(0.15) : .clear,
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("devToolsTab.\(tool.rawValue)")
                            .accessibilityAddTraits(state.selectedTool == tool ? .isSelected : [])
                        }
                    }
                }
                .padding(8)
            }
            Divider()
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("devToolsPanel")
    }
}
