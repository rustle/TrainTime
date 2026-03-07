import SwiftUI
import Amtrak

struct TrainView: View {
    struct FormattedTrainTime: View {
        let date: Date
        var body: some View {
            if Calendar.current.isDateInToday(date) {
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.body)
            } else {
                Text(date.formatted(.dateTime.hour().minute().day(.twoDigits).month(.twoDigits).year()))
                    .font(.body)
            }
        }
    }
    let train: TTTrain
    let stationCode: String
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if let routeName = train.routeName {
                Text(routeName)
                    .font(.largeTitle.bold())
            }
            Capsule()
                .frame(height: 4)
            HStackButVStackIfTooWide {
                Text("Train")
                Text(train.trainNumRaw)
            }
                .font(.title.bold().smallCaps())
            Capsule()
                .frame(height: 4)
            if let stop = train.stops[stationCode] {
                HStackButVStackIfTooWide {
                    Text("Scheduled Arrival:")
                        .font(.title2.bold())
                    FormattedTrainTime(date: stop.schArr)
                }
                HStackButVStackIfTooWide {
                    Text("Scheduled Departure:")
                        .font(.title2.bold())
                    FormattedTrainTime(date: stop.schDep)
                }
                if let arr = stop.arr {
                    HStackButVStackIfTooWide {
                        Text("Arrival:")
                            .font(.title2.bold())
                        FormattedTrainTime(date: arr)
                    }
                }
                if let dep = stop.dep {
                    HStackButVStackIfTooWide {
                        Text("Departure:")
                            .font(.title2.bold())
                        FormattedTrainTime(date: dep)
                    }
                }
                Capsule()
                    .frame(height: 4)
            }
            if let origName = train.origName, origName.count > 0, let destName
                = train.destName, destName.count > 0 {
                Text("Running from \(origName) to \(destName)")
                    .font(.body)
            }
        }
            .padding()
            .background(.thickMaterial)
            .cornerRadius(12)
    }
}

 #Preview {
    let date = Date()
    let train = TTTrain(routeName: "Lakeshore Limited",
                        trainNum: "48",
                        trainNumRaw: "48",
                        trainID: "48",
                        stops: ["UCA": .init(name: "Utica",
                                             code: "UCA",
                                             schArr: date,
                                             schDep: date,
                                             arr: date,
                                             dep: date)],
                        origName: "New York City",
                        destName: "Chicago",
                        createdAt: date,
                        updatedAt: date,
                        lastValTS: date)
    NavigationView {
        List {
            TrainView(train: train, stationCode: "UCA")
        }
    }
        .environment(\.client, ClientKey.defaultValue)
}
