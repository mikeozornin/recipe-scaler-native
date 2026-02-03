//
//  WebSocketService.swift
//  RecipeScalerNative
//
//

import Foundation
import SocketIO

@MainActor
class WebSocketService: ObservableObject {
    static let shared = WebSocketService()

    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var userId: String?
    private var deviceId: String

    enum ConnectionStatus {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    private init() {
        // Generate or load device ID
        if let storedDeviceId = UserDefaults.standard.string(forKey: "deviceId") {
            self.deviceId = storedDeviceId
        } else {
            self.deviceId = UUID().uuidString
            UserDefaults.standard.set(deviceId, forKey: "deviceId")
        }
    }

    // MARK: - Configuration
    func configure(serverURL: String, userId: String) {
        self.userId = userId

        guard let url = URL(string: serverURL) else {
            connectionStatus = .error("Invalid server URL")
            return
        }

        // Socket.IO configuration
        let config: SocketIOClientConfiguration = [
            .log(false),
            .compress,
            .reconnects(true),
            .reconnectAttempts(-1), // Infinite reconnect attempts
            .reconnectWait(1000),
            .forceWebsockets(true),
            .connectParams(["userId": userId, "deviceId": deviceId])
        ]

        manager = SocketManager(socketURL: url, config: config)
        socket = manager?.defaultSocket

        setupEventHandlers()
    }

    // MARK: - Connection Management
    func connect() {
        guard socket != nil else {
            connectionStatus = .error("Socket not configured")
            return
        }

        connectionStatus = .connecting
        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
        connectionStatus = .disconnected
        isConnected = false
    }

    // MARK: - Event Handlers
    private func setupEventHandlers() {
        guard let socket = socket else { return }

        // Connection events
        socket.on(clientEvent: .connect) { [weak self] data, ack in
            Task { @MainActor in
                self?.isConnected = true
                self?.connectionStatus = .connected
                print("✅ WebSocket connected")
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] data, ack in
            Task { @MainActor in
                self?.isConnected = false
                self?.connectionStatus = .disconnected
                print("❌ WebSocket disconnected")
            }
        }

        socket.on(clientEvent: .error) { [weak self] data, ack in
            Task { @MainActor in
                let errorMessage = data.first as? String ?? "Unknown error"
                self?.connectionStatus = .error(errorMessage)
                print("⚠️ WebSocket error: \(errorMessage)")
            }
        }

        socket.on(clientEvent: .reconnect) { data, ack in
            print("🔄 WebSocket reconnecting...")
        }

        socket.on(clientEvent: .reconnectAttempt) { data, ack in
            let attempt = data.first as? Int ?? 0
            print("🔄 Reconnect attempt: \(attempt)")
        }

        // Server events - Notifications only (no Yjs data)
        socket.on("connected") { data, ack in
            print("📡 Server acknowledged connection")
        }

        socket.on("sync_confirmed") { [weak self] data, ack in
            Task { @MainActor in
                await self?.handleSyncConfirmed(data: data)
            }
        }

        socket.on("document_loaded") { [weak self] data, ack in
            Task { @MainActor in
                await self?.handleDocumentLoaded(data: data)
            }
        }

        socket.on("collection_updated") { [weak self] data, ack in
            Task { @MainActor in
                await self?.handleCollectionUpdated(data: data)
            }
        }

        socket.on("sync_error") { data, ack in
            if let errorDict = data.first as? [String: Any],
               let error = errorDict["error"] as? String {
                print("⚠️ Sync error: \(error)")
            }
        }
    }

    // MARK: - Event Handlers (Notifications)
    private func handleSyncConfirmed(data: [Any]) async {
        guard let payload = data.first as? [String: Any],
              let recipeId = payload["recipeId"] as? String else {
            return
        }

        print("📥 Recipe synced: \(recipeId)")

        // Trigger refresh from REST API
        NotificationCenter.default.post(
            name: .recipeUpdated,
            object: nil,
            userInfo: ["recipeId": recipeId]
        )
    }

    private func handleDocumentLoaded(data: [Any]) async {
        guard let payload = data.first as? [String: Any],
              let recipeId = payload["recipeId"] as? String else {
            return
        }

        print("📥 Document loaded: \(recipeId)")

        // Note: We ignore yjsState since we can't parse it without yswift
        // Instead, trigger REST API fetch
        NotificationCenter.default.post(
            name: .recipeUpdated,
            object: nil,
            userInfo: ["recipeId": recipeId]
        )
    }

    private func handleCollectionUpdated(data: [Any]) async {
        print("📥 Collection updated")

        // Trigger full recipes list refresh
        NotificationCenter.default.post(
            name: .recipesListUpdated,
            object: nil
        )
    }

    // MARK: - Send Events (for future write support)
    func loadDocument(recipeId: String) {
        guard let socket = socket, isConnected else { return }

        socket.emit("load_document", [
            "userId": userId ?? "",
            "recipeId": recipeId
        ])
    }

    func loadDocuments(recipeIds: [String]) {
        guard let socket = socket, isConnected else { return }

        socket.emit("load_documents", [
            "userId": userId ?? "",
            "recipeIds": recipeIds
        ])
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let recipeUpdated = Notification.Name("recipeUpdated")
    static let recipesListUpdated = Notification.Name("recipesListUpdated")
}
