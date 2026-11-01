# TV Remote for iOS

A native SwiftUI iPhone/iPad app that controls Google TV and Android TV devices (including Chromecast with Google TV) over your Wi-Fi network. It speaks the same **Android TV Remote v2** protocol as Google's own TV remote, so nothing needs to be installed on the TV.

## Features

- **Automatic discovery** of TVs on the network (Bonjour `_androidtvremote2._tcp`), or add one by IP address
- **One-time pairing** with the 6-character code the TV shows
- **D-pad or touchpad** (swipe to move, tap to select)
- Back, Home, Power, Input, Settings, Assistant, Mute, Volume and Channel rockers (hold to repeat)
- Media controls: play/pause, rewind, fast-forward
- Long-press OK / Home / Back for the TV's long-press actions
- **Keyboard**: type on your phone and send text to the TV's search box
- **App shortcuts**: YouTube, Netflix, Prime Video, Disney+, Max and more, plus any custom link
- Shows the TV's volume level and reconnects automatically
- Remembers paired TVs and opens the last one on launch

## Requirements

- Xcode 16 or newer (macOS)
- iOS 17 or newer
- The phone and TV on the same network

## Build and run

1. Open `RemoteTV.xcodeproj` in Xcode.
2. Select the **RemoteTV** target → **Signing & Capabilities** and pick your Team. If needed, change the bundle identifier (`com.example.RemoteTV`) to something unique.
3. Choose your iPhone as the run destination and press **Run**.
4. When iOS asks for **Local Network** access, allow it. Discovery and control do not work without it.

> The iOS Simulator can find and control TVs too, as long as your Mac is on the same network.

## Using it

1. Turn on the TV. It appears under **On this network**. Tap it (or use **Add by IP address**).
2. A code appears on the TV. Type it in the app. It submits automatically after 6 characters.
3. The remote opens. Next time the app opens straight to it.

If the TV stops accepting the phone (for example after a factory reset), use **⋯ → Pair again** on the remote screen.

## How it works

| Port | Purpose |
|------|---------|
| 6467 | Pairing. TLS with a client certificate, then a SHA-256 secret derived from both certificates' RSA keys and the on-screen code. |
| 6466 | Remote control. Length-prefixed protobuf messages for keys, text input, app links, volume and power state. |

Code layout:

- `RemoteTV/Protocol`: hand-written protobuf encoder/decoder and the pairing/remote message definitions (no third-party dependencies)
- `RemoteTV/Network`: TLS connection (Network.framework), self-signed client certificate stored in the Keychain, pairing and remote sessions, Bonjour discovery
- `RemoteTV/Views`: SwiftUI screens

## Notes

- App shortcuts use app links. A shortcut only works if the app is installed on the TV and handles that link.
- Text input sends to the focused text field on the TV. Select a search box on the TV first.
- **⋯ → Reset pairing key** on the TV list gives the phone a new identity. Every TV then needs to be paired again.
