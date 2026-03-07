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
