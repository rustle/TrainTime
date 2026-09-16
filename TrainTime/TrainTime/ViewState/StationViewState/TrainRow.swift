import Amtrak
import Foundation

struct TrainRow: Identifiable, Sendable, Comparable {
    static func < (lhs: TrainRow,
                   rhs: TrainRow) -> Bool {
        lhs.sortDate < rhs.sortDate
    }
    let id: String
    let train: Train
    let stop: Stop
    init(trainAtStop: TrainAtStop) {
        self.train = trainAtStop.train
        self.stop = trainAtStop.stop
        self.id = train.trainID + stop.code
    }
}

// MARK: - Presentation

extension TrainRow {
    /// Where this call at the station stands right now.
    enum Progress: Sendable {
        /// The train hasn't reached the station yet.
        case upcoming
        /// The train is at the station.
        case atStation
        /// The train has left the station.
        case departed
    }
    /// The time the row is scanned by: the departure, actual when it's known.
    var departure: Date {
        stop.dep ?? stop.schDep
    }
    /// The arrival, actual when it's known.
    var arrival: Date {
        stop.arr ?? stop.schArr
    }
    /// The time the row sorts and groups by.
    var sortDate: Date {
        departure
    }
    /// Seconds behind schedule, negative when early. Nil until the API reports
    /// a real time to compare the schedule against.
    var delay: TimeInterval? {
        if let dep = stop.dep {
            return dep.timeIntervalSince(stop.schDep)
        }
        if let arr = stop.arr {
            return arr.timeIntervalSince(stop.schArr)
        }
        return nil
    }
    /// "On time", "6 min late", "2 min early", or nil when nothing is reported.
    var scheduleDescription: LocalizedStringResource? {
        guard let delay else {
            return nil
        }
        let minutes = Int((delay / 60).rounded())
        if minutes == 0 {
            return "On time"
        } else if minutes < 0 {
            return "\(-minutes) min early"
        } else {
            return "\(minutes) min late"
        }
    }
    /// True once the train is more than a minute behind its schedule.
    var isLate: Bool {
        guard let delay else {
            return false
        }
        return delay > 60
    }
    var progress: Progress {
        switch stop.status {
        case .Departed:
            return .departed
        case .station:
            return .atStation
        case .enroute:
            return .upcoming
        case .Unknown, .none:
            // The feed leaves status out often enough that the reported times
            // are the more reliable signal.
            if stop.dep != nil {
                return .departed
            } else if stop.arr != nil {
                return .atStation
            } else {
                return .upcoming
            }
        }
    }
    /// What the row leads with. Not every train run carries a route name.
    var title: LocalizedStringResource {
        if let routeName = train.routeName, !routeName.isEmpty {
            return "\(routeName)"
        }
        return "Train \(train.trainNum)"
    }
    /// "48 to Chicago", or just the train number when the feed omits the
    /// destination.
    var subtitle: LocalizedStringResource {
        if let destName = train.destName, !destName.isEmpty {
            return "\(train.trainNum) to \(destName)"
        }
        return "Train \(train.trainNum)"
    }
    /// "New York City to Chicago", for the detail screen.
    var route: LocalizedStringResource? {
        guard let origName = train.origName, !origName.isEmpty,
              let destName = train.destName, !destName.isEmpty else {
            return nil
        }
        return "\(origName) to \(destName)"
    }
}
