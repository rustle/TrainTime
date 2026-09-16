#if DEBUG
import Amtrak
import Foundation

extension TrainRow {
    /// A day's worth of calls at one station, for previews, laid out on the
    /// given calendar's idea of today.
    static func previewRows(calendar: Calendar) -> [TrainRow] {
        let today = calendar.startOfDay(for: .now)
        func time(_ hour: Int,
                  _ minute: Int) -> Date {
            calendar.date(byAdding: DateComponents(hour: hour,
                                                   minute: minute),
                          to: today) ?? today
        }
        func row(routeName: String,
                 trainNum: String,
                 destName: String,
                 schArr: Date,
                 schDep: Date,
                 arr: Date? = nil,
                 dep: Date? = nil,
                 platform: String? = nil,
                 status: StopStatus? = nil) -> TrainRow {
            let date = Date.now
            return TrainRow(
                trainAtStop: TrainAtStop(
                    train: Train(routeName: routeName,
                                 trainNum: trainNum,
                                 trainNumRaw: trainNum,
                                 trainID: "\(trainNum)-1",
                                 origName: "New York City",
                                 destName: destName,
                                 createdAt: date,
                                 updatedAt: date,
                                 lastValTS: date),
                    stop: Stop(code: "UCA",
                               schArr: schArr,
                               schDep: schDep,
                               arr: arr,
                               dep: dep,
                               platform: platform,
                               status: status)
                )
            )
        }
        return [
            row(routeName: "Empire Service",
                trainNum: "281",
                destName: "Niagara Falls",
                schArr: time(7, 45),
                schDep: time(7, 48),
                arr: time(7, 44),
                dep: time(7, 49),
                platform: "1",
                status: .Departed),
            row(routeName: "Lake Shore Limited",
                trainNum: "48",
                destName: "New York City",
                schArr: time(11, 10),
                schDep: time(11, 15),
                arr: time(11, 27),
                dep: time(11, 31),
                platform: "2",
                status: .Departed),
            row(routeName: "Maple Leaf",
                trainNum: "64",
                destName: "New York City",
                schArr: time(14, 5),
                schDep: time(14, 8),
                arr: time(14, 5),
                status: .station),
            row(routeName: "Empire Service",
                trainNum: "284",
                destName: "New York City",
                schArr: time(17, 32),
                schDep: time(17, 35),
                status: .enroute),
            row(routeName: "Lake Shore Limited",
                trainNum: "49",
                destName: "Chicago",
                schArr: time(23, 40),
                schDep: time(23, 45),
                status: .enroute),
            row(routeName: "Empire Service",
                trainNum: "280",
                destName: "Niagara Falls",
                schArr: time(31, 15),
                schDep: time(31, 18),
                status: .enroute),
        ]
    }
}
#endif // DEBUG
