import Amtrak
import os
import SwiftUI

struct StationList: View {
    /// The ways a favorite can be moved without dragging.
    struct Reorder {
        let isFirst: Bool
        let isLast: Bool
        let moveUp: @MainActor () -> Void
        let moveDown: @MainActor () -> Void
        let moveToTop: @MainActor () -> Void
        let moveToBottom: @MainActor () -> Void
    }
    struct Row: View {
        let row: StationRow
        let action: @MainActor () -> Void
        var reorder: Reorder?
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
                            .accessibilityLabel("Favorite")
                    }
                    Text(row.station.code)
                        .font(.title2.monospaced())
                }
                .padding(.vertical)
            }
                // One element per row so the move actions below attach to
                // the station rather than to a piece of it.
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if let reorder {
                        if !reorder.isFirst {
                            Button("Move Up", action: reorder.moveUp)
                            Button("Move to Top", action: reorder.moveToTop)
                        }
                        if !reorder.isLast {
                            Button("Move Down", action: reorder.moveDown)
                            Button("Move to Bottom", action: reorder.moveToBottom)
                        }
                    }
                }
#if os(tvOS)
                .contextMenu {
                    Button {
                        action()
                    } label: {
                        if row.station.isFavorite == true {
                            Label("Unfavorite", systemImage: "star.fill")
                        } else {
                            Label("Favorite", systemImage: "star")
                        }
                    }
                    if let reorder {
                        Divider()
                        Button("Move Up", systemImage: "arrow.up", action: reorder.moveUp)
                            .disabled(reorder.isFirst)
                        Button("Move Down", systemImage: "arrow.down", action: reorder.moveDown)
                            .disabled(reorder.isLast)
                        Button("Move to Top", systemImage: "arrow.up.to.line", action: reorder.moveToTop)
                            .disabled(reorder.isFirst)
                        Button("Move to Bottom", systemImage: "arrow.down.to.line", action: reorder.moveToBottom)
                            .disabled(reorder.isLast)
                    }
                }
#else
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
#endif
        }
    }
    @State var state: StationListState
    init(component: StationListDependency) {
        state = .init(component: component)
    }
    var body: some View {
//        let _ = Self._printChanges()
        NavigationStack {
            List {
                if let filteredRows = state.filteredRows {
                    ForEach(filteredRows) { row in
                        stationRow(row)
                    }
                } else if state.favoriteRows.isEmpty {
                    ForEach(state.allRows) { row in
                        stationRow(row)
                    }
                } else {
                    // Favorites get their own section so the drop targets
                    // are unambiguous and a drag can't leave the favorites.
                    Section("Favorites") {
                        ForEach(state.favoriteRows) { row in
                            stationRow(row,
                                       reorder: reorder(for: row))
                        }
                            .onMove { source, destination in
                                state.moveFavorites(fromOffsets: source,
                                                    toOffset: destination)
                            }
                    }
                    Section("Stations") {
                        ForEach(state.otherRows) { row in
                            stationRow(row)
                        }
                    }
                }
            }
                .navigationDestination(for: Station.self) { station in
                    StationView(state: .init(station: station,
                                             component: state.component.makeStationComponent()))
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
#if !os(tvOS)
                .toolbar {
                    if !state.favoriteRows.isEmpty {
                        EditButton()
                    }
                }
#endif
        }
    }
    private func stationRow(_ row: StationRow,
                            reorder: Reorder? = nil) -> some View {
        Row(row: row,
            action: {
                state.toggleFavorite(code: row.station.code)
            },
            reorder: reorder)
            .background {
                if !row.station.trainIdentifiers.isEmpty {
                    NavigationLink(value: row.station) {
                        EmptyView()
                    }
                        .opacity(0)
                }
            }
    }
    private func reorder(for row: StationRow) -> Reorder {
        let code = row.station.code
        return Reorder(isFirst: state.favoriteRows.first?.id == row.id,
                       isLast: state.favoriteRows.last?.id == row.id,
                       moveUp: { state.moveFavorite(code: code, by: -1) },
                       moveDown: { state.moveFavorite(code: code, by: 1) },
                       moveToTop: { state.moveFavoriteToTop(code: code) },
                       moveToBottom: { state.moveFavoriteToBottom(code: code) })
    }
}

#if DEBUG
#Preview {
    StationList(component: PreviewAppComponent().makeStationListComponent())
}
#endif // DEBUG
