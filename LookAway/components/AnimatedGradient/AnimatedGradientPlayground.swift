//
//  AnimatedGradientPlayground.swift
//  LookAway
//
//  Created by robert marc wren on 10/15/25.
//

import SwiftUI
import simd

// A struct representing a point in the grid with column, row, and flat index
struct GridPoint: CustomStringConvertible {
  let column: Int
  let row: Int
  let index: Int
  var description: String {
    return "(col: \(column), row: \(row), idx: \(index))"
  }
}

protocol PointBehavior {
  /// Clamp proposed normalized point (0..1) given current mesh state.
  /// Note: the number of rows is computed from points.count and columns inside the behavior.
  func clamp(
    proposed p: SIMD2<Float>,
    index: Int,
    points: [MeshPoint],
    columns: Int
  ) -> SIMD2<Float>
}

/// Type-erased wrapper so we can store heterogeneous behaviors in @State
struct AnyPoint: PointBehavior {
  private let _clamp: (SIMD2<Float>, Int, [MeshPoint], Int) -> SIMD2<Float>

  init<B: PointBehavior>(_ base: B) {
    _clamp = base.clamp
  }

  func clamp(
    proposed p: SIMD2<Float>,
    index: Int,
    points: [MeshPoint],
    columns: Int
  ) -> SIMD2<Float> {
    _clamp(p, index, points, columns)
  }
}

// Corner points: immutable
struct CornerPoint: PointBehavior {
  func clamp(
    proposed p: SIMD2<Float>,
    index: Int,
    points: [MeshPoint],
    columns: Int
  ) -> SIMD2<Float> {
    return points[index].simdPosition
  }
}

// Edge points: lock to axis (x or y) and clamp between immediate neighbors along that axis
struct EdgePoint: PointBehavior {
  enum Axis { case horizontal, vertical }
  let axis: Axis
  // original orthogonal coordinate to lock to (y for horizontal, x for vertical)
  let fixedValue: Float
  let lowerNeighborIndex: Int?
  let upperNeighborIndex: Int?

  init(index: Int, columns: Int, points: [MeshPoint]) {
    let rows = GridHelper.rows(forPointCount: points.count, columns: columns) ?? 1
    let col = index % columns
    let row = index / columns

    // horizontal edge
    if row == 0 || row == rows - 1 {
      axis = .horizontal
      fixedValue = points[index].simdPosition.y
      if col > 0 {
        lowerNeighborIndex = row * columns + (col - 1)
      } else {
        lowerNeighborIndex = nil
      }
      if col < columns - 1 {
        upperNeighborIndex = row * columns + (col + 1)
      } else {
        upperNeighborIndex = nil
      }
    }
    // vertical edge
    else {
      axis = .vertical
      fixedValue = points[index].simdPosition.x
      if row > 0 {
        lowerNeighborIndex = (row - 1) * columns + col
      } else {
        lowerNeighborIndex = nil
      }
      if row < rows - 1 {
        upperNeighborIndex = (row + 1) * columns + col
      } else {
        upperNeighborIndex = nil
      }
    }
  }

  func clamp(
    proposed p: SIMD2<Float>,
    index: Int,
    points: [MeshPoint],
    columns: Int
  ) -> SIMD2<Float> {
    var p = p

    switch axis {
    case .horizontal:
      // lock Y to the outer edge coordinate
      p.y = fixedValue
      // clamp X between neighbors if both exist
      if let l = lowerNeighborIndex, let r = upperNeighborIndex {
        // guard indices
        if l >= 0 && l < points.count && r >= 0 && r < points.count {
          let leftX = points[l].simdPosition.x
          let rightX = points[r].simdPosition.x
          let lowerX = min(leftX, rightX)
          let upperX = max(leftX, rightX)
          p.x = min(max(p.x, lowerX), upperX)
        }
      }
    case .vertical:
      // lock X to the outer edge coordinate
      p.x = fixedValue
      if let t = lowerNeighborIndex, let b = upperNeighborIndex {
        if t >= 0 && t < points.count && b >= 0 && b < points.count {
          let topY = points[t].simdPosition.y
          let bottomY = points[b].simdPosition.y
          let lowerY = min(topY, bottomY)
          let upperY = max(topY, bottomY)
          p.y = min(max(p.y, lowerY), upperY)
        }
      }
    }

    return p
  }
}

/// Inner grid points have their movement constrained within a diagonal band
/// running top, left to bottom, right. The bounds of the diagonal are defined
/// by the diagonal line that runs through the neighbor to the left and right
/// of the point.
///
/// InnerPoints are guaranteed to be part of a grid that is at
/// least 3x3 in size and are always an inner point (they never fall on the edge
/// of the grid).
struct InnerPoint: PointBehavior {
  let leftNeighbor: GridPoint
  let leftDiagonal: [GridPoint]
  let rightNeighbor: GridPoint
  let rightDiagonal: [GridPoint]
  let bounds: [GridPoint]

