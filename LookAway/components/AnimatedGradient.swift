import SwiftUI

struct AnimatedGradient: View {
  @Binding var animateMesh: Bool
  @Binding var animateColors: Bool
  @Binding var showDebugPoints: Bool
  @Binding var baseColor: Color
  @Binding var colorRangeDegrees: Double
  @State private var meshPoints: [UnitPoint] = []
  @State private var meshColors: [Color] = []
  @State private var timer: Timer? = nil
  let rows: Int = 4
  let cols: Int = 4
  let animationDuration: Double = 2.5
  let maxOffset: Double = 0.20
  // Minimum distance in pixels between points
  let minPointDistance: CGFloat = 32
  // Disable cluster for more regular movement
  let cluster = false
  let colorPalette: [Color] = [
    .yellow, .orange, .pink, .purple, .blue, .indigo, .mint, .red,
  ]

  func randomUnitPoint() -> UnitPoint {
    UnitPoint(x: Double.random(in: 0...1), y: Double.random(in: 0...1))
  }

  // Helper to get HSB components from Color (using UIColor for cross-platform)
  func getHSB(_ color: Color) -> (hue: Double, saturation: Double, brightness: Double) {
    #if os(macOS)
      let nsColor = NSColor(color)
      var h: CGFloat = 0
      var s: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      nsColor.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
      return (Double(h), Double(s), Double(b))
    #else
      let uiColor = UIColor(color)
      var h: CGFloat = 0
      var s: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
      return (Double(h), Double(s), Double(b))
    #endif
  }

