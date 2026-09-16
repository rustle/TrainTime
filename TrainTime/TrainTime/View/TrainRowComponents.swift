import SwiftUI

/// A time, with the date included only when it isn't today's.
struct TrainTimeText: View {
    @Environment(\.calendar) private var calendar
    let date: Date
    var body: some View {
        if calendar.isDateInToday(date) {
            Text(date,
                 format: .dateTime.hour().minute())
        } else {
            Text(date,
                 format: .dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}

/// The departure a row is scanned by, with the schedule it missed underneath.
struct TrainDepartureTime: View {
    let row: TrainRow
    var body: some View {
        VStack(alignment: .leading,
               spacing: 1) {
            Text(row.departure,
                 format: .dateTime.hour().minute())
                .font(.title3.monospacedDigit().weight(.semibold))
            if row.isLate {
                Text(row.stop.schDep,
                     format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// On time, minutes late, or departed.
struct TrainStatusBadge: View {
    let row: TrainRow
    private var tint: Color {
        switch row.progress {
        case .departed:
            return .secondary
        case .atStation:
            return .amtrakTravelBlue
        case .upcoming:
            return row.isLate ? .orange : .green
        }
    }
    private var text: LocalizedStringResource? {
        switch row.progress {
        case .departed:
            return "Departed"
        case .atStation:
            return "At Station"
        case .upcoming:
            return row.scheduleDescription
        }
    }
    var body: some View {
        if let text {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.15),
                            in: Capsule())
                .foregroundStyle(tint)
        }
    }
}

/// Platform, when the feed names one.
struct TrainPlatformLabel: View {
    let row: TrainRow
    var body: some View {
        if let platform = row.stop.platform, !platform.isEmpty {
            Text("Track \(platform)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
