import Amtrak
import SwiftUI

struct StationView: View {
    struct ListContainer: View {
        let trains: [TrainRow]
        var body: some View {
            List(trains) { row in
                TrainView(train: row.train,
                          stop: row.stop)
            }
        }
    }
    @State var state: StationViewState
    var body: some View {
        ListContainer(trains: state.trains)
            .navigationTitle(state.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: {
                        StationLocationView(station: state.station)
                    }, label: {
                        Image(systemName: "map")
                    })
                }
            }
            .refreshable {
                try? await state.load(refreshStation: true)
            }
            .task {
                try? await state.load()
            }
    }
}

#if DEBUG
#Preview {
    NavigationView {
        StationView(
            state: .init(
                station: .init(
                    name: "Utica",
                    code: "UCA",
                    trainIdentifiers: ["48-1"]
                ),
                component: PreviewAppComponent().makeStationListComponent().makeStationComponent()
            )
        )
    }
}
#endif // DEBUG
