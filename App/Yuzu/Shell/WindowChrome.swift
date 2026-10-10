import AppKit
import SwiftUI

/// Hides the title bar and seats the window's real traffic lights in the sidebar's 54pt bar.
struct WindowChrome: NSViewRepresentable {
    static let barHeight: CGFloat = 54
    static let leading: CGFloat = 16
    static let spacing: CGFloat = 9
    static let buttonSize: CGFloat = 14
    static let trafficLightsWidth: CGFloat = buttonSize * 3 + spacing * 2

    func makeNSView(context: Context) -> ChromeView {
        ChromeView()
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.seat()
    }

    final class ChromeView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            // AppKit puts the buttons back on resize, key changes, and full screen exits.
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.seat() }
                }
            }
            seat()
        }

        override func layout() {
            super.layout()
            seat()
        }

        func seat() {
            guard let window,
                  !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview,
                  let container = titlebar.superview else { return }
            let height = WindowChrome.barHeight
            // Only as wide as the buttons, so clicks on the sidebar's own bar controls reach SwiftUI.
            let width = WindowChrome.leading * 2 + WindowChrome.trafficLightsWidth
            container.frame = NSRect(x: 0, y: window.frame.height - height, width: width, height: height)
            titlebar.frame = container.bounds
            let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (index, kind) in kinds.enumerated() {
                guard let button = window.standardWindowButton(kind) else { continue }
                let x = WindowChrome.leading + CGFloat(index) * (WindowChrome.buttonSize + WindowChrome.spacing)
                button.setFrameOrigin(NSPoint(x: x, y: (height - button.frame.height) / 2))
            }
        }
    }
}
