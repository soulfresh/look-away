import Foundation

extension Array {
  /// Returns the element at the specified index, wrapping around if the index
  /// is out of bounds.
  ///
  /// You can use a negative index to count from the end of the array, or an
  /// index greater than the array's count to wrap around to the beginning.
  /// Returns `nil` if the array is empty.
  ///
  /// - Parameter index: The index of the element to access.
  /// - Returns: The element at the wrapped index, or `nil` if the array is empty.
  func wrapping(at index: Int) -> Element? {
    guard !isEmpty else {
      return nil
    }

    let remainder = index % count
    let wrappedIndex = remainder < 0 ? remainder + count : remainder
    return self[wrappedIndex]
  }
}
