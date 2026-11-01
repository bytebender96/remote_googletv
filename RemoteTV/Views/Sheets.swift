import SwiftUI

/// Type on the phone and send the text to the focused text field on the TV.
struct KeyboardSheet: View {
    @ObservedObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Type to send to the TV", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.send)
                    .focused($focused)
                    .onSubmit(send)

                HStack(spacing: 12) {
                    Button {
                        session.press(.delete)
                    } label: {
                        Label("Delete", systemImage: "delete.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        session.press(.enter)
                    } label: {
                        Label("Enter", systemImage: "return")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: send) {
                        Label("Send", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                }

                Text("Select a search box or text field on the TV first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260)])
        .onAppear { focused = true }
    }

    private func send() {
        session.sendText(text)
        text = ""
        Haptics.tap()
    }
}

struct TVApp: Identifiable {
    var id: String { name }
    let name: String
    let symbol: String
    let color: Color
    let link: String
}

/// Quick-launch shortcuts. Launching uses app links the TV resolves to installed apps.
struct AppsSheet: View {
    @ObservedObject var session: RemoteSession
    @Environment(\.dismiss) private var dismiss
    @State private var customLink = ""

    static let apps: [TVApp] = [
        TVApp(name: "YouTube", symbol: "play.rectangle.fill", color: .red, link: "https://www.youtube.com"),
        TVApp(name: "Netflix", symbol: "n.square.fill", color: Color(red: 0.9, green: 0.04, blue: 0.08),
              link: "https://www.netflix.com/title"),
        TVApp(name: "Prime Video", symbol: "play.tv.fill", color: Color(red: 0.0, green: 0.66, blue: 0.88),
              link: "https://app.primevideo.com"),
        TVApp(name: "Disney+", symbol: "sparkles.tv.fill", color: Color(red: 0.07, green: 0.2, blue: 0.6),
              link: "https://www.disneyplus.com"),
        TVApp(name: "Max", symbol: "m.square.fill", color: Color(red: 0.0, green: 0.2, blue: 0.9),
              link: "https://play.max.com"),
        TVApp(name: "Spotify", symbol: "music.note", color: .green, link: "spotify://"),
        TVApp(name: "YouTube Music", symbol: "music.note.tv.fill", color: .red, link: "https://music.youtube.com"),
        TVApp(name: "Twitch", symbol: "gamecontroller.fill", color: .purple, link: "twitch://home"),
        TVApp(name: "Plex", symbol: "play.circle.fill", color: .orange, link: "plex://"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 18) {
                    ForEach(Self.apps) { app in
                        Button {
                            session.launch(app.link)
                            Haptics.tap()
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: app.symbol)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 64, height: 64)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(app.color))
                                Text(app.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Open a link on the TV")
                        .font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("https://… or app://", text: $customLink)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Open") {
                            session.launch(customLink)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customLink.isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
