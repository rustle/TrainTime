import SwiftUI

/// The station's calls on a vertical time rail, for scanning a whole day at a
/// glance. Departed calls fade, and a marker shows where the current time falls.
struct TrainTimelineView: View {
    // MARK: - Rail

    /// The line every entry hangs off, with this entry's dot on it.
    private struct Rail: View {
        let progress: TrainRow.Progress
        let isFirst: Bool
        let isLast: Bool
        private var dotColor: Color {
            switch progress {
            case .departed:
                return .secondary
            case .atStation:
                return .amtrakTravelBlue
            case .upcoming:
                return .amtrakTravelBlue
            }
        }
        var body: some View {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.quaternary)
                        .opacity(isFirst ? 0 : 1)
                        .frame(width: 2,
                               height: 18)
                    Rectangle()
                        .fill(.quaternary)
                        .opacity(isLast ? 0 : 1)
                        .frame(width: 2)
                }
                Group {
                    if progress == .upcoming {
                        Circle()
                            .fill(dotColor)
                    } else {
                        Circle()
                            .strokeBorder(dotColor,
                                          lineWidth: 2)
                    }
                }
                    .frame(width: 11,
                           height: 11)
                    .padding(.top, 13)
            }
                .frame(width: 24)
        }
    }

    // MARK: - Entry

    private struct Entry: View {
        let row: TrainRow
        let stationName: String
        let isFirst: Bool
        let isLast: Bool
        var body: some View {
            NavigationLink {
                TrainDetailView(row: row,
                                stationName: stationName)
            } label: {
                HStack(alignment: .top,
                       spacing: 8) {
                    Text(row.departure,
                         format: .dateTime.hour().minute())
                        .font(.footnote.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    Rail(progress: row.progress,
                         isFirst: isFirst,
                         isLast: isLast)
                    VStack(alignment: .leading,
                           spacing: 3) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                        Text(row.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            TrainStatusBadge(row: row)
                            TrainPlatformLabel(row: row)
                        }
                    }
                        .padding(.vertical, 8)
                    Spacer(minLength: 0)
                }
                    .contentShape(Rectangle())
                    .opacity(row.progress == .departed ? 0.5 : 1)
            }
                .buttonStyle(.plain)
        }
    }

    // MARK: - Now

    private struct NowMarker: View {
        let now: Date
        var body: some View {
            HStack(alignment: .center,
                   spacing: 8) {
                Text(now,
                     format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.red)
                ZStack {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                    Circle()
                        .fill(.red)
                        .frame(width: 7,
                               height: 7)
                }
                    .frame(width: 24,
                           height: 14)
                Rectangle()
                    .fill(.red.opacity(0.5))
                    .frame(height: 1)
            }
                .padding(.trailing)
        }
    }

    // MARK: - Day

    private struct DaySection: View {
        @Environment(\.calendar) private var calendar
        let day: TrainTimeline.Day
        let stationName: String
        let now: Date
        /// Where the current time falls among the day's calls, when the day is
        /// the one in progress.
        private var nowMarkerIndex: Int? {
            guard calendar.isDate(day.id,
                                  inSameDayAs: now) else {
                return nil
            }
            return day.rows.firstIndex { $0.departure >= now } ?? day.rows.count
        }
        var body: some View {
            Section {
                ForEach(Array(day.rows.enumerated()),
                        id: \.element.id) { index, row in
                    if index == nowMarkerIndex {
                        NowMarker(now: now)
                    }
                    Entry(row: row,
                          stationName: stationName,
                          isFirst: index == 0,
                          isLast: index == day.rows.count - 1)
                        .id(row.id)
                }
                if nowMarkerIndex == day.rows.count {
                    NowMarker(now: now)
                }
            } header: {
                HStack {
                    Text(day.title(relativeTo: now,
                                   calendar: calendar))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("^[\(day.rows.count) train](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
#if os(tvOS)
                    .background(.regularMaterial)
#else
                    .background(.bar)
#endif
            }
        }
    }

    // MARK: - Timeline

    let timeline: TrainTimeline
    let stationName: String
    @State private var now: Date = .now
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading,
                           spacing: 0,
                           pinnedViews: [.sectionHeaders]) {
                    ForEach(timeline.days) { day in
                        DaySection(day: day,
                                   stationName: stationName,
                                   now: now)
                    }
                }
            }
                .task {
                    // The now marker is only useful if it keeps up with the clock.
                    while !Task.isCancelled {
                        now = .now
                        try? await Task.sleep(for: .seconds(30))
                    }
                }
                .onAppear {
                    guard let row = timeline
                        .day(containingNextDepartureAfter: now)?
                        .firstRow(atOrAfter: now) else {
                        return
                    }
                    proxy.scrollTo(row.id,
                                   anchor: .center)
                }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainTimelineView(timeline: TrainTimeline(rows: TrainRow.previewRows(calendar: PreviewAppComponent.calendar),
                                                  calendar: PreviewAppComponent.calendar),
                          stationName: "Utica")
            .navigationTitle("Utica")
    }
        .environment(\.calendar, PreviewAppComponent.calendar)
}
#endif // DEBUG
