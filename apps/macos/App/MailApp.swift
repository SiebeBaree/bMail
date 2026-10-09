import DesignSystem
import SwiftUI

@main
struct MailApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("bMail", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands { MenuCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
