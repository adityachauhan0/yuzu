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

extension View {
    func dismissesOnEscape(_ isPresented: Binding<Bool>) -> some View {
        modifier(EscapeDismiss(isPresented: isPresented.wrappedValue) { isPresented.wrappedValue = false })
    }

    func dismissesOnEscape(when isPresented: Bool, close: @escaping () -> Void) -> some View {
        modifier(EscapeDismiss(isPresented: isPresented, close: close))
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
