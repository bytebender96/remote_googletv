import SwiftUI

struct RemoteView: View {
    let device: TVDevice
    @EnvironmentObject private var store: DeviceStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: RemoteSession

    @AppStorage("useTouchpad") private var useTouchpad = false
    @State private var showKeyboard = false
    @State private var showApps = false

    init(device: TVDevice) {
        self.device = device
        _session = StateObject(wrappedValue: RemoteSession(host: device.host))
    }

    var body: some View {
        VStack(spacing: 18) {
            statusBanner

            HStack {
                CircleKey(systemImage: "power", key: .power, session: session, size: 50,
                          tint: .red, accessibilityLabel: "Power")
                Spacer()
                CircleKey(systemImage: "mic.fill", key: .assist, session: session, size: 50,
                          accessibilityLabel: "Assistant")
                CircleKey(systemImage: "rectangle.on.rectangle", key: .input, session: session, size: 50,
                          accessibilityLabel: "Input")
                CircleKey(systemImage: "gearshape.fill", key: .settings, session: session, size: 50,
                          accessibilityLabel: "Settings")
            }

            Picker("Control", selection: $useTouchpad) {
                Text("D-pad").tag(false)
                Text("Touchpad").tag(true)
            }
            .pickerStyle(.segmented)

            Group {
                if useTouchpad {
                    Touchpad(session: session, height: 250)
                } else {
                    DPad(session: session, size: 250)
                }
            }
            .frame(height: 250)

            HStack(spacing: 28) {
                CircleKey(systemImage: "arrow.uturn.backward", key: .back, session: session,
                          mode: .longPress, accessibilityLabel: "Back")
                CircleKey(systemImage: "house.fill", key: .home, session: session,
                          mode: .longPress, accessibilityLabel: "Home")
                CircleKey(systemImage: volumeMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                          key: .mute, session: session,
                          tint: volumeMuted ? .orange : .white, accessibilityLabel: "Mute")
            }

            HStack(alignment: .center) {
                Rocker(label: "VOL", upKey: .volumeUp, downKey: .volumeDown,
                       upIcon: "plus", downIcon: "minus", session: session)
                Spacer()
                VStack(spacing: 14) {
                    CircleKey(systemImage: "playpause.fill", key: .mediaPlayPause, session: session,
                              size: 64, accessibilityLabel: "Play or pause")
                    HStack(spacing: 14) {
                        CircleKey(systemImage: "backward.fill", key: .mediaRewind, session: session,
                                  size: 46, accessibilityLabel: "Rewind")
                        CircleKey(systemImage: "forward.fill", key: .mediaFastForward, session: session,
                                  size: 46, accessibilityLabel: "Fast forward")
                    }
                }
                Spacer()
                Rocker(label: "CH", upKey: .channelUp, downKey: .channelDown,
                       upIcon: "chevron.up", downIcon: "chevron.down", session: session)
            }

            volumeBar
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showKeyboard) { KeyboardSheet(session: session) }
        .sheet(isPresented: $showApps) { AppsSheet(session: session) }
        .onAppear {
            store.lastUsedHost = device.host
            session.connect()
        }
        .onDisappear { session.disconnect() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if session.state != .connected { session.connect() }
            } else if phase == .background {
                session.disconnect()
            }
        }
    }

    private var volumeMuted: Bool { session.volume?.muted ?? false }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showKeyboard = true } label: { Image(systemName: "keyboard") }
                .accessibilityLabel("Keyboard")
            Button { showApps = true } label: { Image(systemName: "square.grid.2x2") }
                .accessibilityLabel("Apps")
            Menu {
                Button { session.connect() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                Button { session.press(.guide) } label: { Label("TV guide", systemImage: "list.bullet.rectangle") }
                Button { session.press(.captions) } label: { Label("Captions", systemImage: "captions.bubble") }
                Button { session.press(.menu) } label: { Label("Menu", systemImage: "line.3.horizontal") }
                Divider()
                Button(role: .destructive) {
                    session.disconnect()
                    store.setPaired(false, host: device.host)
                } label: { Label("Pair again", systemImage: "link") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch session.state {
        case .connected:
            EmptyView()
        case .connecting, .disconnected:
            banner(icon: nil, text: "Connecting to \(device.name)…", color: .secondary)
        case .failed(let message):
            VStack(spacing: 8) {
                banner(icon: "wifi.exclamationmark",
                       text: session.mightNeedPairing
                           ? "The TV didn't accept this phone. It may need to be paired again."
                           : "Can't reach the TV. \(message)",
                       color: .orange)
                HStack {
                    Button("Retry") { session.connect() }
                        .buttonStyle(.bordered)
                    if session.mightNeedPairing {
                        Button("Pair again") {
                            session.disconnect()
                            store.setPaired(false, host: device.host)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private func banner(icon: String?, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.footnote)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    @ViewBuilder
    private var volumeBar: some View {
        if let volume = session.volume, volume.max > 0 {
            HStack(spacing: 10) {
                Image(systemName: volume.muted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.caption)
                ProgressView(value: Double(volume.level), total: Double(volume.max))
                    .tint(volume.muted ? .gray : .accentColor)
                Text("\(volume.level)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            }
            .foregroundStyle(.secondary)
        }
    }
}
