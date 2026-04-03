import Foundation

extension String {
    var normalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current)
    }
}
