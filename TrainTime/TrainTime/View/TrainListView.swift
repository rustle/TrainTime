import SwiftUI

/// The station's calls as a list, a day per section.
struct TrainListView: View {
    let timeline: TrainTimeline
    let stationName: String
    @Environment(\.calendar) private var calendar
    var body: some View {
        List {
            ForEach(timeline.days) { day in
                Section(header: Text(day.title(calendar: calendar))) {
                    ForEach(day.rows) { row in
                        NavigationLink {
                            TrainDetailView(row: row,
                                            stationName: stationName)
                        } label: {
                            StationTrainRow(row: row)
                        }
                    }
                }
            }
        }
#if os(tvOS)
            .listStyle(.grouped)
#else
            .listStyle(.insetGrouped)
#endif
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainListView(timeline: TrainTimeline(rows: TrainRow.previewRows(calendar: PreviewAppComponent.calendar),
                                              calendar: PreviewAppComponent.calendar),
                      stationName: "Utica")
            .navigationTitle("Utica")
    }
        .environment(\.calendar, PreviewAppComponent.calendar)
}
#endif // DEBUG
