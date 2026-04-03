import Foundation

///
struct TrainAtStop: Codable, Sendable, Equatable, CustomDebugStringConvertible {
    ///
    let train: Train
    ///
    let stop: Stop
    ///
    var debugDescription: String {
        JSONEncoder.jsonDebugDescription(for: self) ?? "TrainAtStop"
    }
}
