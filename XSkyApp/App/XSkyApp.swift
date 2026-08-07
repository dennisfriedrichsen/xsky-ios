import SwiftUI
import XSkyCore

@main
struct XSkyApp: App {
    @State private var workspace = WorkspaceModel()

    init() {
        // UI-test hooks: reset persisted state for deterministic runs
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            if let url = try? WorkspacePersistence.defaultFileURL() {
                try? FileManager.default.removeItem(at: url)
            }
            if let dir = try? WorkspaceModel.userCatalogDirectory() {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environment(workspace)
                .preferredColorScheme(.dark)
                .task {
                    // UI-test hook: import the bundled example user catalog
                    // (the system file picker cannot be automated)
                    if ProcessInfo.processInfo.arguments.contains(
                        "-uitest-import-example"),
                        let url = Bundle.main.url(
                            forResource: "usercat", withExtension: "example")
                    {
                        while workspace.loadState == .loading {
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        await workspace.importUserCatalog(from: url)
                    }
                }
        }
    }
}
