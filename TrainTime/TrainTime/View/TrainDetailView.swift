import Amtrak
import SwiftUI

/// Everything the feed says about one train's call at one station.
struct TrainDetailView: View {
    let row: TrainRow
    let stationName: String
    private var train: Train {
        row.train
    }
    private var stop: Stop {
        row.stop
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading,
                       spacing: 6) {
                    Text(row.title)
                        .font(.title2.bold())
                    if let route = row.route {
                        Text(route)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        TrainStatusBadge(row: row)
                        TrainPlatformLabel(row: row)
                    }
                        .padding(.top, 2)
                }
                    .padding(.vertical, 4)
            }
            Section("At \(stationName)") {
                LabeledContent("Scheduled Arrival") {
                    TrainTimeText(date: stop.schArr)
                }
                LabeledContent("Scheduled Departure") {
                    TrainTimeText(date: stop.schDep)
                }
                if let arr = stop.arr {
                    LabeledContent("Arrival") {
                        TrainTimeText(date: arr)
                    }
                }
                if let dep = stop.dep {
                    LabeledContent("Departure") {
                        TrainTimeText(date: dep)
                    }
                }
                if let platform = stop.platform, !platform.isEmpty {
                    LabeledContent("Track",
                                   value: platform)
                }
            }
            Section("Train") {
                LabeledContent("Number",
                               value: train.trainNum)
                if let provider = train.provider, !provider.isEmpty {
                    LabeledContent("Operator",
                                   value: provider)
                }
                if let eventName = train.eventName, !eventName.isEmpty {
                    LabeledContent("Next Station",
                                   value: eventName)
                }
                if let velocity = train.velocity, velocity > 0 {
                    LabeledContent("Speed",
                                   value: "\(Int(velocity.rounded())) mph")
                }
                LabeledContent("Last Updated") {
                    TrainTimeText(date: train.lastValTS)
                }
            }
            if let statusMsg = train.statusMsg, !statusMsg.isEmpty {
                Section("Status") {
                    Text(statusMsg)
                }
            }
            if !train.alerts.isEmpty {
                Section("Alerts") {
                    ForEach(Array(train.alerts.enumerated()),
                            id: \.offset) { _, alert in
                        Text(alert.message)
                    }
                }
            }
        }
            .navigationTitle("Train \(train.trainNum)")
#if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainDetailView(row: TrainRow.previewRows(calendar: PreviewAppComponent.calendar)[1],
                        stationName: "Utica")
    }
        .environment(\.calendar, PreviewAppComponent.calendar)
}
#endif // DEBUG
