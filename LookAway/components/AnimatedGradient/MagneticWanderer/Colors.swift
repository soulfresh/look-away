import SwiftUI

extension MagneticWanderer {

  protocol ColorGrid {
    func getColor(atColumn column: Int, row: Int) -> Color
    var colorList: String { get }
  }

  /// Helper functions for color manipulation
  struct ColorHelper {
    /// Linearly interpolate between two colors in HSB space
    /// - Parameters:
    ///   - from: Starting color
    ///   - to: Ending color
    ///   - t: Interpolation factor (0.0 = from, 1.0 = to)
    /// - Returns: Interpolated color
    static func interpolateHSB(from color1: Color, to color2: Color, t: Double) -> Color {
      // Extract HSB components
      var h1: CGFloat = 0
      var s1: CGFloat = 0
      var b1: CGFloat = 0
      var a1: CGFloat = 0
      var h2: CGFloat = 0
      var s2: CGFloat = 0
      var b2: CGFloat = 0
      var a2: CGFloat = 0

      #if canImport(UIKit)
        UIColor(color1).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        UIColor(color2).getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
      #elseif canImport(AppKit)
        NSColor(color1).getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
        NSColor(color2).getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
      #endif

      // Linear interpolation
      let h = h1 + (h2 - h1) * t
      let s = s1 + (s2 - s1) * t
      let b = b1 + (b2 - b1) * t

      return Color(hue: Double(h), saturation: Double(s), brightness: Double(b))
    }

    /// Linearly interpolate between two colors in RGB space
    /// - Parameters:
    ///   - from: Starting color
    ///   - to: Ending color
    ///   - t: Interpolation factor (0.0 = from, 1.0 = to)
    /// - Returns: Interpolated color
    static func interpolateRGB(from color1: Color, to color2: Color, t: Double) -> Color {
      // Extract RGB components
      var r1: CGFloat = 0
      var g1: CGFloat = 0
      var b1: CGFloat = 0
      var a1: CGFloat = 0
      var r2: CGFloat = 0
      var g2: CGFloat = 0
      var b2: CGFloat = 0
      var a2: CGFloat = 0

      #if canImport(UIKit)
        UIColor(color1).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(color2).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
      #elseif canImport(AppKit)
        NSColor(color1).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        NSColor(color2).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
      #endif

      // Linear interpolation in RGB space
      let r = r1 + (r2 - r1) * t
      let g = g1 + (g2 - g1) * t
      let b = b1 + (b2 - b1) * t
      let a = a1 + (a2 - a1) * t

      return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    /// Generate a random color in HSB space with specified saturation
    /// - Parameter saturation: Saturation value (0.0 to 1.0)
    /// - Returns: Random color with the given saturation
    static func randomColor(saturation: Double) -> Color {
      let hue = Double.random(in: 0...1)
      return Color(hue: hue, saturation: saturation, brightness: 0.8)
    }

    /// Calculate interpolation factor (t) for a position with rotation applied
    /// - Parameters:
    ///   - column: Column index
    ///   - row: Row index
    ///   - columns: Total number of columns
    ///   - rows: Total number of rows
    ///   - rotationDegrees: Rotation angle (0° = top to bottom, 90° = left to right)
    /// - Returns: Interpolation factor from 0.0 to 1.0
    static func rotatedInterpolation(
      column: Int,
      row: Int,
      columns: Int,
      rows: Int,
      rotationDegrees: Double
    ) -> Double {
      // Normalize position to 0.0 - 1.0
      let colCount = max(columns - 1, 1)
      let rowCount = max(rows - 1, 1)
      let normalizedCol = Double(column) / Double(colCount)
      let normalizedRow = Double(row) / Double(rowCount)

      // Center the coordinates (-0.5 to 0.5)
      let centeredCol = normalizedCol - 0.5
      let centeredRow = normalizedRow - 0.5

      // Convert rotation to radians
      let radians = rotationDegrees * .pi / 180.0

      // Project the position onto the gradient direction vector
      let cosValue = cos(radians)
      let sinValue = sin(radians)
      let projection = centeredRow * cosValue + centeredCol * sinValue

      // Find the range of projection values across the entire grid
      let absCos = Swift.abs(cosValue)
      let absSin = Swift.abs(sinValue)
      let maxProjection = absCos * 0.5 + absSin * 0.5

      // Normalize projection to 0.0-1.0 range
      let normalized = projection / maxProjection
      let t = (normalized + 1.0) / 2.0

      // Clamp to 0.0-1.0 range
      return max(0.0, min(1.0, t))
    }
  }

  /// A rainbow of colors distributed across the grid.
  /// Supports rotation: 0° = left to right, 90° = top to bottom, etc.
  struct RainbowGrid: ColorGrid {
    let columns: Int
    let rows: Int
    private let rotationDegrees: Double

