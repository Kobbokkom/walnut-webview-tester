import SwiftUI

/// The single Mac Agent state shown by the connection sheet and the toolbar button.
enum AgentConnectionState: Equatable {
    case off, starting, waitingToPair, pairingEnded, waitingForMac, connected
    case failed(String)

    var title: Text {
        switch self {
        case .off: Text("Not running")
        case .starting: Text("Starting…")
        case .waitingToPair: Text("Waiting for pairing")
        case .pairingEnded: Text("Pairing ended")
        case .waitingForMac: Text("Waiting for your Mac")
        case .connected: Text("Connected to Mac")
        case .failed(let error): Text(verbatim: error)
        }
    }

    var dotColor: Color {
        switch self {
        case .connected: .green
        case .waitingToPair, .waitingForMac, .starting: .accentColor
        case .pairingEnded, .failed: .orange
        case .off: .secondary
        }
    }

    /// Toolbar icon tint: green only when a Mac is actually connected.
    var iconColor: Color {
        switch self {
        case .connected: .green
        case .off: .primary
        default: .accentColor
        }
    }
}

extension AgentSession {
    var state: AgentConnectionState {
        if let error = pairingStorageError ?? reconnectError { return .failed(error) }
        if isConnected { return .connected }
        if isPairingAvailable { return .waitingToPair }
        if isRunning, isPairingReady { return .waitingForMac }
        if isPairingEnded { return .pairingEnded }
        if isRunning { return .starting }
        if let error = connectionError { return .failed(error) }
        return .off
    }
}
