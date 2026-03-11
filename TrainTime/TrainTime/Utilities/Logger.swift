import os

extension Logger {
    private static let subsystem = "TrainTime"
    static let database = Logger(subsystem: subsystem,
                                 category: "database")
    static let service = Logger(subsystem: subsystem,
                                category: "service")
    static let view = Logger(subsystem: subsystem,
                             category: "view")
    static let viewState = Logger(subsystem: subsystem,
                                  category: "viewstate")
    static let utilities = Logger(subsystem: subsystem,
                                  category: "utilities")
}
