import SwiftUI

/// Exposes a stable AppKit accessibility identifier (and optional label) for UI evals.
struct AccessibilityID: NSViewRepresentable {
    let identifier: String
    var label: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(true)
        view.setAccessibilityIdentifier(identifier)
        if let label {
            view.setAccessibilityLabel(label)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityIdentifier(identifier)
        if let label {
            nsView.setAccessibilityLabel(label)
        }
    }
}

extension View {
    func accessibilityID(_ identifier: String, label: String? = nil) -> some View {
        background(AccessibilityID(identifier: identifier, label: label).frame(width: 0, height: 0))
    }
}
