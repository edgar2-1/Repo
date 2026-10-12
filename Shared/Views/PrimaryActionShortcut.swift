import SwiftUI

extension View {
    /// On Apple Watch Series 9 / Ultra 2 and later, the Double Tap gesture
    /// triggers this view. Needs the watchOS 11 SDK (Xcode 16); older
    /// toolchains compile it away.
    @ViewBuilder
    func doubleTapPrimaryAction() -> some View {
        #if os(watchOS) && compiler(>=6.0)
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
