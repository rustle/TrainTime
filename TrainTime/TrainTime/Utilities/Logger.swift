import os

extension Logger {
    private static let subsystem = "TrainTime"
    static let viewState = Logger(subsystem: subsystem,
                                  category: "viewstate")
    static let utilities = Logger(subsystem: subsystem,
                                  category: "utilities")
}