    init(columns: Int, rows: Int, rotationDegrees: Double = 90) {
      self.columns = columns
      self.rows = rows
      self.rotationDegrees = rotationDegrees
    }

    var colorList: String {
      return "Rainbow (full spectrum)"
    }

    func getColor(atColumn column: Int, row: Int) -> Color {
      // Get interpolation factor with rotation applied
      let t = ColorHelper.rotatedInterpolation(
        column: column,
        row: row,
        columns: columns,
        rows: rows,
        rotationDegrees: rotationDegrees
      )

      // Map t to hue (0.0 = red, 1.0 = red again, full spectrum)
      let hue = t

      // Vary saturation based on perpendicular axis
      // For horizontal (90°), vary by row; for vertical (0°), vary by column
      let perpendicularT = ColorHelper.rotatedInterpolation(
        column: column,
        row: row,
        columns: columns,
        rows: rows,
        rotationDegrees: rotationDegrees + 90
      )
      let saturation = 0.5 + perpendicularT * 0.5

      return Color(hue: hue, saturation: saturation, brightness: 0.8)
    }
  }

  /// A grid that colors the grid a solid background color and then
  /// places random colors in groups ("blobs") around the grid. The blobs can
  /// be 1 or more neighboring points in our grid. The position of the blobs
  /// and the number of blobs are random.
  ///
  /// For example, we might have a 4x4 white grid with a black blob at the
  /// points (1,1), (1,2), and (2,1).
  struct BlobColorGrid: ColorGrid {
    let columns: Int
    let rows: Int
    let background: Color

    // Dictionary mapping (column, row) to color
    private let colorMap: [String: Color]

    // Store blob colors for colorList
    private let blobColors: [Color]

    init(
      columns: Int,
      rows: Int,
      blobCount: Int = 1,
      backgroundColor: Color = .white,
      saturation saturationRange: ClosedRange<Double> = 0.5...0.8,
      brightness brightnessRange: ClosedRange<Double> = 0.7...0.8,
    ) {
      self.columns = columns
      self.rows = rows
      self.background = backgroundColor

      var map: [String: Color] = [:]

      // Generate random colors for blobs (with minimum hue separation)
      var hues: [Double] = []
      let minHueDifference = 10.0 / 360.0

      for _ in 0..<blobCount {
        var hue: Double
        var attempts = 0
        let maxAttempts = 100

        repeat {
          hue = Double.random(in: 0...1)
          attempts += 1

          let isFarEnough = hues.allSatisfy { existingHue in
            let diff = Swift.abs(hue - existingHue)
            let wrappedDiff = min(diff, 1.0 - diff)
            return wrappedDiff >= minHueDifference
          }

          if isFarEnough || attempts >= maxAttempts {
            hues.append(hue)
            break
          }
        } while true
      }

      let colors = hues.map { hue in
        let saturation = Double.random(in: saturationRange)
        return Color(
          hue: hue,
          saturation: saturation,
          brightness: Double.random(in: brightnessRange)
        )
      }

      self.blobColors = colors

      // Create blobs
      for blobIndex in 0..<blobCount {
        let blobColor = colors[blobIndex]

        // Pick random starting point
        // First blob starts from inner points only, others can start anywhere
        var currentCol: Int
        var currentRow: Int

        if blobIndex == 0 {
          // Inner points only (excluding edges)
          currentCol = Int.random(in: 1..<max(2, columns - 1))
          currentRow = Int.random(in: 1..<max(2, rows - 1))
        } else {
          // Any point
          currentCol = Int.random(in: 0..<columns)
          currentRow = Int.random(in: 0..<rows)
        }

        // Pick random number of points to fill (1 to 4 points per blob)
        let pointsToFill = Int.random(in: 1...4)

        for _ in 0..<pointsToFill {
          // Color current point
          let key = "\(currentCol),\(currentRow)"
          map[key] = blobColor

          // Pick a random neighboring point for next iteration
          // Neighbors: up, down, left, right
          let neighbors = [
            (currentCol, currentRow - 1),  // up
            (currentCol, currentRow + 1),  // down
            (currentCol - 1, currentRow),  // left
            (currentCol + 1, currentRow),  // right
          ]

          // Filter to valid neighbors within grid bounds
          let validNeighbors = neighbors.filter { col, row in
            col >= 0 && col < columns && row >= 0 && row < rows
          }

          // Pick random valid neighbor (or stay at current if no valid neighbors)
          if let neighbor = validNeighbors.randomElement() {
            currentCol = neighbor.0
            currentRow = neighbor.1
          }
        }
      }

      self.colorMap = map
    }

    var colorList: String {
      let allColors = [background] + blobColors
      return "\(allColors.map { $0.description }.joined(separator: ", "))"
    }

    func getColor(atColumn column: Int, row: Int) -> Color {
      let key = "\(column),\(row)"
      return colorMap[key] ?? background
    }
  }

