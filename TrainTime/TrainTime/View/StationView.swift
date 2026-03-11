import Amtrak
import SwiftUI

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
    @State var state: StationViewState
    var body: some View {
        ListContainer(trains: state.trains,
                      stationCode: state.station.code)
            .navigationTitle(state.title)
            .refreshable {
                try? await state.load(refreshStation: true)
            }
            .task {
                try? await state.load()
            }
    }
}

#Preview {
    NavigationView {
        StationView(
            state: .init(station: .init(name: "Utica",
                                        code: "UCA",
                                        trainIdentifiers: ["48-1"]),
                         component: StationComponent(client: TTClient()))
        )
    }
}
