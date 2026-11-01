import Foundation
import Network

/// Finds Google TV / Android TV devices on the local network via Bonjour
/// (service type `_androidtvremote2._tcp`) and resolves their IP addresses.
@MainActor
final class DeviceDiscovery: ObservableObject {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        let name: String
        var host: String?
    }

    @Published private(set) var devices: [Found] = []
    @Published private(set) var isSearching = false

    private var browser: NWBrowser?
    private var resolvers: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "remotetv.discovery")

    func start() {
        stop()
        isSearching = true
        let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names: [(String, NWEndpoint)] = results.compactMap { result in
                if case .service(let name, _, _, _) = result.endpoint { return (name, result.endpoint) }
                return nil
            }
            DispatchQueue.main.async { self?.update(names) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                DispatchQueue.main.async { self?.isSearching = false }
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        isSearching = false
    }

    private func update(_ results: [(String, NWEndpoint)]) {
        let names = Set(results.map(\.0))
        devices.removeAll { !names.contains($0.name) }
        for (name, endpoint) in results where !devices.contains(where: { $0.name == name }) {
            devices.append(Found(name: name, host: nil))
            resolve(name: name, endpoint: endpoint)
        }
        devices.sort { $0.name < $1.name }
    }

    /// Opens a short TCP connection to the service just to learn its IPv4 address.
    private func resolve(name: String, endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        resolvers[name] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                var host: String?
                if case .hostPort(let h, _)? = connection?.currentPath?.remoteEndpoint {
                    host = Self.string(for: h)
                }
                connection?.cancel()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.resolvers[name] = nil
                    if let host, let index = self.devices.firstIndex(where: { $0.name == name }) {
                        self.devices[index].host = host
                    }
                }
            case .failed, .waiting:
                connection?.cancel()
                DispatchQueue.main.async { self?.resolvers[name] = nil }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    nonisolated private static func string(for host: NWEndpoint.Host) -> String {
        var text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): text = name
        @unknown default: text = "\(host)"
        }
        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
        return text
    }
}
