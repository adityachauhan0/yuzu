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
        }
        .defaultSize(width: 1440, height: 900)
    }
}
