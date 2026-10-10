import Foundation
import GRDB
import os
import SwiftConcurrencySerialQueue

// MARK: - Storage

/// Why iCloud says the key-value store changed under us.
enum FavoritesCloudChangeReason: Sendable {
    /// Another device wrote.
    case serverChange
    /// The first download after launch or sign in.
    case initialSync
    /// Our last write was rejected; anything we push now is rejected too.
    case quotaViolation
    /// The signed in account changed, so the cloud value belongs to someone else.
    case accountChange
    case unknown
}

/// The slice of iCloud key-value storage the favorites store needs, so tests
/// can stand in for it.
protocol FavoritesCloudStorage: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?,
             forKey key: String)
    func synchronize()
    /// Changes made by something other than this process, as they arrive.
    func externalChanges() -> AsyncStream<FavoritesCloudChangeReason>
}

/// `NSUbiquitousKeyValueStore.default` behind the storage protocol.
struct UbiquitousFavoritesCloudStorage: FavoritesCloudStorage {
    func data(forKey key: String) -> Data? {
        NSUbiquitousKeyValueStore.default.data(forKey: key)
    }
    func set(_ data: Data?,
             forKey key: String) {
        NSUbiquitousKeyValueStore.default.set(data,
                                              forKey: key)
    }
    func synchronize() {
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    func externalChanges() -> AsyncStream<FavoritesCloudChangeReason> {
        AsyncStream { continuation in
            // Only ever handed back to NotificationCenter, which is thread-safe.
            nonisolated(unsafe) let token = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default,
                queue: nil
            ) { notification in
                // Reduce the notification to a Sendable value here, on the
                // posting thread, rather than sending the notification across.
                let reason = notification
                    .userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                continuation.yield(FavoritesCloudChangeReason(reason))
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}

private extension FavoritesCloudChangeReason {
    init(_ reason: Int?) {
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange:
            self = .serverChange
        case NSUbiquitousKeyValueStoreInitialSyncChange:
            self = .initialSync
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            self = .quotaViolation
        case NSUbiquitousKeyValueStoreAccountChange:
            self = .accountChange
        default:
            self = .unknown
        }
    }
}

// MARK: - Record

/// One station's favorite state and when it was decided. Unfavoriting is a
/// record with `isFavorite == false`, so removals travel between devices
/// instead of being indistinguishable from "never favorited".
struct FavoriteRecord: Codable, Equatable, Sendable {
    let code: String
    let isFavorite: Bool
    let updatedAt: Date
    /// Where the station sits among favorites. Nil for unfavorites and for
    /// records from app versions that didn't order favorites. Left out of
    /// the JSON when nil, and ignored by older versions when present, so
    /// both directions of the upgrade keep decoding.
    var sortOrder: Double?
    init(code: String,
         isFavorite: Bool,
         updatedAt: Date,
         sortOrder: Double? = nil) {
        self.code = code
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
}

extension FavoriteRecord {
    /// Last writer wins. On a tie, keeping a favorite beats dropping one,
    /// and knowing the order beats not knowing it. A winning favorite that
    /// has no position takes the loser's, so toggling on an older app
    /// version doesn't throw the station's place away. Symmetric, so the
    /// result doesn't depend on which side was merged first.
    static func resolve(_ lhs: FavoriteRecord,
                        _ rhs: FavoriteRecord) -> FavoriteRecord {
        var winner: FavoriteRecord
        let loser: FavoriteRecord
        if lhs.updatedAt != rhs.updatedAt {
            (winner, loser) = lhs.updatedAt > rhs.updatedAt ? (lhs, rhs) : (rhs, lhs)
        } else if lhs.isFavorite != rhs.isFavorite {
            (winner, loser) = lhs.isFavorite ? (lhs, rhs) : (rhs, lhs)
        } else {
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?):
                (winner, loser) = left <= right ? (lhs, rhs) : (rhs, lhs)
            case (_?, nil):
                (winner, loser) = (lhs, rhs)
            default:
                (winner, loser) = (rhs, lhs)
            }
        }
        if winner.isFavorite, winner.sortOrder == nil {
            winner.sortOrder = loser.sortOrder
        }
        return winner
    }
}

extension [FavoriteRecord] {
    /// Merges per station; see `FavoriteRecord.resolve`.
    func merged(with other: [FavoriteRecord]) -> [FavoriteRecord] {
        var byCode: [String: FavoriteRecord] = [:]
        for record in self + other {
            guard let existing = byCode[record.code] else {
                byCode[record.code] = record
                continue
            }
            byCode[record.code] = FavoriteRecord.resolve(existing, record)
        }
        return byCode.values.sorted { $0.code < $1.code }
    }
}

// MARK: - Store

/// Keeps station favorites in step across the user's devices through iCloud
/// key-value storage.
///
/// The user data database stays the local source of truth and the UI keeps
/// observing it as before. The cloud holds a list of `FavoriteRecord`s and
/// every reconciliation merges the two sides per station by `updatedAt`, so a
/// device joining late adds its favorites instead of replacing everyone
/// else's, and an unfavorite made on one device reaches the others.
///
/// All work runs through one serial queue: a local toggle, an external
/// change, and the start-up reconciliation can't interleave at the database
/// awaits and undo each other.
actor FavoritesCloudStore {
    private static let key = "favoriteStationRecords"
    private let userDataConnection: DatabasePool
    private let storage: any FavoritesCloudStorage
    private let now: @Sendable () -> Date
    private var externalChangesTask: Task<Void, Never>?
    private let queue = SerialQueueThrowing()
    init(userDataConnection: DatabasePool,
         storage: any FavoritesCloudStorage,
         now: @escaping @Sendable () -> Date) {
        self.userDataConnection = userDataConnection
        self.storage = storage
        self.now = now
    }
    deinit {
        externalChangesTask?.cancel()
    }
    /// Reconciles with whatever iCloud has cached and starts following changes
    /// from other devices. Call once the rest of the app is ready to observe
    /// favorites; calling again is a no-op.
    func start() async {
        guard externalChangesTask == nil else {
            return
        }
        let changes = storage.externalChanges()
        externalChangesTask = Task { [weak self] in
            for await reason in changes {
                guard let self else {
                    return
                }
                await self.handle(reason)
            }
        }
        // Ask for the latest value. Anything newer than the local cache
        // arrives later as an external change and is reconciled then.
        storage.synchronize()
        await reconcileSerialized(pushAllowed: true)
    }
    private func handle(_ reason: FavoritesCloudChangeReason) async {
        switch reason {
        case .serverChange, .initialSync, .unknown:
            await reconcileSerialized(pushAllowed: true)
        case .accountChange:
            // The cached value now belongs to a different account. Local data
            // is still this device's truth, so merge rather than adopt: a
            // missing cloud value must not read as "nothing is favorited".
            await reconcileSerialized(pushAllowed: true)
        case .quotaViolation:
            // Take what the server has, but pushing would just be rejected
            // again. Codes are small enough this probably means something 
            // else is wrong.
            Logger.service.error("FavoritesCloudStore: iCloud quota violation")
            await reconcileSerialized(pushAllowed: false)
        }
    }
    private func reconcileSerialized(pushAllowed: Bool) async {
        // reconcile() logs its own failures and never throws, so the only
        // thing to discard here is the queue's throwing signature.
        _ = try? await queue.enqueue { _ in
            await self.reconcile(pushAllowed: pushAllowed)
        }
    }
    // MARK: Reconcile
    /// Merges the database and the cloud per station and writes whichever
    /// side is behind.
    private func reconcile(pushAllowed: Bool) async {
        do {
            let local = try await localRecords()
            let cloud = cloudRecords()
            let merged = local.merged(with: cloud)
            if merged != local {
                try await write(merged)
            }
            if pushAllowed && merged != cloud {
                push(merged)
            }
        } catch {
            Logger.service.error("FavoritesCloudStore: reconcile failed \(error)")
        }
    }
    /// Rows that carry a timestamp as they are. Favorites written before
    /// timestamps existed are stamped now, so they survive the first merge
    /// instead of losing to every cloud record.
    private func localRecords() async throws -> [FavoriteRecord] {
        let now = now()
        return try await userDataConnection.read { db in
            try StationUserData
                .fetchAll(db)
                .compactMap { row in
                    if let updatedAt = row.updatedAt {
                        return FavoriteRecord(code: row.code,
                                              isFavorite: row.isFavorite == true,
                                              updatedAt: updatedAt,
                                              sortOrder: row.isFavorite == true ? row.sortOrder : nil)
                    }
                    guard row.isFavorite == true else {
                        return nil
                    }
                    return FavoriteRecord(code: row.code,
                                          isFavorite: true,
                                          updatedAt: now,
                                          sortOrder: row.sortOrder)
                }
        }
    }
    private func cloudRecords() -> [FavoriteRecord] {
        guard let data = storage.data(forKey: Self.key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([FavoriteRecord].self,
                                            from: data)
        } catch {
            Logger.service.error("FavoritesCloudStore: ignoring undecodable cloud value \(error)")
            return []
        }
    }
    private func write(_ records: [FavoriteRecord]) async throws {
        try await userDataConnection.write { db in
            for record in records {
                try StationUserData(record)
                    .upsert(db)
            }
        }
    }
    private func push(_ records: [FavoriteRecord]) {
        do {
            storage.set(try JSONEncoder().encode(records),
                        forKey: Self.key)
            storage.synchronize()
        } catch {
            Logger.service.error("FavoritesCloudStore: push failed \(error)")
        }
    }
}

// MARK: - Writing

/// The app writes favorites through the store, so each change is stamped and
/// mirrored to iCloud in the same queued step, after any reconciliation
/// already in flight.
extension FavoritesCloudStore: WriteUserDataForStationProvider {
    func writeUserData(_ changes: [StationUserDataChange]) async throws {
        let now = now()
        let records = changes.map { change in
            FavoriteRecord(code: change.code,
                           isFavorite: change.isFavorite == true,
                           updatedAt: now,
                           sortOrder: change.isFavorite == true ? change.sortOrder : nil)
        }
        try await queue.enqueue { _ in
            try await self.userDataConnection.write { db in
                for record in records {
                    try StationUserData(record)
                        .upsert(db)
                }
            }
            await self.push(self.cloudRecords().merged(with: records))
        }
    }
}

private extension StationUserData {
    init(_ record: FavoriteRecord) {
        self.init(code: record.code,
                  isFavorite: record.isFavorite ? true : nil,
                  updatedAt: record.updatedAt,
                  sortOrder: record.isFavorite ? record.sortOrder : nil)
    }
}
