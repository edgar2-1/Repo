import Foundation

/// Android `KeyEvent` key codes understood by the Android TV / Google TV
/// remote service. Raw values are the Android constants.
public enum KeyCode: Int32, CaseIterable, Sendable, Codable {
    case home = 3
    case back = 4
    case num0 = 7
    case num1 = 8
    case num2 = 9
    case num3 = 10
    case num4 = 11
    case num5 = 12
    case num6 = 13
    case num7 = 14
    case num8 = 15
    case num9 = 16
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case enter = 66
    case del = 67
    case menu = 82
    case search = 84
    case mediaPlayPause = 85
    case mediaStop = 86
    case mediaNext = 87
    case mediaPrevious = 88
    case mediaRewind = 89
    case mediaFastForward = 90
    case mute = 91
    case mediaPlay = 126
    case mediaPause = 127
    case volumeMute = 164
    case info = 165
    case channelUp = 166
    case channelDown = 167
    case tv = 170
    case guide = 172
    case captions = 175
    case settings = 176
    case tvInput = 178
    case assist = 219
    case sleep = 223
    case wakeup = 224
    case mediaSkipForward = 272
    case mediaSkipBackward = 273
}

/// How a key press is delivered.
public enum KeyDirection: Int32, Sendable {
    case unknown = 0
    case startLong = 1
    case endLong = 2
    case short = 3
}
