import SwiftUI

struct MeshPoint: Identifiable {
  let id = UUID()
  var position: UnitPoint
  var color: Color
  var duration: Double
}

/// A `MeshGradient` that animates the positions/colors of points within the mesh.
struct AnimatedGradient: View {
  /// Whether or not the animate the mesh point positions
  @Binding var animateMesh: Bool
  /// Whether or not to animate the mesh point colors
  @Binding var animateColors: Bool
  /// The base color of the gradient. All colors are randomized around this
  /// color on the HSB color wheel.
  @Binding var baseColor: Color
  /// The range in degrees around the base color to randomize colors.
  @Binding var colorRangeDegrees: Double
  
  /// Allows toggling on a debug overlay showing the mesh points
  @Binding var showDebugPoints: Bool

  @State private var meshPoints: [MeshPoint] = []
  @State private var timers: [UUID: DispatchWorkItem] = [:]
  
  let rows: Int = 3
  let cols: Int = 4
  private var minDuration: Double = 1.0 // 6.0
  private var maxDuration: Double = 2.0 //8.0
  /// The maximum distance that points are allowed to move from their starting
  /// position as a percentage of the view size.
  private var maxOffset: Double = 0.95
  /// Minimum distance in pixels between points. This helps ensure that points
  /// don't get too close together which can cause artifacts in the mesh.
  private var minPointDistance: CGFloat = 5
  
  init(
    baseColor: Binding<Color>,
    colorRangeDegrees: Binding<Double> = .constant(10.0),
    /// How fast the points should animate. This sets the minimum duration,
    /// with the maximum being double this value.
    speed: Double = 1.0,
    /// The maximum distance that points are allowed to move from their starting
    /// position as a percentage of the view size.
    maxOffset: Double = 0.20,
    /// Minimum distance in pixels between points. This helps ensure that points
    /// don't get too close together which can cause artifacts in the mesh.
    minPointDistance: CGFloat = 10,
    animateMesh: Binding<Bool> = .constant(true),
    animateColors: Binding<Bool> = .constant(true),
    showDebugPoints: Binding<Bool> = .constant(false)
  ) {
    self._baseColor = baseColor
    self._colorRangeDegrees = colorRangeDegrees
    self._animateMesh = animateMesh
    self._animateColors = animateColors
    self._showDebugPoints = showDebugPoints
    self.minDuration = speed
    self.maxDuration = speed * 2
    self.maxOffset = maxOffset
    self.minPointDistance = minPointDistance
  }

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
        points.append(
          MeshPoint(
            position: UnitPoint(x: x, y: y),
            color: randomColor(),
            duration: randomDuration()
          )
        )
      }
    }
    return points
  }

  // Helper to convert [MeshPoint] to [SIMD2<Float>]
  func meshPointsToSIMD(_ points: [MeshPoint]) -> [SIMD2<Float>] {
    points.map { SIMD2<Float>(Float($0.position.x), Float($0.position.y)) }
  }

  // Helper to randomize a single mesh point's position
  func randomPosition(
    _ meshPoint: MeshPoint,
    index: Int,
    viewSize: CGSize,
    currentPoints: [MeshPoint]
  ) -> UnitPoint {
    let row = index / cols
    let col = index % cols

    // First, generate the base grid
    let base = UnitPoint(x: Double(col) / Double(cols - 1), y: Double(row) / Double(rows - 1))
    let isTop = row == 0
    let isBottom = row == rows - 1
    let isLeft = col == 0
    let isRight = col == cols - 1
    let isCorner = (isTop || isBottom) && (isLeft || isRight)

    // Corners stay fixed
    // TODO We could move these around outside of the view bounds
    if isCorner {
      return base
    }

    var minX = base.x
    var maxX = base.x
    var minY = base.y
    var maxY = base.y
    var fixX = false
    var fixY = false

    // TODO DRY this up
    if isTop {
      let prevX = currentPoints[safe: index - 1]?.position.x ?? base.x
      let nextX = currentPoints[safe: index + 1]?.position.x ?? base.x
      minX = max(prevX, base.x - maxOffset)
      maxX = min(nextX, base.x + maxOffset)
      minY = 0
      maxY = 0
      fixY = true
    } else if isBottom {
      let prevX = currentPoints[safe: index - 1]?.position.x ?? base.x
      let nextX = currentPoints[safe: index + 1]?.position.x ?? base.x
      minX = max(prevX, base.x - maxOffset)
      maxX = min(nextX, base.x + maxOffset)
      minY = 1
      maxY = 1
      fixY = true
    } else if isLeft {
      let prevY = currentPoints[safe: index - cols]?.position.y ?? base.y
      let nextY = currentPoints[safe: index + cols]?.position.y ?? base.y
      minY = max(prevY, base.y - maxOffset)
      maxY = min(nextY, base.y + maxOffset)
      minX = 0
      maxX = 0
      fixX = true
    } else if isRight {
      let prevY = currentPoints[safe: index - cols]?.position.y ?? base.y
      let nextY = currentPoints[safe: index + cols]?.position.y ?? base.y
      minY = max(prevY, base.y - maxOffset)
      maxY = min(nextY, base.y + maxOffset)
      minX = 1
      maxX = 1
      fixX = true
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
    
    return newPos
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
  private func isFarEnough(_ candidate: UnitPoint, _ placed: [UnitPoint], viewSize: CGSize) -> Bool
  {
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
      newPoint.duration = self.randomDuration()

      if self.animateMesh {
        newPoint.position = self.randomPosition(
          meshPoint,
          index: index,
          viewSize: geo.size,
          currentPoints: self.meshPoints
        )
      }

      if self.animateColors {
        newPoint.color = self.randomColor()
      }

      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: duration)) {
          if self.animateMesh || self.animateColors {
            self.meshPoints[index] = newPoint
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
          colors: meshPoints.map { $0.color },
        )
        
        if showDebugPoints {
          ForEach(Array(meshPoints.enumerated()), id: \.offset) { idx, meshPoint in
            DebugCircle(color: meshPoint.color, index: idx, size: 16)
              .position(
                x: meshPoint.position.x * geo.size.width, y: meshPoint.position.y * geo.size.height)
          }
        }
      }
      .ignoresSafeArea()
      .onAppear {
        meshPoints = initialMeshPoints()
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
        if animateMesh || animateColors {
          startAllAnimations(geo: geo)
        }
      }
      .onChange(of: animateColors) { _, _ in
        stopAllAnimations()
        meshPoints = initialMeshPoints()
        if animateMesh || animateColors {
          startAllAnimations(geo: geo)
        }
      }
      .onChange(of: baseColor) { _, _ in
        meshPoints = initialMeshPoints()
      }
      .onChange(of: colorRangeDegrees) { _, _ in
        meshPoints = initialMeshPoints()
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
        AnimatedGradient(
          baseColor: $baseColor,
          colorRangeDegrees: $colorRangeDegrees,
          animateMesh: $animateMesh,
          animateColors: $animateColors,
          showDebugPoints: $showDebugPoints,
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
