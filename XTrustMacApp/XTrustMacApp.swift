import SwiftUI

@main
struct XTrustMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var launchState = AppLaunchState()

    var body: some Scene {
        WindowGroup {
            Group {
                if let appState = launchState.appState {
                    SessionListView(appState: appState)
                } else {
                    AppLaunchErrorView(errorMessage: launchState.errorMessage)
                }
            }
            .frame(minWidth: 960, minHeight: 600)
        }
    }
}

@MainActor
final class AppLaunchState: ObservableObject {
    @Published var appState: AppState?
    @Published var errorMessage: String?

    init() {
        do {
            self.appState = try AppState.bootstrap()
            self.errorMessage = nil
        } catch {
            self.appState = nil
            self.errorMessage = error.localizedDescription
        }
    }
}

struct AppLaunchErrorView: View {
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Launch Failed")
                .font(.title)
                .fontWeight(.semibold)

            Text(errorMessage ?? "Unknown launch error.")
                .foregroundStyle(.red)
                .textSelection(.enabled)

            Text("The app did not start a fallback workspace or substitute services.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
