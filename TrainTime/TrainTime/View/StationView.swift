import SwiftUI
import Amtrak

struct StationView: View {
    struct ListContainer: View {
        let trains: [TrainRow]
        let stationCode: String
        var body: some View {
            List(trains) { row in
                TrainView(train: row.train,
                          stationCode: stationCode)
            }
        }
    }
    @Environment(\.client) var client
    @State var state: StationViewState
    var body: some View {
        ListContainer(trains: state.trains,
                      stationCode: state.station.code)
            .navigationTitle(state.title)
            .refreshable {
                try? await state.load(with: client, refreshStation: true)
            }
            .task {
                try? await state.load(with: client)
            }
    }
}

#Preview {
    NavigationView {
        StationView(state: .init(station: .init(name: "Utica", code: "UCA", trainIdentifiers: ["48-1"])))
    }
        .environment(\.client, ClientKey.defaultValue)
}
