import Foundation
import Security

enum CertificateError: LocalizedError {
    case keyGeneration(String)
    case signing(String)
    case keychain(OSStatus)
    case invalidCertificate
    case identityNotFound

    var errorDescription: String? {
        switch self {
        case .keyGeneration(let m): return "Could not create key: \(m)"
        case .signing(let m): return "Could not sign certificate: \(m)"
        case .keychain(let s): return "Keychain error \(s)"
        case .invalidCertificate: return "Generated certificate was invalid"
        case .identityNotFound: return "Client identity not found in keychain"
        }
    }
}

/// Creates and stores the self-signed client certificate the TV uses to recognise this phone.
/// The TV remembers the certificate after pairing, so it must stay the same between launches.
final class CertificateManager {
    static let shared = CertificateManager()

    private let keyTag = Data("com.remotetv.client.key".utf8)
    private let certLabel = "RemoteTV Client Certificate"
    private var cached: SecIdentity?

    func identity() throws -> SecIdentity {
        if let cached { return cached }
        if let existing = loadIdentity() {
            cached = existing
            return existing
        }
        try generate()
        guard let created = loadIdentity() else { throw CertificateError.identityNotFound }
        cached = created
        return created
    }

    /// Deletes the stored identity. Every TV will need to be paired again afterwards.
    func reset() {
        cached = nil
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: keyTag] as CFDictionary)
        SecItemDelete([kSecClass: kSecClassCertificate, kSecAttrLabel: certLabel] as CFDictionary)
    }

    private func loadIdentity() -> SecIdentity? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: certLabel,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item else { return nil }
        return (item as! SecIdentity)
    }

    private func generate() throws {
        reset()

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: keyTag,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as [CFString: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CertificateError.keyGeneration(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }

        let certDER = try Self.makeSelfSignedCertificate(publicKeyPKCS1: publicKeyData, privateKey: privateKey)
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw CertificateError.invalidCertificate
        }

        let status = SecItemAdd([
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: certLabel,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CertificateError.keychain(status)
        }
    }

    // MARK: - X.509 construction (DER)

    private static func makeSelfSignedCertificate(publicKeyPKCS1: Data, privateKey: SecKey) throws -> Data {
        let sha256WithRSA = DER.sequence([DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]), DER.null])
        let rsaEncryption = DER.sequence([DER.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]), DER.null])

        let name = DER.sequence([
            DER.set([DER.sequence([DER.oid([0x55, 0x04, 0x03]), DER.utf8String("atvremote")])]),
        ])

        var serial = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial)
        serial[0] &= 0x7F
        serial[0] |= 0x01

        let now = Date()
        let notBefore = now.addingTimeInterval(-86_400)
        let notAfter = now.addingTimeInterval(20 * 365 * 86_400)

        let tbs = DER.sequence([
            DER.contextExplicit(0, DER.integer([0x02])),
            DER.integer(serial),
            sha256WithRSA,
            name,
            DER.sequence([DER.time(notBefore), DER.time(notAfter)]),
            name,
            DER.sequence([rsaEncryption, DER.bitString(publicKeyPKCS1)]),
        ])

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                    tbs as CFData, &error) as Data? else {
            throw CertificateError.signing(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }

        return DER.sequence([tbs, sha256WithRSA, DER.bitString(signature)])
    }
}

/// Tiny DER encoder for the handful of ASN.1 types a certificate needs.
enum DER {
    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let n = content.count
        if n < 0x80 {
            out.append(UInt8(n))
        } else {
            var lengthBytes: [UInt8] = []
            var v = n
            while v > 0 {
                lengthBytes.insert(UInt8(v & 0xFF), at: 0)
                v >>= 8
            }
            out.append(0x80 | UInt8(lengthBytes.count))
            out.append(contentsOf: lengthBytes)
        }
        out.append(content)
        return out
    }

    static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }
    static func set(_ items: [Data]) -> Data { tlv(0x31, items.reduce(Data(), +)) }
    static func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }
    static var null: Data { Data([0x05, 0x00]) }
    static func utf8String(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }
    static func bitString(_ d: Data) -> Data { tlv(0x03, Data([0x00]) + d) }
    static func contextExplicit(_ n: UInt8, _ d: Data) -> Data { tlv(0xA0 | n, d) }

    static func integer(_ bytes: [UInt8]) -> Data {
        var b = Array(bytes.drop(while: { $0 == 0 }))
        if b.isEmpty { b = [0] }
        if b[0] & 0x80 != 0 { b.insert(0, at: 0) }
        return tlv(0x02, Data(b))
    }

    static func time(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let year = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date).year ?? 2000
        if year < 2050 {
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            return tlv(0x17, Data(formatter.string(from: date).utf8))
        }
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return tlv(0x18, Data(formatter.string(from: date).utf8))
    }

    /// Reads (modulus, exponent) from a PKCS#1 RSAPublicKey, with leading zero bytes removed.
    static func rsaComponents(_ pkcs1: Data) -> (modulus: Data, exponent: Data)? {
        let b = [UInt8](pkcs1)
        var i = 0

        func readLength() -> Int? {
            guard i < b.count else { return nil }
            let first = b[i]; i += 1
            if first < 0x80 { return Int(first) }
            let count = Int(first & 0x7F)
            guard count <= 4, i + count <= b.count else { return nil }
            var len = 0
            for _ in 0..<count { len = len << 8 | Int(b[i]); i += 1 }
            return len
        }

        func readInteger() -> Data? {
            guard i < b.count, b[i] == 0x02 else { return nil }
            i += 1
            guard let len = readLength(), i + len <= b.count else { return nil }
            let value = Data(b[i..<(i + len)].drop(while: { $0 == 0 }))
            i += len
            return value
        }

        guard b.first == 0x30 else { return nil }
        i = 1
        guard readLength() != nil, let n = readInteger(), let e = readInteger() else { return nil }
        return (n, e)
    }
}
