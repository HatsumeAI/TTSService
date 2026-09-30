import SwiftUI

@main
struct SayTTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app is driven entirely by the status item; there is no main window.
        Settings {
            SettingsView(model: AppModel.shared)
        }
    }
}
