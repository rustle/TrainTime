import Amtrak
import os
import SwiftUI

struct StationList: View {
    @State var state: StationListState
    init(component: StationListDependency) {
        state = .init(component: component)
    }
    var body: some View {
        //let _ = Self._printChanges()
        NavigationStack {
            List(state.filteredRows ?? state.allRows) { row in
                    NavigationLink(destination: {
                        StationView(state: .init(station: row.station,
                                                 component: state.component.makeStationComponent()))
                    }, label: {
                        VStack(alignment: .center) {
                            HStack(alignment: .center) {
                                Text(row.title)
                                    .font(.largeTitle)
                                    .bold()
                                Spacer()
                                Text(row.station.code)
                                    .font(.title2.monospaced())
                            }
                            .padding(.vertical)
                        }
//                        .swipeActions(edge: .leading) {
//                            Button { print("toggle") } label: {
//                                Image(systemName: "star.fill")
//                            }
//                        }
                    })
                }
                .navigationTitle("Stations")
                .searchable(text: $state.query,
                            prompt: "Search Stations")
                .onSubmit(of: .search) {
                    state.flush()
                }
                .refreshable {
                    try? await state.load()
                }
                .task {
                    try? await state.load()
                }
        }
    }
}

#Preview {
    StationList(component: StationListComponent.previewComponent())
}
