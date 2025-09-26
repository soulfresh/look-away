import SwiftUI

struct MeshPoint: Identifiable {
  let id = UUID()
  var position: UnitPoint
  var duration: Double
}

struct AnimatedGradient: View {
  @Binding var animateMesh: Bool
  @Binding var animateColors: Bool
  @Binding var showDebugPoints: Bool
  @Binding var baseColor: Color
  @Binding var colorRangeDegrees: Double
  @State private var meshPoints: [MeshPoint] = []
  @State private var meshColors: [Color] = []
  @State private var timers: [UUID: DispatchWorkItem] = [:]
  let rows: Int = 4
  let cols: Int = 3
  let minDuration: Double = 6.0
  let maxDuration: Double = 8.0
  let maxOffset: Double = 0.20
  // Minimum distance in pixels between points
  let minPointDistance: CGFloat = 32

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

  // Helper to create a random duration for a point
  func randomDuration() -> Double {
    Double.random(in: minDuration...maxDuration)
  }

  // Helper to create initial mesh points with random durations
  func initialMeshPoints() -> [MeshPoint] {
    var points: [MeshPoint] = []
    for row in 0..<rows {
      for col in 0..<cols {
        let x = Double(col) / Double(cols - 1)
        let y = Double(row) / Double(rows - 1)
        points.append(MeshPoint(position: UnitPoint(x: x, y: y), duration: randomDuration()))
      }
    }
    return points
  }

  // Helper to convert [MeshPoint] to [SIMD2<Float>]
  func meshPointsToSIMD(_ points: [MeshPoint]) -> [SIMD2<Float>] {
    points.map { SIMD2<Float>(Float($0.position.x), Float($0.position.y)) }
  }

  // Helper to randomize a single mesh point's position
  func randomizeMeshPoint(_ meshPoint: MeshPoint, index: Int, viewSize: CGSize, currentPoints: [MeshPoint]) -> MeshPoint {
    let row = index / cols
    let col = index % cols
    // First, generate the base grid
    let base = UnitPoint(x: Double(col) / Double(cols - 1), y: Double(row) / Double(rows - 1))
    let isTop = row == 0
    let isBottom = row == rows - 1
    let isLeft = col == 0
    let isRight = col == cols - 1
    let isCorner = (isTop || isBottom) && (isLeft || isRight)
    if isCorner {
      return MeshPoint(position: base, duration: randomDuration())
    }
    var minX = base.x, maxX = base.x, minY = base.y, maxY = base.y
    var fixX = false, fixY = false
    if isTop {
      let prevX = currentPoints[safe: index - 1]?.position.x ?? base.x
      let nextX = currentPoints[safe: index + 1]?.position.x ?? base.x
      minX = max(prevX, base.x - maxOffset)
      maxX = min(nextX, base.x + maxOffset)
      minY = 0; maxY = 0; fixY = true
    } else if isBottom {
      let prevX = currentPoints[safe: index - 1]?.position.x ?? base.x
      let nextX = currentPoints[safe: index + 1]?.position.x ?? base.x
      minX = max(prevX, base.x - maxOffset)
      maxX = min(nextX, base.x + maxOffset)
      minY = 1; maxY = 1; fixY = true
    } else if isLeft {
      let prevY = currentPoints[safe: index - cols]?.position.y ?? base.y
      let nextY = currentPoints[safe: index + cols]?.position.y ?? base.y
      minY = max(prevY, base.y - maxOffset)
      maxY = min(nextY, base.y + maxOffset)
      minX = 0; maxX = 0; fixX = true
    } else if isRight {
      let prevY = currentPoints[safe: index - cols]?.position.y ?? base.y
      let nextY = currentPoints[safe: index + cols]?.position.y ?? base.y
      minY = max(prevY, base.y - maxOffset)
      maxY = min(nextY, base.y + maxOffset)
      minX = 1; maxX = 1; fixX = true
    } else {
      let minXNeighbor = currentPoints[safe: index - 1]?.position.x ?? base.x
      let maxXNeighbor = currentPoints[safe: index + 1]?.position.x ?? base.x
      let minYNeighbor = currentPoints[safe: index - cols]?.position.y ?? base.y
      let maxYNeighbor = currentPoints[safe: index + cols]?.position.y ?? base.y
      minX = max(minXNeighbor, base.x - maxOffset)
      maxX = min(maxXNeighbor, base.x + maxOffset)
      minY = max(minYNeighbor, base.y - maxOffset)
      maxY = min(maxYNeighbor, base.y + maxOffset)
    }
    // Use isFarEnough for collision avoidance
    let placed = currentPoints.prefix(index).map { $0.position }
    let newPos = randomizePoint(
      base: base,
      minX: minX, maxX: maxX,
      minY: minY, maxY: maxY,
      placed: placed,
      viewSize: viewSize,
      fixX: fixX, fixY: fixY
    )
    return MeshPoint(position: newPos, duration: randomDuration())
  }

