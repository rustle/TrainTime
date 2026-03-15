import SwiftUI

@main
struct TrainTimeApp: App {
    struct AppErrorView: View {
        let titleText: LocalizedStringKey
        let titleSystemImage: String
        let messageText: LocalizedStringKey?
        let buttonText: LocalizedStringKey
        let buttonRole: ButtonRole?
        let action: @MainActor () async -> Void
        var body: some View {
            VStack(spacing: 12) {
                Label(titleText, systemImage: titleSystemImage)
                    .font(.title)
                if let messageText = messageText {
                    Text(messageText)
                        .font(.body)
                }
                Button(buttonText,
                       role: buttonRole) {
                    Task { @MainActor in
                        await action()
                    }
                }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    @State var state = TrainTimeAppState()
    var body: some Scene {
        WindowGroup {
            if let stationListComponent = state.stationListComponent {
                StationList(component: stationListComponent)
            } else if let loadError = state.loadError {
                switch loadError {
                case .transient:
                    AppErrorView(
                        titleText: "OH NO!",
                        titleSystemImage: "exclamationmark.triangle",
                        messageText: nil,
                        buttonText: "Try Again",
                        buttonRole: nil
                    ) {
                        await state.load()
                    }
                case .corruptDatabase:
                    AppErrorView(
                        titleText: "Database Not Found",
                        titleSystemImage: "exclamationmark.triangle",
                        messageText: "Delete Local Database and Try Again?",
                        buttonText: "Delete",
                        buttonRole: .destructive
                    ) {
                        await state.resetAndReload()
                    }
                case .fatal:
                    Text("Unknown Error")
                        .font(.title)
                    // TODO: Check for update button?
                    // TODO: Link out to KB?
                    // TODO: Send logs?
                }
            } else {
                Group {
                    ProgressView()
                }
                    .task {
                        await state.load()
                    }
            }
        }
    }
}
