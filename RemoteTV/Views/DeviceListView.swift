import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var store: DeviceStore
    @StateObject private var discovery = DeviceDiscovery()
    @State private var path: [String] = []
    @State private var showingAdd = false
    @State private var didAutoOpen = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !store.devices.isEmpty {
                    Section("My TVs") {
                        ForEach(store.devices) { device in
                            Button { path.append(device.host) } label: {
                                DeviceRow(name: device.name, detail: device.host,
                                          badge: device.isPaired ? "Paired" : nil)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { store.devices[$0].host }.forEach(store.remove)
                        }
                    }
                }

                Section {
                    let newDevices = discovery.devices.filter { found in
                        !store.devices.contains { $0.host == found.host || $0.name == found.name }
                    }
                    if newDevices.isEmpty {
                        Text(discovery.isSearching ? "Looking for TVs…" : "No TVs found")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(newDevices) { found in
                        Button {
                            guard let host = found.host else { return }
                            store.upsert(name: found.name, host: host)
                            path.append(host)
                        } label: {
                            DeviceRow(name: found.name, detail: found.host ?? "Resolving…", badge: nil)
                        }
                        .disabled(found.host == nil)
                    }
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add by IP address", systemImage: "plus.circle")
                    }
                } header: {
                    HStack {
                        Text("On this network")
                        if discovery.isSearching { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    Text("Your phone and TV need to be on the same Wi-Fi network. Works with Google TV and Android TV devices, including Chromecast with Google TV.")
                }
            }
            .navigationTitle("TV Remote")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { discovery.start() } label: { Label("Search again", systemImage: "arrow.clockwise") }
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Reset pairing key", systemImage: "key")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable { discovery.start() }
            .navigationDestination(for: String.self) { host in
                DeviceScreen(host: host)
            }
            .sheet(isPresented: $showingAdd) {
                AddDeviceSheet { name, host in
                    store.upsert(name: name, host: host)
                    path.append(host)
                }
            }
            .confirmationDialog("Reset pairing key?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    CertificateManager.shared.reset()
                    store.unpairAll()
                }
            } message: {
                Text("This phone gets a new identity, and every TV will need to be paired again.")
            }
        }
        .onAppear {
            discovery.start()
            // Jump straight to the last used remote on launch.
            if !didAutoOpen, let host = store.lastUsedHost, store.device(for: host)?.isPaired == true {
                path = [host]
            }
            didAutoOpen = true
        }
    }
}

private struct DeviceRow: View {
    let name: String
    let detail: String
    let badge: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Shows the pairing flow until the TV is paired, then the remote.
struct DeviceScreen: View {
    let host: String
    @EnvironmentObject private var store: DeviceStore

    var body: some View {
        if let device = store.device(for: host) {
            if device.isPaired {
                RemoteView(device: device)
            } else {
                PairingView(device: device)
            }
        } else {
            Text("This TV was removed.")
                .foregroundStyle(.secondary)
        }
    }
}

struct AddDeviceSheet: View {
    var onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP address (e.g. 192.168.1.50)", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Name (optional)", text: $name)
                } footer: {
                    Text("Find the IP address on your TV under Settings › Network & Internet.")
                }
            }
            .navigationTitle("Add TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        dismiss()
                        onAdd(trimmedName.isEmpty ? trimmedHost : trimmedName, trimmedHost)
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
