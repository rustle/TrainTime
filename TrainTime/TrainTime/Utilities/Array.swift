import Foundation

extension Array {
    /// The array with the elements at `source` moved to sit before whatever
    /// is currently at `destination`, matching SwiftUI's
    /// `move(fromOffsets:toOffset:)` without importing SwiftUI.
    func moving(fromOffsets source: IndexSet,
                toOffset destination: Int) -> Self {
        let moved = source.map { self[$0] }
        var result = self
        for index in source.reversed() {
            result.remove(at: index)
        }
        let insertion = destination - source.count(where: { $0 < destination })
        result.insert(contentsOf: moved,
                      at: insertion)
        return result
    }
}

extension Array where Element: Comparable {
    @inlinable
    func binarySearch(_ target: Element) -> Index {
        var left = 0
        var right = count - 1
        while left <= right {
            let mid = left + (right - left) / 2
            if self[mid] == target {
                return mid
            } else if self[mid] < target {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        return left
    }
    @inlinable
    mutating func sortedInsert(_ target: Element) {
        var left = 0
        var right = count - 1
        while left <= right {
            let mid = left + (right - left) / 2
            if self[mid] == target {
                insert(target, at: mid)
                return
            } else if self[mid] < target {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        insert(target, at: left)
    }
}