  // Helper to randomize a point with constraints
  private func randomizePoint(
    base: UnitPoint,
    minX: Double, maxX: Double,
    minY: Double, maxY: Double,
    placed: [UnitPoint],
    viewSize: CGSize,
    fixX: Bool = false, fixY: Bool = false
  ) -> UnitPoint {
    var x = base.x
    var y = base.y
    var attempts = 0
    repeat {
      if !fixX { x = Double.random(in: minX...maxX) }
      if !fixY { y = Double.random(in: minY...maxY) }
      let candidate = UnitPoint(x: x, y: y)
      if isFarEnough(candidate, placed, viewSize: viewSize) {
        return candidate
      }
      attempts += 1
    } while attempts < 20
    return UnitPoint(x: x, y: y)
  }

  // Helper to check min distance in pixel space
  private func isFarEnough(_ candidate: UnitPoint, _ placed: [UnitPoint], viewSize: CGSize) -> Bool {
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

  // Helper to schedule per-point animation (unified for mesh and color)
  func scheduleAnimation(for index: Int, geo: GeometryProxy) {
    let meshPoint = meshPoints[index]
    let duration = meshPoint.duration
    let id = meshPoint.id
    let workItem = DispatchWorkItem {
      var newPoint = meshPoint
      var newColor: Color? = nil
      if self.animateMesh {
        newPoint = self.randomizeMeshPoint(meshPoint, index: index, viewSize: geo.size, currentPoints: self.meshPoints)
      } else {
        // Still randomize duration for next cycle
        newPoint.duration = self.randomDuration()
      }
      if self.animateColors {
        newColor = self.randomColor()
      }
      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: duration)) {
          if self.animateMesh {
            self.meshPoints[index] = newPoint
          } else {
            // Only update duration
            self.meshPoints[index].duration = newPoint.duration
          }
          if let color = newColor, self.meshColors.indices.contains(index) {
            self.meshColors[index] = color
          }
        }
        // Reschedule for next animation
        self.scheduleAnimation(for: index, geo: geo)
      }
    }
    timers[id]?.cancel()
    timers[id] = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
  }

  // Helper to start all animations
  func startAllAnimations(geo: GeometryProxy) {
    // Ensure meshColors is always the correct length
    if meshColors.count != meshPoints.count {
      meshColors = initialMeshColors()
    }
    for idx in meshPoints.indices {
      scheduleAnimation(for: idx, geo: geo)
    }
  }

  // Helper to stop all animations
  func stopAllAnimations() {
    for (_, workItem) in timers {
      workItem.cancel()
    }
    timers.removeAll()
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        MeshGradient(
          width: cols,
          height: rows,
          points: meshPointsToSIMD(meshPoints.isEmpty ? initialMeshPoints() : meshPoints),
          colors: meshColors.isEmpty ? initialMeshColors() : meshColors
        )
        .animation(.easeInOut(duration: 1.0), value: meshColors)
        // Overlay control points
        if showDebugPoints {
          let points = meshPoints.isEmpty ? initialMeshPoints() : meshPoints
          let colors = meshColors.isEmpty ? initialMeshColors() : meshColors
          ForEach(Array(points.enumerated()), id: \.offset) { idx, meshPoint in
            let color = colors[idx]
            DebugCircle(color: color, index: idx, size: 16)
              .position(x: meshPoint.position.x * geo.size.width, y: meshPoint.position.y * geo.size.height)
          }
        }
      }
      .ignoresSafeArea()
      .onAppear {
        meshPoints = initialMeshPoints()
        meshColors = initialMeshColors()
        stopAllAnimations()
        if animateMesh || animateColors {
          startAllAnimations(geo: geo)
        }
      }
      .onDisappear {
        stopAllAnimations()
      }
      .onChange(of: animateMesh) { _, _ in
        stopAllAnimations()
        meshPoints = initialMeshPoints()
        meshColors = initialMeshColors()
        if animateMesh || animateColors {
          startAllAnimations(geo: geo)
        }
      }
      .onChange(of: animateColors) { _, _ in
        stopAllAnimations()
        meshPoints = initialMeshPoints()
        meshColors = initialMeshColors()
        if animateMesh || animateColors {
          startAllAnimations(geo: geo)
        }
      }
      .onChange(of: baseColor) { _, _ in
        meshColors = initialMeshColors()
      }
      .onChange(of: colorRangeDegrees) { _, _ in
        meshColors = initialMeshColors()
      }
    }
  }
}

// Helper for safe array access
extension Array {
  subscript(safe index: Int) -> Element? {
    (startIndex..<endIndex).contains(index) ? self[index] : nil
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
    @State private var showDebugPoints: Bool = false
    @State private var baseColor: Color = .blue
    @State private var colorRangeDegrees: Double = 10

    var body: some View {
      VStack {
        AnimatedGradient(// AnimatedGradient no longer needs to know about controls
          animateMesh: $animateMesh,
          animateColors: $animateColors,
          showDebugPoints: $showDebugPoints,
          baseColor: $baseColor,
          colorRangeDegrees: $colorRangeDegrees
        )
        VStack {
          MeshGradientControls(
            animateMesh: $animateMesh,
            animateColors: $animateColors,
            showDebugPoints: $showDebugPoints,
            baseColor: $baseColor,
            colorRangeDegrees: $colorRangeDegrees
          )
        }
      }
    }
  }
  static var previews: some View {
    PreviewWrapper()
      .padding(20)
  }
}
