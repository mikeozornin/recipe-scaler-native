import Foundation

/// Connection state machine for the Socket.IO sync connection.
enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayLabel: String {
        switch self {
        case .disconnected:
            return String(localized: "connection.state.disconnected")
        case .connecting:
            return String(localized: "connection.state.connecting")
        case .connected:
            return String(localized: "connection.state.connected")
        case .reconnecting:
            return String(localized: "connection.state.reconnecting")
        case .error(let message):
            return String(format: String(localized: "connection.state.error"), locale: .current, message)
        }
    }
}
