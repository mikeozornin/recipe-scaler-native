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

/// Active Socket.IO transport strategy (shown in debug sync status).
enum SyncConnectionTransport: String, Sendable, Equatable {
    case websocketOnly
    case pollingAndWebsocket

    var displayLabel: String {
        switch self {
        case .websocketOnly:
            return String(localized: "sync.status.transport.websocket")
        case .pollingAndWebsocket:
            return String(localized: "sync.status.transport.polling")
        }
    }
}
