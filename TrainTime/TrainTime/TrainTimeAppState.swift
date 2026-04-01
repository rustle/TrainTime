import Amtrak
import Foundation
import GRDB
import os
import Observation
import SwiftConcurrencySerialQueue
import SwiftUI

@MainActor
@Observable
final class TrainTimeAppState {
    enum LoadState: Equatable {
        case loading
        case loaded
    }
    enum LoadError {
        /// A transient failure (e.g. DB lock contention, network issue). Safe to retry.
        case transient(Error)
        /// The cache database is corrupt or a migration failed. Deleting cache may recover.
        case corruptCache(Error)
        /// The user data database is corrupt or a migration failed. Deleting all local data may recover.
        case corruptUserData(Error)
        /// An unrecoverable failure
        case fatal(Error)
    }

    private(set) var appComponent: AppComponent?
    private(set) var stationListComponent: StationListComponent?
    private(set) var loadState: LoadState?
    private(set) var loadError: LoadError?

    func load() async {
        guard loadState == nil else {
            return
        }
        withAnimation {
            loadState = .loading
        }
        let (nextLoadState, nextLoadError) = await _load()
        withAnimation {
            self.loadState = nextLoadState
            self.loadError = nextLoadError
        }
    }

    private func _load() async -> (LoadState?, LoadError?) {
        do {
            let appComponent = try await AppComponent.makeProductionAppComponent()
            self.appComponent = appComponent
            self.stationListComponent = appComponent.makeStationListComponent()
            return (.loaded, nil)
        } catch where error is AmtrakClientError {
            Logger.app.error("App load failed (transient): \(error)")
            return (nil, .transient(error))
        } catch let error as DatabaseSetupError {
            if let dbError = error.underlying as? DatabaseError,
               dbError.resultCode == .SQLITE_BUSY || dbError.resultCode == .SQLITE_LOCKED {
                Logger.app.error("App load failed (transient, database): \(error)")
                return (nil, .transient(error))
            } else {
                switch error.database {
                case .cache:
                    Logger.app.error("App load failed (corrupt cache): \(error)")
                    return (nil, .corruptCache(error))
                case .userData:
                    Logger.app.error("App load failed (corrupt user data): \(error)")
                    return (nil, .corruptUserData(error))
                }
            }
        } catch let error as DatabaseError
            where error.resultCode == .SQLITE_BUSY
               || error.resultCode == .SQLITE_LOCKED {
            Logger.app.error("App load failed (transient, database (not specified)): \(error)")
            return (nil, .transient(error))
        } catch where error is DatabaseError {
            Logger.app.error("App load failed (corrupt database (not specified)): \(error)")
            return (nil, .corruptCache(error))
        } catch {
            Logger.app.error("App load failed (transient): \(error)")
            return (nil, .transient(error))
        }
    }

    func resetCacheAndReload() async {
        AppComponent.deleteProductionCache()
        await load()
    }
    func resetAllAndReload() async {
        AppComponent.deleteProductionCache()
        AppComponent.deleteProductionUserData()
        await load()
    }
}
