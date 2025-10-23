import simd

struct GridHelper {
  enum Edge {
    case top
    case bottom
    case left
    case right
    case corner
    case inner
  }

  /// Prevents compile-time constant folding to avoid "will never be executed" warnings
  @inline(never)
  static func identity<T>(_ value: T) -> T { value }

  static func edgeType(for index: Int, columns: Int, rows: Int) -> Edge {
    let col = index % columns
    let row = index / columns

    // Corner points
    if (row == 0 || row == rows - 1) && (col == 0 || col == columns - 1) {
      return .corner
    }
    // Top edge
    else if row == 0 {
      return .top
    }
    // Bottom edge
    else if row == rows - 1 {
      return .bottom
    }
    // Left edge
    else if col == 0 {
      return .left
    }
    // Right edge
    else if col == columns - 1 {
      return .right
    }
    // Inner point
    else {
      return .inner
    }
  }

  static func edgeType(column: Int, row: Int, columns: Int, rows: Int) -> Edge {
    edgeType(for: row * columns + column, columns: columns, rows: rows)
  }

  /// Returns the indices of the bounding polygon around a center point in the grid
  /// defined by the number of columns and rows. The bounding polygon is defined as
  /// the point above, right, below, and left of the given point.
  static func boundingPolyIndicies(for idx: Int, columns: Int, rows: Int) -> [Int]? {
    let col = idx % columns
    let row = idx / columns
    if col > 0 && col < columns - 1 && row > 0 && row < rows - 1 {
      let top = (row - 1) * columns + col
      let right = row * columns + (col + 1)
      let bottom = (row + 1) * columns + col
      let left = row * columns + (col - 1)
      return [top, right, bottom, left]
    }
    return nil
  }

  /// Point-in-polygon test (works for convex and concave polygons)
  static func isInsidePoly(_ p: SIMD2<Float>, bounds: [SIMD2<Float>]) -> Bool {
    // Ray casting algorithm
    let n = bounds.count
    var inside = false
    var j = n - 1
    for i in 0..<n {
      let pi = bounds[i]
      let pj = bounds[j]
      if ((pi.y > p.y) != (pj.y > p.y))
        && (p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y + 0.000001) + pi.x)
      {
        inside.toggle()
      }
      j = i
    }
    return inside
  }

  /// Project a point onto the closest point on the boundary of a convex quadrilateral
  static func clampToPolyBounds(_ p: SIMD2<Float>, bounds: [SIMD2<Float>]) -> SIMD2<Float> {
    func closestPointOnSegment(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ p: SIMD2<Float>) -> SIMD2<
      Float
    > {
      let ab = b - a
      let t = simd_dot(p - a, ab) / simd_dot(ab, ab)
      let tClamped = min(max(t, 0), 1)
      return a + ab * tClamped
    }
    var minDist = Float.greatestFiniteMagnitude
    var closest = bounds[0]
    for i in 0..<bounds.count {
      let a = bounds[i]
      let b = bounds[(i + 1) % bounds.count]
      let candidate = closestPointOnSegment(a, b, p)
      let dist = simd_distance(candidate, p)
      if dist < minDist {
        minDist = dist
        closest = candidate
      }
    }
    return closest
  }

  /// Signed side of point p relative to the directed line a->b.
  /// Positive means p is to the left of the line.
  static func signedSide(of p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> Float {
    let ab = b - a
    let ap = p - a
    return ab.x * ap.y - ab.y * ap.x
  }

  /// Closest point on a segment a-b to point p
  static func projectPointToSegment(_ p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> SIMD2<
    Float
  > {
    let ab = b - a
    let denom = simd_dot(ab, ab)
    if denom <= 1e-9 { return a }
    var t = simd_dot(p - a, ab) / denom
    t = min(max(t, 0), 1)
    return a + ab * t
  }

  /// Immediate neighbor indices (including diagonals) for a point in the grid.
  /// Returns up to 8 neighbors within one row/column step, excluding the point itself.
  static func neighborIndices(for idx: Int, columns: Int, rows: Int) -> [Int] {
    let col = idx % columns
    let row = idx / columns
    var neighbors: [Int] = []
    for dRow in -1...1 {
      for dCol in -1...1 {
        if dRow == 0 && dCol == 0 { continue }
        let nRow = row + dRow
        let nCol = col + dCol
        if nRow >= 0 && nRow < rows && nCol >= 0 && nCol < columns {
          neighbors.append(nRow * columns + nCol)
        }
      }
    }
    return neighbors
  }

  /// Compute number of rows from point count and column count. Returns nil if invalid
  /// (e.g. columns <= 0 or pointsCount not divisible by columns).
  static func rows(forPointCount count: Int, columns: Int) -> Int {
    guard columns > 0, count % columns == 0 else { return 0 }
    return count / columns
  }

  static func innerPointCount(columns: Int, rows: Int) -> Int {
    max(0, columns - 2) * max(0, rows - 2)
  }

  /// Compute the most rightward diagonal line possible that runs through
  /// the given grid point. Returns an array of GridPoint structs representing
  /// the line.
  static func diagonalLine(
    through point: GridPoint,
    columns: Int,
    rows: Int
  ) -> [GridPoint] {
    let d = point.column - point.row
    var line: [GridPoint] = []
    for r in 0..<rows {
      let c = d + r
      let clampedC = min(max(c, 0), columns - 1)
      let clampedR = min(max(r, 0), rows - 1)
      let clampedIdx = clampedR * columns + clampedC
      line.append(
        GridPoint(
          column: clampedC,
          row: clampedR,
          index: clampedIdx
        )
      )
    }

    return line
  }
}
