import SwiftUI

/// Opens the Mac Agent sheet and shows the connection (or agent recording) state.
struct MacAgentButton: View {
    let session: AgentSession
    var isRecording = false
    let action: () -> Void

    var body: some View {
        GlassIconButton(
            icon: isRecording ? "record.circle.fill" : "network",
            color: isRecording ? .red : session.state.iconColor,
            accessibilityLabel: isRecording ? "Mac Agent recording" : "Mac Agent",
            action: action
        )
        .accessibilityValue(session.state.title)
    }
}
