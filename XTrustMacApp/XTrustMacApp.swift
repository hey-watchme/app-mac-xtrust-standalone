import Observation
import SwiftUI

@main
struct XTrustMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var launchModel = AppLaunchModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let model = launchModel.model {
                    MeetingListView(model: model)
                } else {
                    AppLaunchErrorView(errorMessage: launchModel.errorMessage)
                }
            }
            .frame(minWidth: 1060, minHeight: 660)
        }
    }
}

@MainActor
@Observable
final class AppLaunchModel {
    var model: AppModel?
    var errorMessage: String?

    init() {
        do {
            self.model = try AppModel.bootstrap()
            self.errorMessage = nil
        } catch {
            self.model = nil
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
