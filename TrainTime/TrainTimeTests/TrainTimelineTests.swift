import Amtrak
import Foundation
import Testing
@testable import TrainTime

private func makeRow(trainNum: String,
                     schArr: Date,
                     schDep: Date,
                     arr: Date? = nil,
                     dep: Date? = nil,
                     status: StopStatus? = nil) -> TrainRow {
    let date = iso8601("2026-08-31T12:00:00Z")
    return TrainRow(
        trainAtStop: TrainAtStop(
            train: Train(routeName: "Empire Service",
                         trainNum: trainNum,
                         trainNumRaw: trainNum,
                         trainID: "\(trainNum)-1",
                         origName: "New York City",
                         destName: "Niagara Falls",
                         createdAt: date,
                         updatedAt: date,
                         lastValTS: date),
            stop: Stop(code: "UCA",
                       schArr: schArr,
                       schDep: schDep,
                       arr: arr,
                       dep: dep,
                       status: status)
        )
    )
}

struct TrainRowPresentationTests {
    @Test func delayIsMeasuredAgainstTheScheduledDeparture() throws {
        let row = makeRow(trainNum: "281",
                          schArr: iso8601("2026-08-31T11:45:00Z"),
                          schDep: iso8601("2026-08-31T11:48:00Z"),
                          arr: iso8601("2026-08-31T11:50:00Z"),
                          dep: iso8601("2026-08-31T12:00:00Z"))
        #expect(row.delay == TimeInterval(12 * 60))
        #expect(String(localized: try #require(row.scheduleDescription)) == "12 min late")
        #expect(row.isLate)
    }
    @Test func delayFallsBackToTheArrivalWhenTheTrainHasNotLeft() throws {
        let row = makeRow(trainNum: "281",
                          schArr: iso8601("2026-08-31T11:45:00Z"),
                          schDep: iso8601("2026-08-31T11:48:00Z"),
                          arr: iso8601("2026-08-31T11:42:00Z"))
        #expect(String(localized: try #require(row.scheduleDescription)) == "3 min early")
        #expect(!row.isLate)
    }
    @Test func delayIsUnknownUntilTheFeedReportsARealTime() {
        let row = makeRow(trainNum: "281",
                          schArr: iso8601("2026-08-31T11:45:00Z"),
                          schDep: iso8601("2026-08-31T11:48:00Z"))
        #expect(row.delay == nil)
        #expect(row.scheduleDescription == nil)
    }
    @Test func progressFallsBackToReportedTimesWhenStatusIsMissing() {
        let departed = makeRow(trainNum: "281",
                               schArr: iso8601("2026-08-31T11:45:00Z"),
                               schDep: iso8601("2026-08-31T11:48:00Z"),
                               arr: iso8601("2026-08-31T11:45:00Z"),
                               dep: iso8601("2026-08-31T11:49:00Z"))
        #expect(departed.progress == .departed)
        let atStation = makeRow(trainNum: "284",
                                schArr: iso8601("2026-08-31T11:45:00Z"),
                                schDep: iso8601("2026-08-31T11:48:00Z"),
                                arr: iso8601("2026-08-31T11:45:00Z"))
        #expect(atStation.progress == .atStation)
        let upcoming = makeRow(trainNum: "64",
                               schArr: iso8601("2026-08-31T11:45:00Z"),
                               schDep: iso8601("2026-08-31T11:48:00Z"))
        #expect(upcoming.progress == .upcoming)
    }
    @Test func reportedStatusWinsOverReportedTimes() {
        let row = makeRow(trainNum: "281",
                          schArr: iso8601("2026-08-31T11:45:00Z"),
                          schDep: iso8601("2026-08-31T11:48:00Z"),
                          arr: iso8601("2026-08-31T11:45:00Z"),
                          dep: iso8601("2026-08-31T11:49:00Z"),
                          status: .station)
        #expect(row.progress == .atStation)
    }
}

struct TrainTimelineTests {
    /// A fixed calendar, so the grouping doesn't depend on where the tests run.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    @Test func callsAreGroupedByDayInChronologicalOrder() {
        let rows = [
            makeRow(trainNum: "49",
                    schArr: iso8601("2026-09-01T13:40:00Z"),
                    schDep: iso8601("2026-09-01T13:45:00Z")),
            makeRow(trainNum: "281",
                    schArr: iso8601("2026-08-31T11:45:00Z"),
                    schDep: iso8601("2026-08-31T11:48:00Z")),
            makeRow(trainNum: "284",
                    schArr: iso8601("2026-08-31T21:32:00Z"),
                    schDep: iso8601("2026-08-31T21:35:00Z")),
        ]

        let timeline = TrainTimeline(rows: rows,
                                     calendar: Self.calendar)

        #expect(timeline.days.count == 2)
        #expect(timeline.days[0].rows.map(\.train.trainNum) == ["281", "284"])
        #expect(timeline.days[1].rows.map(\.train.trainNum) == ["49"])
    }
    @Test func emptyRowsMakeAnEmptyTimeline() {
        #expect(TrainTimeline(rows: [],
                              calendar: Self.calendar).isEmpty)
    }
    @Test func firstRowAtOrAfterFindsTheNextDeparture() throws {
        let rows = [
            makeRow(trainNum: "281",
                    schArr: iso8601("2026-08-31T11:45:00Z"),
                    schDep: iso8601("2026-08-31T11:48:00Z")),
            makeRow(trainNum: "284",
                    schArr: iso8601("2026-08-31T21:32:00Z"),
                    schDep: iso8601("2026-08-31T21:35:00Z")),
        ]
        let timeline = TrainTimeline(rows: rows,
                                     calendar: Self.calendar)

        let day = try #require(timeline.days.first)
        let next = try #require(day.firstRow(atOrAfter: iso8601("2026-08-31T12:00:00Z")))
        #expect(next.train.trainNum == "284")
        #expect(day.firstRow(atOrAfter: iso8601("2026-09-01T00:00:00Z")) == nil)
    }
    @Test func theOpeningDayIsTheOneHoldingTheNextDeparture() throws {
        let rows = [
            makeRow(trainNum: "281",
                    schArr: iso8601("2026-08-31T11:45:00Z"),
                    schDep: iso8601("2026-08-31T11:48:00Z")),
            makeRow(trainNum: "49",
                    schArr: iso8601("2026-09-01T13:40:00Z"),
                    schDep: iso8601("2026-09-01T13:45:00Z")),
        ]
        let timeline = TrainTimeline(rows: rows,
                                     calendar: Self.calendar)

        let day = try #require(timeline.day(containingNextDepartureAfter: iso8601("2026-08-31T12:00:00Z")))
        #expect(day.rows.map(\.train.trainNum) == ["49"])
    }
    @Test func everythingDepartedOpensOnTheLastDay() throws {
        let rows = [
            makeRow(trainNum: "281",
                    schArr: iso8601("2026-08-31T11:45:00Z"),
                    schDep: iso8601("2026-08-31T11:48:00Z")),
        ]
        let timeline = TrainTimeline(rows: rows,
                                     calendar: Self.calendar)

        let day = try #require(timeline.day(containingNextDepartureAfter: iso8601("2026-09-02T12:00:00Z")))
        #expect(day.rows.map(\.train.trainNum) == ["281"])
    }
}
