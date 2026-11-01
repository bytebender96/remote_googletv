import Foundation

/// Android KeyEvent key codes accepted by the TV.
enum KeyCode: Int {
    case home = 3
    case back = 4
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case enter = 66
    case delete = 67
    case menu = 82
    case search = 84
    case mediaPlayPause = 85
    case mediaNext = 87
    case mediaPrevious = 88
    case mediaRewind = 89
    case mediaFastForward = 90
    case mute = 164
    case channelUp = 166
    case channelDown = 167
    case guide = 172
    case captions = 175
    case settings = 176
    case input = 178
    case assist = 219
}
