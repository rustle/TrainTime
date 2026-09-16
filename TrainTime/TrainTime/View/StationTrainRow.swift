import SwiftUI

/// One call at a station, sized for scanning a list.
struct StationTrainRow: View {
    let row: TrainRow
    var body: some View {
        HStack(alignment: .top,
               spacing: 12) {
            TrainDepartureTime(row: row)
            VStack(alignment: .leading,
                   spacing: 3) {
                Text(row.title)
                    .font(.headline)
                Text(row.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TrainStatusBadge(row: row)
                    TrainPlatformLabel(row: row)
                }
            }
            Spacer(minLength: 0)
        }
            .padding(.vertical, 4)
            .opacity(row.progress == .departed ? 0.55 : 1)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        List {
            ForEach(TrainRow.previewRows(calendar: PreviewAppComponent.calendar)) { row in
                StationTrainRow(row: row)
            }
        }
    }
        .environment(\.calendar, PreviewAppComponent.calendar)
}
#endif // DEBUG
