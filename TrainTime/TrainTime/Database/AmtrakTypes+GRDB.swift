import Amtrak
import GRDB

// String-backed RawRepresentable enums: declare conformance and GRDB
// stores/retrieves them as plain TEXT using their rawValue.
extension Heading: @retroactive DatabaseValueConvertible {}
extension TrainState: @retroactive DatabaseValueConvertible {}
extension StationStatus: @retroactive DatabaseValueConvertible {}
