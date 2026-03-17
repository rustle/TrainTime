@testable import TrainTime
import Foundation
import GRDB

struct TestDatabase {
    let database: TrainTime.Database
    let connection: DatabasePool

    static func make() throws -> Self {
        let directory = URL.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = Database(name: UUID().uuidString,
                                directoryURL: directory,
                                migrator: CacheMigrator())
        let connection = try database.newConnection()
        return Self(database: database, connection: connection)
    }

    func closeAndDelete() throws {
        try connection.close()
        let directory = database.directoryURL
        try FileManager.default.removeItem(at: directory)
    }
}
