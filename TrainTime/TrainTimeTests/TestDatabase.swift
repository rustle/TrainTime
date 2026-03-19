@testable import TrainTime
import Foundation
import GRDB

struct TestDatabase {
    let cache: TrainTime.Database
    let cacheConnection: DatabasePool
    let userData: TrainTime.Database
    let userDataConnection: DatabasePool

    static func make() throws -> Self {
        let directory = URL.temporaryDirectory.appending(component: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, 
                                                withIntermediateDirectories: true)
        let cache = Database(name: UUID().uuidString + ".sqlite",
                             directoryURL: directory,
                             migrator: CacheMigrator())
        let cacheConnection = try cache.newConnection()
        let userData = Database(name: UUID().uuidString + ".sqlite",
                                directoryURL: directory,
                                migrator: UserDataMigrator())
        let userDataConnection = try userData.newConnection()
        return Self(cache: cache,
                    cacheConnection: cacheConnection,
                    userData: userData,
                    userDataConnection: userDataConnection)
    }
    
    func runMigrations() async throws {
        try await cache.runMigrations(cacheConnection)
        try await userData.runMigrations(userDataConnection)
    }

    func closeAndDelete() throws {
        try cacheConnection.close()
        try userDataConnection.close()
        // DBs use the same directory so only need to delete once
        let directory = cache.directoryURL
        try FileManager.default.removeItem(at: directory)
    }
}
