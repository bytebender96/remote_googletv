import Foundation

/// Minimal protobuf encoder. Covers only what the Android TV Remote v2 protocol needs,
/// so the app has no third-party dependencies.
struct ProtoWriter {
    private(set) var data = Data()

    mutating func varint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private mutating func tag(_ field: Int, _ wireType: Int) {
        varint(UInt64(field << 3 | wireType))
    }

    mutating func uint(_ field: Int, _ value: UInt64) {
        tag(field, 0)
        varint(value)
    }

    mutating func int(_ field: Int, _ value: Int) {
        tag(field, 0)
        varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        uint(field, value ? 1 : 0)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Data(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.data)
    }
}

enum ProtoError: Error {
    case truncated
    case unsupportedWireType(Int)
}

/// Minimal protobuf decoder: parses a message into a field-number -> values map.
struct ProtoMessage {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
        case fixed64(UInt64)
    }

    private(set) var fields: [Int: [Value]] = [:]

    init(_ input: Data) throws {
        let bytes = [UInt8](input)
        var i = 0

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard i < bytes.count, shift < 64 else { throw ProtoError.truncated }
                let b = bytes[i]
                i += 1
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
        }

        func readFixed(_ count: Int) throws -> UInt64 {
            guard i + count <= bytes.count else { throw ProtoError.truncated }
            var v: UInt64 = 0
            for k in 0..<count { v |= UInt64(bytes[i + k]) << (8 * UInt64(k)) }
            i += count
            return v
        }

        while i < bytes.count {
            let key = try readVarint()
            let field = Int(key >> 3)
            let wireType = Int(key & 0x7)
            let value: Value
            switch wireType {
            case 0:
                value = .varint(try readVarint())
            case 1:
                value = .fixed64(try readFixed(8))
            case 2:
                let length = Int(try readVarint())
                guard length >= 0, i + length <= bytes.count else { throw ProtoError.truncated }
                value = .bytes(Data(bytes[i..<(i + length)]))
                i += length
            case 5:
                value = .fixed32(UInt32(try readFixed(4)))
            default:
                throw ProtoError.unsupportedWireType(wireType)
            }
            fields[field, default: []].append(value)
        }
    }

    func has(_ field: Int) -> Bool { fields[field] != nil }

    func uint(_ field: Int) -> UInt64? {
        if case .varint(let v)? = fields[field]?.last { return v }
        return nil
    }

    func int(_ field: Int) -> Int? {
        uint(field).map { Int(truncatingIfNeeded: Int64(bitPattern: $0)) }
    }

    func bool(_ field: Int) -> Bool? {
        uint(field).map { $0 != 0 }
    }

    func bytes(_ field: Int) -> Data? {
        if case .bytes(let d)? = fields[field]?.last { return d }
        return nil
    }

    func string(_ field: Int) -> String? {
        bytes(field).flatMap { String(data: $0, encoding: .utf8) }
    }

    func message(_ field: Int) -> ProtoMessage? {
        bytes(field).flatMap { try? ProtoMessage($0) }
    }
}

/// Reads a varint from the front of a buffer. Returns nil if more bytes are needed.
func decodeVarintPrefix(_ buffer: Data) -> (value: Int, length: Int)? {
    var result = 0
    var shift = 0
    var count = 0
    for byte in buffer {
        count += 1
        result |= Int(byte & 0x7F) << shift
        if byte & 0x80 == 0 { return (result, count) }
        shift += 7
        if shift > 28 { return nil }
    }
    return nil
}
