import Amtrak
import os
import SwiftUI

#if USE_COLLECTION_VIEW
struct StationListCollectionView: View {
    @Environment(\.client) var client
    @State var state: StationListState = .init()
    var body: some View {
        //let _ = Self._printChanges()
        NavigationStack {
            StationListCollectionViewHost(
                state: state,
                onSelect: { row in
                    state.selectedStation = row
                },
                onRefresh: {
                    try? await state.load(with: client)
                })
                .navigationTitle("Stations")
                .navigationDestination(item: $state.selectedStation) { row in
                    StationView(state: .init(station: row.station))
                }
                .searchable(text: $state.query,
                            prompt: "Search Stations")
                .onSubmit(of: .search) {
                    state.flush()
                }
                .task {
                    try? await state.load(with: client)
                }
        }
    }
}

#Preview {
    StationList()
        .environment(\.client, ClientKey.defaultValue)
}
#endif // USE_COLLECTION_VIEW
