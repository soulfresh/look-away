import Foundation

extension Array {
    /// Returns the next index in the array, wrapping around if necessary.
    ///
    /// - Parameter currentIndex: The current index in the array.
    /// - Returns: The next index, or `nil` if the array is empty.
    func nextIndex(after currentIndex: Int) -> Int? {
        guard !isEmpty else { return nil }
        return (currentIndex + 1) % count
    }
}
