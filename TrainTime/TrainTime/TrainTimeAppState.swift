import Amtrak
import Foundation
import GRDB
import os
import Observation

@MainActor
@Observable
final class TrainTimeAppState {
    enum LoadError {
        /// A transient failure (e.g. DB lock contention, network issue). Safe to retry.
        case transient(Error)
        /// The database is corrupt or a migration failed. Resetting local data may recover.
        case corruptDatabase(Error)
        /// An unrecoverable failure
        case fatal(Error)
    }

    private(set) var appComponent: AppComponent?
    private(set) var stationListComponent: StationListComponent?
    private(set) var loadError: LoadError?

    func load() async {
        loadError = nil
        do {
            let appComponent = try await AppComponent.makeProductionAppComponent()
            self.appComponent = appComponent
            self.stationListComponent = appComponent.makeStationListComponent()
        } catch where error is ClientError {
            Logger.app.error("App load failed (transient): \(error)")
            loadError = .transient(error)
        } catch let error as DatabaseError
            where error.resultCode == .SQLITE_BUSY
               || error.resultCode == .SQLITE_LOCKED {
            Logger.app.error("App load failed (transient, database): \(error)")
            loadError = .transient(error)
        } catch where error is DatabaseError {
            Logger.app.error("App load failed (corrupt database): \(error)")
            loadError = .corruptDatabase(error)
        } catch {
            Logger.app.error("App load failed (transient): \(error)")
            loadError = .transient(error)
        }
    }

    func resetAndReload() async {
        AppComponent.deleteProductionDatabase()
        await load()
    }
}
