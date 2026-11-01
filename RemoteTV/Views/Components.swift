import SwiftUI
import UIKit

enum Theme {
    static let background = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let surface = Color(white: 0.15)
    static let surfaceHighlight = Color(white: 0.22)
    static let stroke = Color.white.opacity(0.08)
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

enum PressMode {
    /// Fires once on release.
    case tap
    /// Short press on release; holding sends long-press start/end (e.g. OK opens context menus).
    case longPress
    /// Fires immediately, then repeats while held (volume, arrows).
    case repeating
}

/// Press handling for remote keys, with a small "pushed in" animation and haptics.
struct PressableModifier: ViewModifier {
    var mode: PressMode
    var onTap: () -> Void
    var onLongStart: () -> Void = {}
    var onLongEnd: () -> Void = {}

    @State private var isPressed = false
    @State private var longTriggered = false
    @State private var holdTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.92 : 1)
            .brightness(isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { began() } }
                    .onEnded { _ in ended() }
            )
    }

    private func began() {
        isPressed = true
        longTriggered = false
        Haptics.tap()
        switch mode {
        case .tap:
            break
        case .longPress:
            holdTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                longTriggered = true
                Haptics.heavy()
                onLongStart()
            }
        case .repeating:
            onTap()
            holdTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                while !Task.isCancelled {
                    onTap()
                    Haptics.tap()
                    try? await Task.sleep(nanoseconds: 110_000_000)
                }
            }
        }
    }

    private func ended() {
        isPressed = false
        holdTask?.cancel()
        holdTask = nil
        switch mode {
        case .tap: onTap()
        case .longPress: longTriggered ? onLongEnd() : onTap()
        case .repeating: break
        }
    }
}

extension View {
    func remoteKey(_ key: KeyCode, session: RemoteSession, mode: PressMode = .tap) -> some View {
        modifier(PressableModifier(
            mode: mode,
            onTap: { session.press(key) },
            onLongStart: { session.longPressBegan(key) },
            onLongEnd: { session.longPressEnded(key) }
        ))
    }
}

/// A round icon button that sends a key.
struct CircleKey: View {
    let systemImage: String
    let key: KeyCode
    let session: RemoteSession
    var size: CGFloat = 58
    var tint: Color = .white
    var fill: Color = Theme.surface
    var mode: PressMode = .tap
    var accessibilityLabel: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(Theme.stroke))
            .remoteKey(key, session: session, mode: mode)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { session.press(key) }
    }
}

/// Classic circular D-pad with OK in the centre.
struct DPad: View {
    let session: RemoteSession
    var size: CGFloat = 250

    var body: some View {
        let cell = size / 3
        ZStack {
            Circle()
                .fill(Theme.surface)
                .overlay(Circle().stroke(Theme.stroke))
            VStack(spacing: 0) {
                arrow(.dpadUp, "chevron.up", "Up", cell)
                HStack(spacing: 0) {
                    arrow(.dpadLeft, "chevron.left", "Left", cell)
                    Text("OK")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .frame(width: cell * 1.05, height: cell * 1.05)
                        .background(Circle().fill(Theme.surfaceHighlight))
                        .overlay(Circle().stroke(Color.white.opacity(0.12)))
                        .remoteKey(.dpadCenter, session: session, mode: .longPress)
                        .accessibilityLabel("Select")
                        .accessibilityAddTraits(.isButton)
                    arrow(.dpadRight, "chevron.right", "Right", cell)
                }
                arrow(.dpadDown, "chevron.down", "Down", cell)
            }
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ key: KeyCode, _ icon: String, _ label: String, _ cell: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: cell, height: cell)
            .remoteKey(key, session: session, mode: .repeating)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

/// Swipe to move focus, tap to select — like the Google TV app's touchpad.
struct Touchpad: View {
    let session: RemoteSession
    var height: CGFloat = 250

    @State private var anchor: CGSize = .zero
    @State private var moved = false
    @State private var touching = false
    private let step: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.stroke))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 30))
                    Text("Swipe to move · Tap to select")
                        .font(.footnote)
                }
                .foregroundStyle(.white.opacity(touching ? 0.15 : 0.35))
            )
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        touching = true
                        let dx = value.translation.width - anchor.width
                        let dy = value.translation.height - anchor.height
                        guard max(abs(dx), abs(dy)) >= step else { return }
                        let key: KeyCode
                        if abs(dx) > abs(dy) {
                            key = dx > 0 ? .dpadRight : .dpadLeft
                        } else {
                            key = dy > 0 ? .dpadDown : .dpadUp
                        }
                        session.press(key)
                        Haptics.tap()
                        moved = true
                        anchor = value.translation
                    }
                    .onEnded { _ in
                        if !moved {
                            session.press(.dpadCenter)
                            Haptics.heavy()
                        }
                        anchor = .zero
                        moved = false
                        touching = false
                    }
            )
            .accessibilityLabel("Touchpad")
    }
}

/// Tall pill with up/down keys, used for volume and channel.
struct Rocker: View {
    let label: String
    let upKey: KeyCode
    let downKey: KeyCode
    let upIcon: String
    let downIcon: String
    let session: RemoteSession

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: upIcon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 62, height: 60)
                .remoteKey(upKey, session: session, mode: .repeating)
                .accessibilityLabel("\(label) up")
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Image(systemName: downIcon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 62, height: 60)
                .remoteKey(downKey, session: session, mode: .repeating)
                .accessibilityLabel("\(label) down")
        }
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke))
    }
}
