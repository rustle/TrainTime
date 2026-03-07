import Amtrak
import os
import SwiftUI

struct StationList: View {
    struct ListContainer: View {
        let rows: [StationRow]
        var body: some View {
            List(rows) { row in
                Row(row: row)
            }
        }
    }
    struct Row: View {
        let row: StationRow
        var body: some View {
            NavigationLink(destination: {
                StationView(state: .init(station: row.station))
            }, label: {
                VStack(alignment: .leading) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(.headline)
                        Spacer()
                        Text(row.station.code)
                            .font(.caption2.monospaced().smallCaps())
                    }
                }
            })
        }
    }
    @Environment(\.client) var client
    @State var state: StationListState = .init()
    var body: some View {
        //let _ = Self._printChanges()
        NavigationStack {
            ListContainer(rows: state.filteredRows ?? state.allRows)
                .navigationTitle("Stations")
                .searchable(text: $state.query,
                            prompt: "Search Stations")
                .onSubmit(of: .search) {
                    state.flush()
                }
                .refreshable {
                    try? await state.load(with: client)
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
