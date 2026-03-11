import Foundation

extension JSONEncoder {
    static func jsonDebugDescription<V: Codable>(for value: V) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data,
                                  encoding: .utf8) else {
            return nil
        }
        return string
    }
}