  func colorFromHSB(hue: Double, saturation: Double, brightness: Double) -> Color {
    #if os(macOS)
      return Color(
        NSColor(
          hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness),
          alpha: 1))
    #else
      return Color(
        UIColor(
          hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness),
          alpha: 1))
    #endif
  }

  func randomColor() -> Color {
    let (h, s, b) = getHSB(baseColor)
    let range = colorRangeDegrees / 360.0
    let minHue = h - range
    let maxHue = h + range
    var hue = Double.random(in: minHue...maxHue)
    // Wrap hue if needed
    if hue < 0 { hue += 1 }
    if hue > 1 { hue -= 1 }
    return colorFromHSB(hue: hue, saturation: s, brightness: b)
  }

  func initialMeshColors() -> [Color] {
    (0..<(rows * cols)).map { _ in randomColor() }
  }

  func initialMeshPoints() -> [UnitPoint] {
    var points: [UnitPoint] = []
    for row in 0..<rows {
      for col in 0..<cols {
        let x = Double(col) / Double(cols - 1)
        let y = Double(row) / Double(rows - 1)
        points.append(UnitPoint(x: x, y: y))
      }
    }
    return points
  }

  func randomizeMeshPoints(viewSize: CGSize) -> [UnitPoint] {
    // First, generate the base grid
    var baseGrid: [[UnitPoint]] = []
    for row in 0..<rows {
      var rowPoints: [UnitPoint] = []
      for col in 0..<cols {
        let x = Double(col) / Double(cols - 1)
        let y = Double(row) / Double(rows - 1)
        rowPoints.append(UnitPoint(x: x, y: y))
      }
      baseGrid.append(rowPoints)
    }
    // Prepare a 2D array for the new points
    var newGrid = baseGrid
    // Helper to check min distance in pixel space
    func isFarEnough(_ candidate: UnitPoint, _ placed: [UnitPoint]) -> Bool {
      let cx = CGFloat(candidate.x) * viewSize.width
      let cy = CGFloat(candidate.y) * viewSize.height
      for pt in placed {
        let px = CGFloat(pt.x) * viewSize.width
        let py = CGFloat(pt.y) * viewSize.height
        let dist = hypot(cx - px, cy - py)
        if dist < minPointDistance { return false }
      }
      return true
    }
    // --- Top edge (row 0, col 1..<cols-1) ---
    for col in 1..<(cols - 1) {
      let prevX = newGrid[0][col - 1].x
      let nextX = baseGrid[0][col + 1].x
      let baseX = baseGrid[0][col].x
      let allowedMinX = max(prevX, baseX - maxOffset)
      let allowedMaxX = min(nextX, baseX + maxOffset)
      var x = baseX
      var attempts = 0
      repeat {
        x = Double.random(in: allowedMinX...allowedMaxX)
        newGrid[0][col] = UnitPoint(x: x, y: 0)
        attempts += 1
      } while !isFarEnough(newGrid[0][col], Array(newGrid.flatMap { $0 }.prefix(0 * cols + col)))
        && attempts < 20
    }
    // --- Bottom edge (row rows-1, col 1..<cols-1) ---
    for col in 1..<(cols - 1) {
      let prevX = newGrid[rows - 1][col - 1].x
      let nextX = baseGrid[rows - 1][col + 1].x
      let baseX = baseGrid[rows - 1][col].x
      let allowedMinX = max(prevX, baseX - maxOffset)
      let allowedMaxX = min(nextX, baseX + maxOffset)
      var x = baseX
      var attempts = 0
      repeat {
        x = Double.random(in: allowedMinX...allowedMaxX)
        newGrid[rows - 1][col] = UnitPoint(x: x, y: 1)
        attempts += 1
      } while !isFarEnough(
        newGrid[rows - 1][col], Array(newGrid.flatMap { $0 }.prefix((rows - 1) * cols + col)))
        && attempts < 20
    }
    // --- Left edge (col 0, row 1..<rows-1) ---
    for row in 1..<(rows - 1) {
      let prevY = newGrid[row - 1][0].y
      let nextY = baseGrid[row + 1][0].y
      let baseY = baseGrid[row][0].y
      let allowedMinY = max(prevY, baseY - maxOffset)
      let allowedMaxY = min(nextY, baseY + maxOffset)
      var y = baseY
      var attempts = 0
      repeat {
        y = Double.random(in: allowedMinY...allowedMaxY)
        newGrid[row][0] = UnitPoint(x: 0, y: y)
        attempts += 1
      } while !isFarEnough(newGrid[row][0], Array(newGrid.flatMap { $0 }.prefix(row * cols)))
        && attempts < 20
    }
    // --- Right edge (col cols-1, row 1..<rows-1) ---
    for row in 1..<(rows - 1) {
      let prevY = newGrid[row - 1][cols - 1].y
      let nextY = baseGrid[row + 1][cols - 1].y
      let baseY = baseGrid[row][cols - 1].y
      let allowedMinY = max(prevY, baseY - maxOffset)
      let allowedMaxY = min(nextY, baseY + maxOffset)
      var y = baseY
      var attempts = 0
      repeat {
        y = Double.random(in: allowedMinY...allowedMaxY)
        newGrid[row][cols - 1] = UnitPoint(x: 1, y: y)
        attempts += 1
      } while !isFarEnough(
        newGrid[row][cols - 1], Array(newGrid.flatMap { $0 }.prefix(row * cols + (cols - 1))))
        && attempts < 20
    }
    // --- Interior points ---
    for row in 1..<(rows - 1) {
      for col in 1..<(cols - 1) {
        let minX = newGrid[row][col - 1].x
        let maxX = newGrid[row][col + 1].x
        let minY = newGrid[row - 1][col].y
        let maxY = newGrid[row + 1][col].y
        let baseX = baseGrid[row][col].x
        let baseY = baseGrid[row][col].y
        let allowedMinX = max(minX, baseX - maxOffset)
        let allowedMaxX = min(maxX, baseX + maxOffset)
        let allowedMinY = max(minY, baseY - maxOffset)
        let allowedMaxY = min(maxY, baseY + maxOffset)
        var x = baseX
        var y = baseY
        var attempts = 0
        repeat {
          x = Double.random(in: allowedMinX...allowedMaxX)
          y = Double.random(in: allowedMinY...allowedMaxY)
          newGrid[row][col] = UnitPoint(x: x, y: y)
          attempts += 1
        } while !isFarEnough(
          newGrid[row][col], Array(newGrid.flatMap { $0 }.prefix(row * cols + col)))
          && attempts < 20
      }
    }
    // Flatten newGrid to row-major order
    return newGrid.flatMap { $0 }
  }
  func unitPointsToSIMD(_ points: [UnitPoint]) -> [SIMD2<Float>] {
    points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
  }
  var body: some View {
    GeometryReader { geo in
      ZStack {
        MeshGradient(
          width: cols,
          height: rows,
          points: unitPointsToSIMD(meshPoints.isEmpty ? initialMeshPoints() : meshPoints),
          colors: meshColors.isEmpty ? initialMeshColors() : meshColors
        )
        // Overlay control points
        if showDebugPoints {
          let points = meshPoints.isEmpty ? initialMeshPoints() : meshPoints
          let colors = meshColors.isEmpty ? initialMeshColors() : meshColors
          ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
            let color = colors[idx]
            DebugCircle(color: color, index: idx, size: 16)
              .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
          }
        }
      }
      .animation(animateMesh ? .easeInOut(duration: animationDuration) : nil, value: meshPoints)
      .animation(animateColors ? .easeInOut(duration: animationDuration) : nil, value: meshColors)
      .ignoresSafeArea()
      .onAppear {
        meshPoints = initialMeshPoints()
        meshColors = initialMeshColors()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: animationDuration, repeats: true) { _ in
          withAnimation(.easeInOut(duration: animationDuration)) {
            if animateMesh {
              meshPoints = randomizeMeshPoints(viewSize: geo.size)
            }
            if animateColors {
              meshColors = initialMeshColors()
            }
          }
        }
      }
      .onDisappear {
        timer?.invalidate()
      }
      .onChange(of: animateMesh) { _ in
        meshPoints = initialMeshPoints()
      }
      .onChange(of: baseColor) { _ in
        meshColors = initialMeshColors()
      }
      .onChange(of: colorRangeDegrees) { _ in
        meshColors = initialMeshColors()
      }
    }
  }
}

