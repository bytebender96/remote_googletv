import Foundation
import Network
import Security

/// A TLS connection to the TV that sends and receives length-prefixed protobuf messages.
/// All callbacks are delivered on the main queue.
final class MessageConnection {
    enum Event {
        case ready(serverCertificate: SecCertificate?)
        case message(Data)
        case failed(Error)
        case closed
    }

    var onEvent: ((Event) -> Void)?

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private let certificateBox: CertificateBox
    private var finished = false

    private final class CertificateBox {
        var certificate: SecCertificate?
    }

    init(host: String, port: UInt16, identity: SecIdentity) {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)

        // The TV uses a self-signed certificate. We accept it and keep it, because pairing
        // mixes the TV's public key into the secret.
        let box = CertificateBox()
        let queue = DispatchQueue(label: "remotetv.connection")
        self.certificateBox = box
        self.queue = queue
        sec_protocol_options_set_verify_block(sec, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate] {
                box.certificate = chain.first
            }
            complete(true)
        }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 6
        tcp.noDelay = true

        let parameters = NWParameters(tls: tls, tcp: tcp)
        connection = NWConnection(host: NWEndpoint.Host(host),
                                  port: NWEndpoint.Port(rawValue: port)!,
                                  using: parameters)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let cert = self.certificateBox.certificate
                self.emit(.ready(serverCertificate: cert))
                self.receive()
            case .waiting(let error), .failed(let error):
                self.fail(error)
            case .cancelled:
                self.finish(.closed)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ message: Data) {
        var w = ProtoWriter()
        w.varint(UInt64(message.count))
        connection.send(content: w.data + message, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail(error) }
        })
    }

    func cancel() {
        finished = true
        onEvent = nil
        connection.cancel()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainBuffer()
            }
            if let error {
                self.fail(error)
            } else if isComplete {
                self.finish(.closed)
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }

    private func drainBuffer() {
        while let (length, prefix) = decodeVarintPrefix(buffer), buffer.count >= prefix + length {
            let start = buffer.startIndex + prefix
            let message = buffer.subdata(in: start..<(start + length))
            buffer = buffer.subdata(in: (start + length)..<buffer.endIndex)
            emit(.message(message))
        }
    }

    private func fail(_ error: Error) {
        finish(.failed(error))
        connection.cancel()
    }

    private func finish(_ event: Event) {
        guard !finished else { return }
        finished = true
        emit(event)
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
