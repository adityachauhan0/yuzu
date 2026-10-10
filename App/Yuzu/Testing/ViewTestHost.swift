import AppKit
import SwiftUI

@MainActor
enum ViewTestHost {
    static func host<V: View>(
        _ view: V,
        size: CGSize = CGSize(width: 1440, height: 900)
    ) -> NSHostingView<V> {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    static func collectAccessibilityStrings(from view: NSView) -> [String] {
        var results: [String] = []
        walk(view) { element in
            let id = element.accessibilityIdentifier()
            if !id.isEmpty {
                results.append(id)
            }
            if let label = element.accessibilityLabel(), !label.isEmpty {
                results.append(label)
            }
            if let value = element.accessibilityValue() as? String, !value.isEmpty {
                results.append(value)
            }
            if let title = element.accessibilityTitle(), !title.isEmpty {
                results.append(title)
            }
        }
        return results
    }

    static func containsIdentifier(_ identifier: String, in view: NSView) -> Bool {
        var found = false
        walk(view) { element in
            if element.accessibilityIdentifier() == identifier {
                found = true
            }
        }
        return found
    }

    private static func walk(_ view: NSView, visit: (NSView) -> Void) {
        visit(view)
        for child in view.subviews {
            walk(child, visit: visit)
        }
    }
}
