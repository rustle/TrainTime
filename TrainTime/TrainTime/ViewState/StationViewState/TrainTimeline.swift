import Foundation

/// A station's calls grouped by day, oldest first, so both the list and the
/// timeline can be scanned a day at a time.
struct TrainTimeline: Sendable {
    struct Day: Identifiable, Sendable {
        /// The start of the day, which is also its identity.
        let id: Date
        let rows: [TrainRow]
        /// "Today", "Tomorrow", or a written out date for anything further out.
        func title(relativeTo now: Date = .now,
                   calendar: Calendar) -> LocalizedStringResource {
            if calendar.isDate(id, inSameDayAs: now) {
                return "Today"
            }
            if let tomorrow = calendar.date(byAdding: .day,
                                            value: 1,
                                            to: now),
               calendar.isDate(id, inSameDayAs: tomorrow) {
                return "Tomorrow"
            }
            return "\(id, format: .dateTime.weekday(.wide).month(.abbreviated).day())"
        }
        /// The first row that hasn't departed yet, which is where the day is
        /// worth scrolling to.
        func firstRow(atOrAfter date: Date) -> TrainRow? {
            rows.first { $0.departure >= date }
        }
    }
    let days: [Day]
    var isEmpty: Bool {
        days.isEmpty
    }
    init(rows: [TrainRow],
         calendar: Calendar) {
        let grouped = Dictionary(grouping: rows.sorted()) { row in
            calendar.startOfDay(for: row.sortDate)
        }
        days = grouped
            .keys
            .sorted()
            .map { day in
                Day(id: day,
                    rows: grouped[day] ?? [])
            }
    }
    /// The day the timeline should open on: the one holding the next departure,
    /// falling back to the last day when everything has already left.
    func day(containingNextDepartureAfter date: Date) -> Day? {
        days.first { $0.firstRow(atOrAfter: date) != nil } ?? days.last
    }
}
