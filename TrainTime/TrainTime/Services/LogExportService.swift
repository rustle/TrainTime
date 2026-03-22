import CoreTransferable
import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers

struct LogExportService: Sendable {
    enum TimeWindow: Sendable {
        case lastHour
        case last24Hours
        case fullSession

        var startDate: Date {
            switch self {
            case .lastHour: return Date(timeIntervalSinceNow: -3600)
            case .last24Hours: return Date(timeIntervalSinceNow: -86400)
            case .fullSession: return .distantPast
            }
        }

        var label: String {
            switch self {
            case .lastHour: return "Last hour"
            case .last24Hours: return "Last 24 hours"
            case .fullSession: return "Full session"
            }
        }
    }

    @MainActor
    private func preamble(timeWindow: TimeWindow) async -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let device = UIDevice.current
        let exportDate = Date.now.formatted(date: .complete, time: .complete)
        return
            """
            TrainTime \(appVersion) (\(buildNumber))
            \(device.model), \(device.systemName) \(device.systemVersion)
            Exported: \(exportDate)
            Window: \(timeWindow.label)
            """
    }

    func export(timeWindow: TimeWindow = .last24Hours) async throws -> String {
        let preamble = await preamble(timeWindow: timeWindow)
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: timeWindow.startDate)
        let entries = try store.getEntries(
            at: position,
            matching: NSPredicate(format: "subsystem == %@", "TrainTime")
        )
        let logEntries = entries.compactMap { entry -> LogEntry? in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            return LogEntry(from: logEntry)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(logEntries), encoding: .utf8) ?? "[]"
        return preamble + "\n\n------\n\n" + json
    }
}

private struct LogEntry: Encodable, Sendable {
    let category: String
    let date: Date
    let level: String
    let message: String

    init(from entry: OSLogEntryLog) {
        category = entry.category
        date = entry.date
        level = entry.level.name
        message = entry.composedMessage
    }
}

private extension OSLogEntryLog.Level {
    var name: String {
        switch self {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}