  init(index: Int, columns: Int, points: [MeshPoint]) {
    // Arithmetic-based diagonal calculation using d = c - r
    // Assumes this initializer is only used for true inner points and columns >= 3.
    let rows = GridHelper.rows(forPointCount: points.count, columns: columns) ?? 1
    let col = index % columns
    let row = index / columns

    self.leftNeighbor = GridPoint(
      column: col - 1,
      row: row,
      index: (row * columns) + (col - 1)
    )
    self.leftDiagonal = GridHelper.diagonalLine(
      through: self.leftNeighbor,
      columns: columns,
      rows: rows
    )

    self.rightNeighbor = GridPoint(
      column: col + 1,
      row: row,
      index: (row * columns) + (col + 1)
    )
    self.rightDiagonal = GridHelper.diagonalLine(
      through: self.rightNeighbor,
      columns: columns,
      rows: rows
    )

    // Construct the closed polygon: left diagonal (top→bottom) + right diagonal (bottom→top)
    self.bounds = self.leftDiagonal + self.rightDiagonal.reversed()
  }

  func clamp(
    proposed p: SIMD2<Float>,
    index: Int,
    points: [MeshPoint],
    columns: Int
  ) -> SIMD2<Float> {
    // Convert bounds GridPoints to actual SIMD2<Float> positions
    var polygon: [SIMD2<Float>] = []
    for gp in bounds {
      guard gp.index >= 0 && gp.index < points.count else { continue }
      polygon.append(points[gp.index].simdPosition)
    }

    // Need at least 3 points for a valid polygon
    guard polygon.count >= 3 else { return p }

    // Check if point is inside the polygon
    if GridHelper.isInsidePoly(p, bounds: polygon) {
      return p
    }

    // Point is outside, clamp to nearest boundary
    return GridHelper.clampToPolyBounds(p, bounds: polygon)
  }
}

func makeBehavior(for index: Int, columns: Int, currentPoints: [MeshPoint]) -> AnyPoint {
  let type = GridHelper.edgeType(
    for: index,
    columns: columns,
    rows: GridHelper.rows(
      forPointCount: currentPoints.count,
      columns: columns
    )
  )

  if type == .corner {
    return AnyPoint(CornerPoint())
  }
  if type == .inner {
    return AnyPoint(InnerPoint(index: index, columns: columns, points: currentPoints))
  }
  return AnyPoint(EdgePoint(index: index, columns: columns, points: currentPoints))
}

struct AnimatedGradientPlayground: View {
  let debug = true
  let columns = 4
  let rows = 4

  @State private var points: [MeshPoint]

  // Helper to generate a random Color
  private static func randomColor() -> Color {
    Color(hue: Double.random(in: 0...1), saturation: 0.7, brightness: 0.9)
  }

  init() {
    var generatedPoints: [MeshPoint] = []
    for row in 0..<rows {
      for col in 0..<columns {
        let cols = GridHelper.identity(columns)
        let rowsCount = GridHelper.identity(rows)
        let x = cols == 1 ? 0.5 : CGFloat(col) / CGFloat(cols - 1)
        let y = rowsCount == 1 ? 0.5 : CGFloat(row) / CGFloat(rowsCount - 1)
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

  @State private var activeBehavior: AnyPoint? = nil

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

  var body: some View {
    GeometryReader { geo in
      ZStack {
        ForEach(Array(points.enumerated()), id: \.offset) { pointIndex, point in
          let isCorner =
            GridHelper.edgeType(
              for: pointIndex, columns: columns, rows: rows) == .corner

          // Draw lines from this point to all immediate neighbors (including diagonals)
          let neighbors = GridHelper.neighborIndices(
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
                  // Create or reuse the behavior for this drag target
                  if activeBehavior == nil {
                    activeBehavior = makeBehavior(
                      for: pointIndex,
                      columns: columns,
                      currentPoints: points
                    )
                  }

                  // Normalized position within [0, 1]
                  let rawX = value.location.x / geo.size.width
                  let rawY = value.location.y / geo.size.height
                  let newX = min(max(0, rawX), 1)
                  let newY = min(max(0, rawY), 1)

                  let proposed = SIMD2<Float>(Float(newX), Float(newY))

                  // Ask the behavior to clamp the proposed point
                  let clamped =
                    activeBehavior?.clamp(
                      proposed: proposed,
                      index: pointIndex,
                      points: points,
                      columns: columns
                    ) ?? proposed

                  var newPoints = points
                  let newPoint = SIMD2<Float>(clamped.x, clamped.y)
                  newPoints[pointIndex] = MeshPoint(
                    position: newPoint,
                    color: point.color
                  )
                  points = newPoints
                }
                .onEnded { _ in
                  activeBehavior = nil
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
