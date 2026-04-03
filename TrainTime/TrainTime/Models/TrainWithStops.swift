import Foundation

/// Only used in tests for now

///
struct TrainWithStops: Codable, Sendable, Equatable, CustomDebugStringConvertible {
    ///
    let train: Train
    ///
    let stops: [Stop]
    ///
    var debugDescription: String {
        JSONEncoder.jsonDebugDescription(for: self) ?? "TrainAtStop"
    }
}
