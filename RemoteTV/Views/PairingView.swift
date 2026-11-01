import SwiftUI

struct PairingView: View {
    let device: TVDevice
    @EnvironmentObject private var store: DeviceStore
    @StateObject private var session: PairingSession
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    init(device: TVDevice) {
        self.device = device
        _session = StateObject(wrappedValue: PairingSession(host: device.host))
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 40)

            Text("Pair with \(device.name)")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            content
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.start() }
        .onDisappear { session.cancel() }
        .onChange(of: session.state) { _, state in
            switch state {
            case .waitingForCode:
                codeFocused = true
            case .paired:
                store.setPaired(true, host: device.host)
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .idle, .connecting:
            ProgressView("Connecting to your TV…")
        case .waitingForCode, .verifying:
            VStack(spacing: 16) {
                Text("Enter the code shown on your TV")
                    .foregroundStyle(.secondary)

                TextField("", text: $code, prompt: Text("ABC123").foregroundStyle(.white.opacity(0.2)))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    .onChange(of: code) { _, newValue in
                        let filtered = String(newValue.uppercased().filter { $0.isHexDigit }.prefix(6))
                        if filtered != newValue {
                            code = filtered
                        } else if filtered.count == 6 {
                            submit()
                        }
                    }
                    .disabled(session.state == .verifying)

                if session.wrongCodeHint {
                    Label("That code doesn't match. Check the TV and try again.", systemImage: "xmark.octagon")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if session.state == .verifying {
                    ProgressView("Pairing…")
                } else {
                    Button("Pair", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(code.count != 6)
                }
            }
        case .paired:
            Label("Paired!", systemImage: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(spacing: 16) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
                Text("Make sure the TV is on and on the same Wi-Fi network as this phone.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    code = ""
                    session.start()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func submit() {
        guard code.count == 6 else { return }
        session.submit(code: code)
        if session.wrongCodeHint { code = "" }
    }
}
