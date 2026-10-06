import Foundation
#if os(watchOS)
import WatchKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Platform-neutral haptic feedback.
enum Haptics {
    enum Kind {
        case click, start, success, failure
    }

    @MainActor
    static func play(_ kind: Kind) {
        #if os(watchOS)
        let type: WKHapticType
        switch kind {
        case .click: type = .click
        case .start: type = .start
        case .success: type = .success
        case .failure: type = .failure
        }
        WKInterfaceDevice.current().play(type)
        #elseif canImport(UIKit)
        switch kind {
        case .click:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .start:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}
