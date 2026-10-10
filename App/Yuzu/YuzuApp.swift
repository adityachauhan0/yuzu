import AppKit
import SwiftUI

@main
struct YuzuApp: App {
    @StateObject private var model: AppModel = {
        do {
            return try AppModel.makeForLaunch()
        } catch {
            fatalError("Failed to start Yuzu: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
                .ignoresSafeArea(.container, edges: .top)
                .background(WindowChrome())
                .onAppear {
                    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let image = NSImage(contentsOf: url) {
                        NSApplication.shared.applicationIconImage = image
                    }
                    model.applyLaunchRouteIfNeeded()
                    model.startScheduleWatch()
                    Task {
                        await model.applySavedMCPConfig()
                        await model.prepareAdvisedModel()
                    }
                }
        }
        .commands {
            CommandGroup(after: .sidebar) {
                Button(model.sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") {
                    model.sidebarCollapsed.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    model.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
