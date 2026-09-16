import Amtrak
import SwiftUI

/// How the station's calls are presented.
enum StationViewMode: String, CaseIterable, Identifiable, Sendable {
    /// A day per section, one row per call.
    case list
    /// A time rail with a now marker.
    case timeline
    var id: String {
        rawValue
    }
    var title: LocalizedStringResource {
        switch self {
        case .list:
            return "List"
        case .timeline:
            return "Timeline"
        }
    }
}

struct StationView: View {
    @AppStorage("StationViewMode") private var mode: StationViewMode = .list
    @State var state: StationViewState
    var body: some View {
        Group {
            if state.timeline.isEmpty {
                ContentUnavailableView("No Trains Scheduled",
                                       systemImage: "train.side.front.car",
                                       description: Text("Pull to refresh \(state.title)."))
            } else {
                switch mode {
                case .list:
                    TrainListView(timeline: state.timeline,
                                  stationName: state.title)
                case .timeline:
                    TrainTimelineView(timeline: state.timeline,
                                      stationName: state.title)
                }
            }
        }
            .navigationTitle(state.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                Picker("View", selection: $mode) {
                    ForEach(StationViewMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: {
                        StationLocationView(station: state.station)
                    }, label: {
                        Label("Station Location",
                              systemImage: "map")
                    })
                }
            }
            .refreshable {
                try? await state.load(refreshStation: true)
            }
            .task {
                try? await state.load()
            }
            // The calendar every date in this screen is grouped and labelled
            // with, so the views agree with the timeline's day boundaries.
            .environment(\.calendar, state.component.calendar)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
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
