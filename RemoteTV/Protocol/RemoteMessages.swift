import Foundation

/// Messages for the remote control protocol, spoken on port 6466.
/// Field numbers follow the RemoteMessage proto used by the Google TV app.
enum RemoteMessage {
    private enum Field {
        static let configure = 1
        static let setActive = 2
        static let error = 3
        static let pingRequest = 8
        static let pingResponse = 9
        static let keyInject = 10
        static let imeKeyInject = 20
        static let imeBatchEdit = 21
        static let start = 40
        static let setVolumeLevel = 50
        static let appLinkLaunch = 90
    }

    /// Feature bitmask announced to the TV (ping, key, IME, power, volume, app links).
    static let features = 622

    enum KeyDirection: UInt64 {
        case startLong = 1
        case endLong = 2
        case short = 3
    }

    static func configure(model: String, vendor: String, appVersion: String) -> Data {
        var w = ProtoWriter()
        w.message(Field.configure) { c in
            c.int(1, features)
            c.message(2) { d in
                d.string(1, model)
                d.string(2, vendor)
                d.int(3, 1)
                d.string(4, "1")
                d.string(5, "atvremote")
                d.string(6, appVersion)
            }
        }
        return w.data
    }

    static func setActive() -> Data {
        var w = ProtoWriter()
        w.message(Field.setActive) { $0.int(1, features) }
        return w.data
    }

    static func pingResponse(_ value: Int) -> Data {
        var w = ProtoWriter()
        w.message(Field.pingResponse) { $0.int(1, value) }
        return w.data
    }

    static func key(_ code: KeyCode, _ direction: KeyDirection) -> Data {
        var w = ProtoWriter()
        w.message(Field.keyInject) { k in
            k.uint(1, UInt64(code.rawValue))
            k.uint(2, direction.rawValue)
        }
        return w.data
    }

    static func launchApp(_ link: String) -> Data {
        var w = ProtoWriter()
        w.message(Field.appLinkLaunch) { $0.string(1, link) }
        return w.data
    }

    static func sendText(_ text: String, imeCounter: Int, fieldCounter: Int) -> Data {
        let cursor = max(text.count - 1, 0)
        var w = ProtoWriter()
        w.message(Field.imeBatchEdit) { b in
            b.int(1, imeCounter)
            b.int(2, fieldCounter)
            b.message(3) { e in
                e.int(1, 1)
                e.message(2) { o in
                    o.int(1, cursor)
                    o.int(2, cursor)
                    o.string(3, text)
                }
            }
        }
        return w.data
    }

    enum Incoming {
        case configure
        case setActive
        case ping(Int)
        case power(isOn: Bool)
        case volume(level: Int, max: Int, muted: Bool)
        case imeCounters(ime: Int, field: Int)
        case currentApp(String)
        case error
        case other
    }

    static func parse(_ data: Data) -> Incoming {
        guard let msg = try? ProtoMessage(data) else { return .other }
        if msg.has(Field.configure) { return .configure }
        if msg.has(Field.setActive) { return .setActive }
        if let ping = msg.message(Field.pingRequest) { return .ping(ping.int(1) ?? 0) }
        if let start = msg.message(Field.start) { return .power(isOn: start.bool(1) ?? false) }
        if let vol = msg.message(Field.setVolumeLevel) {
            return .volume(level: vol.int(9) ?? 0, max: vol.int(8) ?? 100, muted: vol.bool(10) ?? false)
        }
        if let edit = msg.message(Field.imeBatchEdit) {
            return .imeCounters(ime: edit.int(1) ?? 0, field: edit.int(2) ?? 0)
        }
        if let ime = msg.message(Field.imeKeyInject),
           let package = ime.message(1)?.string(12), !package.isEmpty {
            return .currentApp(package)
        }
        if msg.has(Field.error) { return .error }
        return .other
    }
}