  /// A grid that picks N random colors and interpolates between them.
  /// Supports rotation: 0° = top to bottom, 90° = left to right, etc.
  struct MultiColorGrid: ColorGrid, CustomStringConvertible {
    let columns: Int
    let rows: Int

    // Array of colors to interpolate between
    let colors: [Color]

    // Rotation angle in degrees (0 = top to bottom, 90 = left to right)
    private let rotationDegrees: Double

    var description: String {
      return
        "MultiColorGrid(colors: \(colors), rotationDegrees: \(rotationDegrees))"
    }

    var colorList: String {
      return "\(colors.map { $0.description }.joined(separator: ", "))"
    }

    init(columns: Int, rows: Int, colorCount: Int = 3, rotationDegrees: Double = 0) {
      self.columns = columns
      self.rows = rows
      self.rotationDegrees = rotationDegrees

      // Generate random colors with hues at least 10 degrees apart
      var hues: [Double] = []
      let minHueDifference = 10.0 / 360.0  // 10 degrees as fraction of full circle

      for _ in 0..<colorCount {
        var hue: Double
        var attempts = 0
        let maxAttempts = 100

        repeat {
          hue = Double.random(in: 0...1)
          attempts += 1

          // Check if this hue is far enough from all existing hues
          let isFarEnough = hues.allSatisfy { existingHue in
            let diff = Swift.abs(hue - existingHue)
            // Account for wraparound (e.g., 0.99 and 0.01 are close)
            let wrappedDiff = min(diff, 1.0 - diff)
            return wrappedDiff >= minHueDifference
          }

          if isFarEnough || attempts >= maxAttempts {
            hues.append(hue)
            break
          }
        } while true
      }

      // Create colors from the selected hues
      self.colors = hues.map { hue in
        let saturation = Double.random(in: 0.5...0.8)
        return Color(hue: hue, saturation: saturation, brightness: 0.8)
      }
    }

    /// Initialize with specific colors
    init(columns: Int, rows: Int, colors: [Color], rotationDegrees: Double = 0) {
      self.columns = columns
      self.rows = rows
      self.colors = colors
      self.rotationDegrees = rotationDegrees
    }

    func getColor(atColumn column: Int, row: Int) -> Color {
      guard colors.count > 0 else { return .white }
      guard colors.count > 1 else { return colors[0] }

      // Get interpolation factor with rotation applied
      let t = ColorHelper.rotatedInterpolation(
        column: column,
        row: row,
        columns: columns,
        rows: rows,
        rotationDegrees: rotationDegrees
      )

      // Calculate which segment we're in
      // With N colors, we have N-1 segments
      let segmentCount = colors.count - 1
      let segmentIndex = Int(t * Double(segmentCount))

      // Clamp to valid range
      let clampedSegmentIndex = min(segmentIndex, segmentCount - 1)

      // Calculate position within this segment (0.0 to 1.0)
      let segmentStart = Double(clampedSegmentIndex) / Double(segmentCount)
      let segmentEnd = Double(clampedSegmentIndex + 1) / Double(segmentCount)
      let segmentT = (t - segmentStart) / (segmentEnd - segmentStart)

      // Interpolate between the two colors for this segment
      let color1 = colors[clampedSegmentIndex]
      let color2 = colors[clampedSegmentIndex + 1]

      return ColorHelper.interpolateRGB(from: color1, to: color2, t: segmentT)
    }
  }

  /// Utility for randomly selecting color grid styles
  struct ColorStylePicker {
    /// Randomly selects a ColorGrid style with random parameters
    /// - Parameters:
    ///   - columns: Number of columns in the grid
    ///   - rows: Number of rows in the grid
    /// - Returns: A randomly configured ColorGrid instance
    static func pick(columns: Int = 4, rows: Int = 4) -> ColorGrid {
      let style = Int.random(in: 0...2)
      switch style {
      case 0:
        return BlobColorGrid(
          columns: columns,
          rows: rows,
          blobCount: Int.random(in: 1...2),
          backgroundColor: Color(
            hue: Double.random(in: 0...1),
            saturation: Double.random(in: 0.1...0.3),
            brightness: Double.random(in: 0.5...0.9)
          )
        )
      case 1:
        return BlobColorGrid(
          columns: columns,
          rows: rows,
          blobCount: Int.random(in: 1...2),
          backgroundColor: Color(
            hue: Double.random(in: 0...1),
            saturation: Double.random(in: 0.2...0.5),
            brightness: Double.random(in: 0.1...0.2)
          ),
          saturation: 0.1...0.3,
          brightness: 0.2...0.5
        )
      default:
        return MultiColorGrid(
          columns: columns,
          rows: rows,
          colorCount: Int.random(in: 2...3),
          rotationDegrees: Double.random(in: 0...360)
        )
      }
    }
  }

}
