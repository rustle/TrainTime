import SwiftUI

@main
struct TrainTimeApp: App {
    struct AppErrorView: View {
        let titleText: LocalizedStringKey
        let titleSystemImage: String
        let messageText: LocalizedStringKey?
        let buttonText: LocalizedStringKey?
        let buttonRole: ButtonRole?
        let action: (@MainActor () async -> Void)?
        init(titleText: LocalizedStringKey,
             titleSystemImage: String,
             messageText: LocalizedStringKey? = nil,
             buttonText: LocalizedStringKey? = nil,
             buttonRole: ButtonRole? = nil,
             action: (@MainActor () async -> Void)? = nil) {
            self.titleText = titleText
            self.titleSystemImage = titleSystemImage
            self.messageText = messageText
            self.buttonText = buttonText
            self.buttonRole = buttonRole
            self.action = action
        }
        var body: some View {
            VStack(spacing: 12) {
                Label(titleText, systemImage: titleSystemImage)
                    .font(.title)
                if let messageText = messageText {
                    Text(messageText)
                        .font(.body)
                }
                if let buttonText, let action {
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
    }
    private func errorView(for loadError: TrainTimeAppState.LoadError) -> some View {
            switch loadError {
            case .transient:
                return AppErrorView(
                    titleText: "OH NO!",
                    titleSystemImage: "exclamationmark.triangle",
                    buttonText: "Try Again",
                ) {
                    await state.load()
                }
            case .corruptCache:
                return AppErrorView(
                    titleText: "Database Not Found",
                    titleSystemImage: "exclamationmark.triangle",
                    messageText: "Delete Local Database and Try Again?",
                    buttonText: "Delete",
                    buttonRole: .destructive
                ) {
                    await state.resetCacheAndReload()
                }
            case .corruptUserData:
                return AppErrorView(
                    titleText: "Database Not Found",
                    titleSystemImage: "exclamationmark.triangle",
                    messageText: "Delete All Local Data and Try Again?",
                    buttonText: "Delete",
                    buttonRole: .destructive
                ) {
                    await state.resetAllAndReload()
                }
            case .fatal:
                return AppErrorView(
                    titleText: "Unknown Error",
                    titleSystemImage: "exclamationmark.triangle"
                )
                // TODO: Check for update button?
                // TODO: Link out to KB?
                // TODO: Send logs?
            }
        }
    @State var state = TrainTimeAppState()
    var body: some Scene {
        WindowGroup {
            ZStack {
                if state.loadError == nil {
                    Group {
                        ProgressView()
                    }
                        .zIndex(0)
                        .task {
                            await state.load()
                        }
                }
                if state.loadState == .loaded {
                    if let stationListComponent = state.stationListComponent {
                        StationList(component: stationListComponent)
                            .zIndex(1)
                    }
                }
                if let loadError = state.loadError {
                    errorView(for: loadError)
                        .zIndex(2)
                }
            }
        }
    }
}
