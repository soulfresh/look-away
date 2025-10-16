//
//  AnimatedGradientPlayground.swift
//  LookAway
//
//  Created by robert marc wren on 10/15/25.
//

import SwiftUI
import simd

struct MeshGridHelper {
  /// Determine if the given index would represent a point that is not on the
  /// edge of the grid defined by the number of columns and rows.
  static func isCenterPoint(index: Int, columns: Int, rows: Int) -> Bool {
    let col = index % columns
    let row = index / columns
    return col > 0 && col < columns - 1 && row > 0 && row < rows - 1
  }
  
  /// Prevents compile-time constant folding to avoid "will never be executed" warnings
  @inline(never)
  static func identity<T>(_ value: T) -> T { value }
  
  /// Determine if the given index would represent a corner point in the grid
  /// defined by the number of columns and rows.
  static func isCornerPoint(index: Int, columns: Int, rows: Int) -> Bool {
    let col = index % columns
    let row = index / columns
    return (row == 0 || row == rows - 1) && (col == 0 || col == columns - 1)
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
  static func projectPointToSegment(_ p: SIMD2<Float>, a: SIMD2<Float>, b: SIMD2<Float>) -> SIMD2<Float> {
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
}

struct AnimatedGradientPlayground: View {
  let debug = true
  let columns = 4
  let rows = 3

  @State private var points: [MeshPoint]

  // Helper to generate a random Color
  private static func randomColor() -> Color {
    Color(hue: Double.random(in: 0...1), saturation: 0.7, brightness: 0.9)
  }

  init() {
    var generatedPoints: [MeshPoint] = []
    for row in 0..<rows {
      for col in 0..<columns {
        let cols = MeshGridHelper.identity(columns)
        let rowsCount = MeshGridHelper.identity(rows)
        let x = cols == 1 ? 0.5 : CGFloat(col) / CGFloat(cols - 1)
        let y = rowsCount == 1 ? 0.5 : CGFloat(row) / CGFloat(rowsCount - 1)
//        let isCenter = MeshGridHelper.isCenterPoint(
//          index: row * columns + col, columns: columns, rows: rows)
//        let color: Color = isCenter ? AnimatedGradientPlayground.randomColor() : .white
        // Use a random color for all points so I can more easily see rendering artifacts
        let color: Color = AnimatedGradientPlayground.randomColor()
        generatedPoints.append(MeshPoint(position: UnitPoint(x: x, y: y), color: color))
      }
    }
    _points = State(initialValue: generatedPoints)
  }

  var body: some View {
    ZStack {
      MeshGradient(
        width: columns,
        height: rows,
        points: points.map { $0.simdPosition },
        colors: points.map { $0.color },
      )
      if debug {
        MeshDebugOverlay(columns: columns, points: $points)
      }
    }
  }
}

struct MeshDebugOverlay: View {
  @Binding var points: [MeshPoint]
  let columns: Int
  let rows: Int

  init(columns: Int, points: Binding<[MeshPoint]>) {
    self._points = points
    self.columns = columns
    guard points.wrappedValue.count % columns == 0 else {
      fatalError("points.count must be divisible by columns")
    }
    self.rows = points.wrappedValue.count / columns
    guard points.wrappedValue.count == self.rows * columns else {
      fatalError("points.count must equal rows * columns")
    }
  }

  func isCenterPoint(index: Int) -> Bool {
    MeshGridHelper.isCenterPoint(index: index, columns: columns, rows: rows)
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        ForEach(Array(points.enumerated()), id: \.offset) { pointIndex, point in
          let isCorner = MeshGridHelper.isCornerPoint(
            index: pointIndex, columns: columns, rows: rows)

          // Draw lines from this point to all immediate neighbors (including diagonals)
          let neighbors = MeshGridHelper.neighborIndices(
            for: pointIndex, columns: columns, rows: rows)
          Path { path in
            let from = CGPoint(
              x: CGFloat(point.position.x) * geo.size.width,
              y: CGFloat(point.position.y) * geo.size.height
            )
            for n in neighbors {
              // Draw each edge once by only drawing to higher index neighbor
              if n > pointIndex {
                let toPoint = points[n].position
                let to = CGPoint(
                  x: CGFloat(toPoint.x) * geo.size.width,
                  y: CGFloat(toPoint.y) * geo.size.height
                )
                path.move(to: from)
                path.addLine(to: to)
              }
            }
          }
          // Use black as the line color so it is easier to see
          .stroke(Color.black.opacity(0.9), lineWidth: 1.5)
          
          DebugCircle(color: point.color, index: pointIndex, size: 20)
            .position(
              x: CGFloat(point.position.x) * geo.size.width,
              y: CGFloat(point.position.y) * geo.size.height
            )
            .allowsHitTesting(!isCorner)
            .gesture(
              DragGesture()
                .onChanged { value in
                  // TODO We don't need this normalization step because points are already normalized
                  // Normalized position within [0, 1]
                  var newX = min(max(0, value.location.x / geo.size.width), 1)
                  var newY = min(max(0, value.location.y / geo.size.height), 1)

                  // Grid coordinates
                  let col = pointIndex % columns
                  let row = pointIndex / columns

                  // Corner points are immovable
                  if MeshGridHelper.isCornerPoint(index: pointIndex, columns: columns, rows: rows) {
                    return
                  }

                  // Edge constraints: lock to outer edges
                  if row == 0 {
                    newY = 0
                  }  // top edge
                  else if row == rows - 1 {
                    newY = 1
                  }  // bottom edge
                  else if col == 0 {
                    newX = 0
                  }  // left edge
                  else if col == columns - 1 {
                    newX = 1
                  }  // right edge

                  // Maintain ordering along edges: clamp along the moving axis
                  // between immediate neighbors
                  if row == 0 || row == rows - 1 {
                    // Horizontal edge (top or bottom) -
                    // clamp X between left and right neighbors
                    if col > 0 && col < columns - 1 {
                      let rowStart = row * columns
                      let leftIdx = rowStart + (col - 1)
                      let rightIdx = rowStart + (col + 1)
                      let leftX = CGFloat(points[leftIdx].position.x)
                      let rightX = CGFloat(points[rightIdx].position.x)
                      let lowerX = min(leftX, rightX)
                      let upperX = max(leftX, rightX)
                      // Clamp to ensure we don't pass neighbors
                      newX = min(max(newX, lowerX), upperX)
                    }
                  } else if col == 0 || col == columns - 1 {
                    // Vertical edge (left or right) - clamp Y between top and bottom neighbors
                    if row > 0 && row < rows - 1 {
                      let topIdx = (row - 1) * columns + col
                      let bottomIdx = (row + 1) * columns + col
                      let topY = CGFloat(points[topIdx].position.y)
                      let bottomY = CGFloat(points[bottomIdx].position.y)
                      let lowerY = min(topY, bottomY)
                      let upperY = max(topY, bottomY)
                      // Clamp to ensure we don't pass neighbors
                      newY = min(max(newY, lowerY), upperY)
                    }
                  }

                  // Additional clamp for inner points:
                  // keep each center on its side of the NW-SE diagonal polyline
                  var p = SIMD2<Float>(Float(newX), Float(newY))
                  if MeshGridHelper.isCenterPoint(index: pointIndex, columns: columns, rows: rows) {
                    // Build the two diagonal segments depending on which inner this is
                    var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
                    // true: keep signed side >= 0, false: <= 0
                    var requirePositiveSide = true

                    if col + 1 < columns - 1 {
                      // This is the left inner (e.g., 5).
                      // Constrain relative to 1->6 and 6->BR (11)
                      let topIdx = (row - 1) * columns + col
                      let rightCenterIdx = row * columns + (col + 1)
                      let brCornerIdx = (rows - 1) * columns + (columns - 1)
                      let a1 = points[topIdx].simdPosition
                      let b1 = points[rightCenterIdx].simdPosition
                      let a2 = b1
                      let b2 = points[brCornerIdx].simdPosition
                      segments = [(a1, b1), (a2, b2)]
                      // keep to the left of the directed lines
                      requirePositiveSide = true
                    } else if col - 1 > 0 {
                      // This is the right center (e.g., 6).
                      // Constrain relative to 0->5 and 5->10
                      let tlCornerIdx = 0
                      let leftCenterIdx = row * columns + (col - 1)
                      let bottomIdx = (row + 1) * columns + col
                      let a1 = points[tlCornerIdx].simdPosition
                      let b1 = points[leftCenterIdx].simdPosition
                      let a2 = b1
                      let b2 = points[bottomIdx].simdPosition
                      segments = [(a1, b1), (a2, b2)]
                      // keep to the right of the directed lines (signed side <= 0)
                      requirePositiveSide = false
                    } else {
                      // Fallback: use local diagonal through neighbors if layout differs
                      if row - 1 >= 0 && col - 1 >= 0 && row + 1 < rows && col + 1 < columns {
                        let a1 = points[(row - 1) * columns + col - 1].simdPosition
                        let b1 = points[pointIndex].simdPosition
                        let a2 = b1
                        let b2 = points[(row + 1) * columns + col + 1].simdPosition
                        segments = [(a1, b1), (a2, b2)]
                        requirePositiveSide = true
                      }
                    }

                    // Apply clamping against each segment if on the forbidden side
                    for (a, b) in segments {
                      // Skip degenerate segments
                      let ab = b - a
                      if simd_length_squared(ab) <= 1e-9 { continue }
                      let side = MeshGridHelper.signedSide(of: p, a: a, b: b)
                      if requirePositiveSide {
                        if side < 0 {
                          p = MeshGridHelper.projectPointToSegment(p, a: a, b: b)
                        }
                      } else {
                        if side > 0 {
                          p = MeshGridHelper.projectPointToSegment(p, a: a, b: b)
                        }
                      }
                    }

                    // Update clamped newX/newY from p
                    newX = CGFloat(p.x)
                    newY = CGFloat(p.y)
                  }

                  // Interior points are free to move (no extra clamping beyond [0,1])
                  var newPoints = points
                  let newPoint = SIMD2<Float>(Float(newX), Float(newY))
                  newPoints[pointIndex] = MeshPoint(position: newPoint, color: point.color)
                  points = newPoints

                  // Clamping code - disabled for now
                  //                  if isCenter, let boundingIndicies = MeshGridHelper.boundingPolyIndicies(for: pointIndex, columns: columns, rows: rows) {
                  //                    let bounds = boundingIndicies.map { points[$0].simdPosition }
                  //                    let clampedPoint: SIMD2<Float>
                  //                    if MeshGridHelper.isInsidePoly(newPoint, bounds: bounds) {
                  //                      clampedPoint = newPoint
                  //                    } else {
                  //                      clampedPoint = MeshGridHelper.clampToPolyBounds(newPoint, bounds: bounds)
                  //                    }
                  //                    newPoints[pointIndex] = MeshPoint(position: clampedPoint, color: point.color)
                  //                    points = newPoints
                  //                  } else {
                  //                    newPoints[pointIndex] = MeshPoint(position: newPoint, color: point.color)
                  //                    points = newPoints
                  //                  }
                }
            )
        }
      }
    }
  }
}

#Preview {
  HStack {
    AnimatedGradientPlayground()
  }
  .padding(20)
}
