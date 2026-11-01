import Foundation

/// Messages for the pairing ("polo") protocol, spoken on port 6467.
/// Field numbers follow Google's polo.proto.
enum PairingMessage {
    static let protocolVersion: UInt64 = 2
    static let statusOK: UInt64 = 200

    private enum Field {
        static let protocolVersion = 1
        static let status = 2
        static let pairingRequest = 10
        static let pairingRequestAck = 11
        static let options = 20
        static let configuration = 30
        static let configurationAck = 31
        static let secret = 40
        static let secretAck = 41
    }

    private static let encodingHexadecimal: UInt64 = 3
    private static let roleInput: UInt64 = 1
    private static let codeLength: UInt64 = 6

    private static func outer(_ build: (inout ProtoWriter) -> Void) -> Data {
        var w = ProtoWriter()
        w.uint(Field.protocolVersion, protocolVersion)
        w.uint(Field.status, statusOK)
        build(&w)
        return w.data
    }

    private static func writeEncoding(_ w: inout ProtoWriter) {
        w.uint(1, encodingHexadecimal)
        w.uint(2, codeLength)
    }

    static func pairingRequest(clientName: String) -> Data {
        outer { w in
            w.message(Field.pairingRequest) { r in
                r.string(1, "atvremote")
                r.string(2, clientName)
            }
        }
    }

    static func options() -> Data {
        outer { w in
            w.message(Field.options) { o in
                o.message(1) { writeEncoding(&$0) }
                o.uint(3, roleInput)
            }
        }
    }

    static func configuration() -> Data {
        outer { w in
            w.message(Field.configuration) { c in
                c.message(1) { writeEncoding(&$0) }
                c.uint(2, roleInput)
            }
        }
    }

    static func secret(_ secret: Data) -> Data {
        outer { w in
            w.message(Field.secret) { $0.bytes(1, secret) }
        }
    }

    enum Incoming {
        case pairingRequestAck
        case options
        case configurationAck
        case secretAck
        case error(status: UInt64)
        case unknown
    }

    static func parse(_ data: Data) -> Incoming {
        guard let msg = try? ProtoMessage(data) else { return .unknown }
        let status = msg.uint(Field.status) ?? 0
        if status != statusOK { return .error(status: status) }
        if msg.has(Field.pairingRequestAck) { return .pairingRequestAck }
        if msg.has(Field.options) { return .options }
        if msg.has(Field.configurationAck) { return .configurationAck }
        if msg.has(Field.secretAck) { return .secretAck }
        return .unknown
    }
}
