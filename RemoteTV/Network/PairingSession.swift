import CryptoKit
import Foundation
import Security
import UIKit

/// Runs the pairing handshake with a TV on port 6467.
/// Flow: request -> options -> configuration -> TV shows a 6-character code -> we send the secret.
@MainActor
final class PairingSession: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case waitingForCode
        case verifying
        case paired
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Set when the typed code doesn't match what the TV is showing.
    @Published var wrongCodeHint = false

    private let host: String
    private var connection: MessageConnection?
    private var serverCertificate: SecCertificate?

    init(host: String) {
        self.host = host
    }

    func start() {
        cancel()
        state = .connecting
        do {
            let identity = try CertificateManager.shared.identity()
            let connection = MessageConnection(host: host, port: 6467, identity: identity)
            connection.onEvent = { [weak self] event in self?.handle(event) }
            self.connection = connection
            connection.start()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func submit(code rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard state == .waitingForCode else { return }
        wrongCodeHint = false
        guard code.count == 6, let codeBytes = Data(hex: code) else {
            wrongCodeHint = true
            return
        }
        guard let secret = computeSecret(codeBytes: codeBytes) else { return }
        state = .verifying
        connection?.send(PairingMessage.secret(secret))
    }

    func cancel() {
        connection?.cancel()
        connection = nil
    }

    private func handle(_ event: MessageConnection.Event) {
        switch event {
        case .ready(let cert):
            serverCertificate = cert
            connection?.send(PairingMessage.pairingRequest(clientName: UIDevice.current.name))
        case .message(let data):
            handle(PairingMessage.parse(data))
        case .failed(let error):
            failIfActive("Couldn't connect: \(error.localizedDescription)")
        case .closed:
            failIfActive("The TV closed the connection.")
        }
    }

    private func failIfActive(_ message: String) {
        switch state {
        case .paired, .failed: break
        default: state = .failed(message)
        }
    }

    private func handle(_ message: PairingMessage.Incoming) {
        switch message {
        case .pairingRequestAck:
            connection?.send(PairingMessage.options())
        case .options:
            connection?.send(PairingMessage.configuration())
        case .configurationAck:
            state = .waitingForCode
        case .secretAck:
            state = .paired
            cancel()
        case .error(let status):
            state = .failed(status == 402 ? "Wrong code. Try again." : "The TV rejected pairing (status \(status)).")
            cancel()
        case .unknown:
            break
        }
    }

    /// secret = SHA256(clientModulus + clientExponent + serverModulus + serverExponent + code[1...2]).
    /// The first byte of the code is a checksum that must match the first byte of the hash.
    private func computeSecret(codeBytes: Data) -> Data? {
        guard let identity = try? CertificateManager.shared.identity(),
              let client = Self.rsaComponents(of: identity),
              let serverCertificate,
              let server = Self.rsaComponents(of: serverCertificate) else {
            state = .failed("Could not read the TLS certificates.")
            return nil
        }

        var hasher = SHA256()
        hasher.update(data: client.modulus)
        hasher.update(data: client.exponent)
        hasher.update(data: server.modulus)
        hasher.update(data: server.exponent)
        hasher.update(data: codeBytes.suffix(2))
        let digest = Data(hasher.finalize())

        guard digest.first == codeBytes.first else {
            // Typo in the code: keep the session open so the user can retype it.
            wrongCodeHint = true
            return nil
        }
        wrongCodeHint = false
        return digest
    }

    private static func rsaComponents(of identity: SecIdentity) -> (modulus: Data, exponent: Data)? {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else { return nil }
        return rsaComponents(of: certificate)
    }

    private static func rsaComponents(of certificate: SecCertificate) -> (modulus: Data, exponent: Data)? {
        guard let key = SecCertificateCopyKey(certificate),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return DER.rsaComponents(data)
    }
}

extension Data {
    init?(hex: String) {
        var bytes: [UInt8] = []
        var chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        while !chars.isEmpty {
            guard let b = UInt8(String(chars.prefix(2)), radix: 16) else { return nil }
            bytes.append(b)
            chars.removeFirst(2)
        }
        self.init(bytes)
    }
}
