import Foundation

struct TVDevice: Identifiable, Codable, Hashable {
    var id: String { host }
    var name: String
    var host: String
    var isPaired: Bool = false
}

/// Saved TVs, persisted in UserDefaults.
@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [TVDevice] = []
    @Published var lastUsedHost: String? {
        didSet { UserDefaults.standard.set(lastUsedHost, forKey: lastUsedKey) }
    }

    private let devicesKey = "savedDevices"
    private let lastUsedKey = "lastUsedHost"

    init() {
        if let data = UserDefaults.standard.data(forKey: devicesKey),
           let saved = try? JSONDecoder().decode([TVDevice].self, from: data) {
            devices = saved
        }
        lastUsedHost = UserDefaults.standard.string(forKey: lastUsedKey)
    }

    func device(for host: String) -> TVDevice? {
        devices.first { $0.host == host }
    }

    @discardableResult
    func upsert(name: String, host: String) -> TVDevice {
        if let index = devices.firstIndex(where: { $0.host == host }) {
            devices[index].name = name
            save()
            return devices[index]
        }
        let device = TVDevice(name: name, host: host)
        devices.append(device)
        save()
        return device
    }

    func setPaired(_ paired: Bool, host: String) {
        guard let index = devices.firstIndex(where: { $0.host == host }) else { return }
        devices[index].isPaired = paired
        save()
    }

    func remove(host: String) {
        devices.removeAll { $0.host == host }
        if lastUsedHost == host { lastUsedHost = nil }
        save()
    }

    func unpairAll() {
        for index in devices.indices { devices[index].isPaired = false }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: devicesKey)
        }
    }
}