struct DebugCircle: View {
  let color: Color
  let index: Int
  let size: CGFloat
  var body: some View {
    ZStack {
      Circle()
        .fill(color)
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.black, lineWidth: 1))
      Text("\(index)")
        .font(.system(size: size * 0.6, weight: .bold))
        .foregroundColor(.black)
    }
  }
}

struct MeshGradientControls: View {
  @Binding var animateMesh: Bool
  @Binding var animateColors: Bool
  @Binding var showDebugPoints: Bool
  @Binding var baseColor: Color
  @Binding var colorRangeDegrees: Double
  var body: some View {
    VStack {
      HStack {
        Toggle("Animate Mesh", isOn: $animateMesh)
          .toggleStyle(.switch)
          .padding(.horizontal)
        Toggle("Animate Colors", isOn: $animateColors)
          .toggleStyle(.switch)
          .padding(.horizontal)
        Toggle("Show Debug Points", isOn: $showDebugPoints)
          .toggleStyle(.switch)
          .padding(.horizontal)
      }
      HStack {
        ColorPicker("Base Color", selection: $baseColor)
          .padding(.horizontal)
        Text("Range: ")
        Slider(value: $colorRangeDegrees, in: 0...180, step: 1) {
          Text("Range")
        }
        .frame(width: 120)
        Text("\(Int(colorRangeDegrees))°")
          .frame(width: 40, alignment: .leading)
      }
      .padding(.bottom, 24)
    }
  }
}

struct AnimatedGradient_Previews: PreviewProvider {
  struct PreviewWrapper: View {
    @State private var animateMesh: Bool = true
    @State private var animateColors: Bool = true
    @State private var showDebugPoints: Bool = true
    @State private var baseColor: Color = .blue
    @State private var colorRangeDegrees: Double = 20

    var body: some View {
      ZStack {
        AnimatedGradient(// AnimatedGradient no longer needs to know about controls
          animateMesh: $animateMesh,
          animateColors: $animateColors,
          showDebugPoints: $showDebugPoints,
          baseColor: $baseColor,
          colorRangeDegrees: $colorRangeDegrees
        )
        VStack {
          Spacer()
          MeshGradientControls(
            animateMesh: $animateMesh,
            animateColors: $animateColors,
            showDebugPoints: $showDebugPoints,
            baseColor: $baseColor,
            colorRangeDegrees: $colorRangeDegrees
          )
        }
        .padding()
      }
    }
  }
  static var previews: some View {
    PreviewWrapper()
      .padding(20)
  }
}
