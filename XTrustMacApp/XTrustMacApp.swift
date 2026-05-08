import SwiftUI

@main
struct XTrustMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.bootstrap()

    var body: some Scene {
        WindowGroup {
            SessionListView(appState: appState)
                .frame(minWidth: 960, minHeight: 600)
        }
    }
}
