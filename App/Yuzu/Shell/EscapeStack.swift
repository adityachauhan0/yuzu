import AppKit
import SwiftUI

/// Popovers and dialogs that Escape closes, newest first. Window-level layers
/// (Settings, search, changelog, the inspector) close after these are gone.
@MainActor
final class EscapeStack {
    private var entries: [(id: UUID, close: () -> Void)] = []

    func push(_ id: UUID, close: @escaping () -> Void) {
        entries.removeAll { $0.id == id }
        entries.append((id, close))
    }

    func pop(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Closes the newest layer. `false` when nothing was open.
    func closeTop() -> Bool {
        guard let top = entries.popLast() else { return false }
        top.close()
        return true
    }
}

private struct EscapeDismiss: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let isPresented: Bool
    let close: () -> Void
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, open in
                if open {
                    model.escapeStack.push(id, close: close)
                } else {
                    model.escapeStack.pop(id)
                }
            }
            .onDisappear { model.escapeStack.pop(id) }
    }
}

/// Menus that a click anywhere else in the window should close.
@MainActor
final class OutsideClickStack {
    private var entries: [(id: UUID, close: () -> Void)] = []

    func push(_ id: UUID, close: @escaping () -> Void) {
        entries.removeAll { $0.id == id }
        entries.append((id, close))
    }

    func pop(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func closeAll() {
        let pending = entries
        entries.removeAll()
        pending.forEach { $0.close() }
    }
}

private struct OutsideClickDismiss: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let isPresented: Bool
    let close: () -> Void
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, open in
                if open {
                    model.outsideClicks.push(id, close: close)
                } else {
                    model.outsideClicks.pop(id)
                }
            }
            .onDisappear { model.outsideClicks.pop(id) }
    }
}

extension View {
    func dismissesOnOutsideClick(_ isPresented: Binding<Bool>) -> some View {
        modifier(OutsideClickDismiss(isPresented: isPresented.wrappedValue) {
            isPresented.wrappedValue = false
        })
    }

    func dismissesOnEscape(_ isPresented: Binding<Bool>) -> some View {
        modifier(EscapeDismiss(isPresented: isPresented.wrappedValue) { isPresented.wrappedValue = false })
    }

    func dismissesOnEscape(when isPresented: Bool, close: @escaping () -> Void) -> some View {
        modifier(EscapeDismiss(isPresented: isPresented, close: close))
    }
}

/// Frames of open menus and the buttons that show them, in window coordinates.
/// A click outside every frame closes those menus.
final class PopupChromeRegistry: @unchecked Sendable {
    static let shared = PopupChromeRegistry()
    private var frames: [UUID: CGRect] = [:]

    func set(_ id: UUID, _ frame: CGRect) {
        frames[id] = frame
    }

    func remove(_ id: UUID) {
        frames[id] = nil
    }

    func contains(_ point: NSPoint) -> Bool {
        frames.values.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
    }
}

struct PopupChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> Marker { Marker() }

    func updateNSView(_ nsView: Marker, context: Context) {
        nsView.syncFrame()
    }

    static func dismantleNSView(_ nsView: Marker, coordinator: ()) {
        PopupChromeRegistry.shared.remove(nsView.id)
    }

    final class Marker: NSView {
        let id = UUID()

        override func layout() {
            super.layout()
            syncFrame()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                PopupChromeRegistry.shared.remove(id)
            } else {
                syncFrame()
            }
        }

        func syncFrame() {
            guard window != nil else { return }
            PopupChromeRegistry.shared.set(id, convert(bounds, to: nil))
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    /// Marks a menu or the button that opens it, so a click there is not an outside click.
    func popupChrome() -> some View {
        background(PopupChrome())
    }
}

/// Closes registered menus when the click misses all of them.
struct OutsideClickMonitor: NSViewRepresentable {
    let close: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(close: close)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.close = close
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator {
        var close: (() -> Void)?
        private var monitor: Any?

        func install(close: @escaping () -> Void) {
            self.close = close
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let inside = PopupChromeRegistry.shared.contains(event.locationInWindow)
                if !inside {
                    self?.close?()
                }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

/// Routes the window's Escape key to `AppModel.handleEscape()`.
struct EscapeKeyMonitor: NSViewRepresentable {
    let handle: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(handle: handle)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handle = handle
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator {
        var handle: (() -> Bool)?
        private var monitor: Any?

        func install(handle: @escaping () -> Bool) {
            self.handle = handle
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      let handle = self?.handle else { return event }
                return handle() ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
