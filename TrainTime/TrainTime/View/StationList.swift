import Amtrak
import os
import SwiftUI

struct StationList: View {
    struct Row: View {
        let row: StationRow
        let action: @MainActor () -> Void
        var body: some View {
            VStack(alignment: .center) {
                HStack(alignment: .center) {
                    Text(row.title)
                        .font(.largeTitle)
                        .bold()
                    Spacer()
                    if row.station.isFavorite == true {
                        Image(systemName: "star.circle.fill")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.amtrakTravelBlue)
                            .frame(width: 20)
                    }
                    Text(row.station.code)
                        .font(.title2.monospaced())
                }
                .padding(.vertical)
            }
                .swipeActions(edge: .leading,
                              allowsFullSwipe: true) {
                    Button {
                        action()
                    } label: {
                        if row.station.isFavorite == true {
                            Image(systemName: "star.fill")
                                .tint(.amtrakTravelBlue)
                        } else {
                            Image(systemName: "star")
                        }
                    }
                }
        }
    }
    @State var state: StationListState
    init(component: StationListDependency) {
        state = .init(component: component)
    }
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack {
            List(state.filteredRows ?? state.allRows) { row in
                    NavigationLink(destination: {
                        StationView(state: .init(station: row.station,
                                                 component: state.component.makeStationComponent()))
                    }, label: {
                        Row(row: row) {
                            state.writeUserDataForStation(code: row.station.code,
                                                          isFavorite: !(row.station.isFavorite ?? false))
                        }
                    })
                        .disabled(row.station.trainIdentifiers.isEmpty)
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

#if DEBUG
#Preview {
    StationList(component: PreviewAppComponent().makeStationListComponent())
}
#endif // DEBUG
