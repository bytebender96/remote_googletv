import Foundation
import UIKit

/// Keeps a control connection open to a paired TV on port 6466 and sends key presses.
@MainActor
final class RemoteSession: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var isPoweredOn: Bool?
    @Published private(set) var volume: (level: Int, max: Int, muted: Bool)?
    @Published private(set) var currentApp: String?
    /// True when the TV dropped us during the TLS handshake, which usually means it forgot the pairing.
    @Published private(set) var mightNeedPairing = false

    let host: String
    private var connection: MessageConnection?
    private var imeCounter = 0
    private var fieldCounter = 0
    private var everConfigured = false
    private var reconnectTask: Task<Void, Never>?
    private var shouldStayConnected = false

    init(host: String) {
        self.host = host
    }

    func connect() {
        shouldStayConnected = true
        reconnectTask?.cancel()
        connection?.cancel()
        state = .connecting
        everConfigured = false
        do {
            let identity = try CertificateManager.shared.identity()
            let connection = MessageConnection(host: host, port: 6466, identity: identity)
            connection.onEvent = { [weak self] event in self?.handle(event) }
            self.connection = connection
            connection.start()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func disconnect() {
        shouldStayConnected = false
        reconnectTask?.cancel()
        connection?.cancel()
        connection = nil
        state = .disconnected
    }

    // MARK: Commands

    func press(_ key: KeyCode) {
        send(RemoteMessage.key(key, .short))
    }

    func longPressBegan(_ key: KeyCode) {
        send(RemoteMessage.key(key, .startLong))
    }

    func longPressEnded(_ key: KeyCode) {
        send(RemoteMessage.key(key, .endLong))
    }

    func launch(_ link: String) {
        send(RemoteMessage.launchApp(link))
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        send(RemoteMessage.sendText(text, imeCounter: imeCounter, fieldCounter: fieldCounter))
    }

    private func send(_ data: Data) {
        guard state == .connected else { return }
        connection?.send(data)
    }

    // MARK: Events

    private func handle(_ event: MessageConnection.Event) {
        switch event {
        case .ready:
            mightNeedPairing = false
        case .message(let data):
            handle(RemoteMessage.parse(data))
        case .failed(let error):
            connection = nil
            // A failure before the TV ever configured us is typically a rejected certificate.
            if !everConfigured { mightNeedPairing = true }
            state = .failed(error.localizedDescription)
            scheduleReconnect()
        case .closed:
            connection = nil
            if !everConfigured { mightNeedPairing = true }
            state = .failed("Disconnected from TV")
            scheduleReconnect()
        }
    }

    private func handle(_ message: RemoteMessage.Incoming) {
        switch message {
        case .configure:
            let device = UIDevice.current
            connection?.send(RemoteMessage.configure(
                model: device.model,
                vendor: "Apple",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            ))
        case .setActive:
            connection?.send(RemoteMessage.setActive())
            everConfigured = true
            mightNeedPairing = false
            state = .connected
        case .ping(let value):
            connection?.send(RemoteMessage.pingResponse(value))
        case .power(let isOn):
            isPoweredOn = isOn
        case .volume(let level, let max, let muted):
            volume = (level, max, muted)
        case .imeCounters(let ime, let field):
            imeCounter = ime
            fieldCounter = field
        case .currentApp(let package):
            currentApp = package
        case .error, .other:
            break
        }
    }

    private func scheduleReconnect() {
        guard shouldStayConnected, !mightNeedPairing else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled, self.shouldStayConnected else { return }
            self.connect()
        }
    }
}
