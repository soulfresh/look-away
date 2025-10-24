import SwiftUI
import box2d

/// Public namespace for the Magnetic Wanderer components/classes
public enum MagneticWanderer {}

extension MagneticWanderer {

  struct AnimatedMesh: View {
    let columns: Int
    let rows: Int
    @StateObject private var world = PhysicsSimulation()
    @State private var clock: any Clock<Duration>
    @Binding var showCanvas: Bool
    let colors: ColorGrid

    // Expose state to parent
    @Binding var magnetIsWandering: Bool

    init(
      colorGrid: ColorGrid? = nil,
      columns: Int = 4,
      rows: Int = 4,
      showCanvas: Binding<Bool> = .constant(false),
      magnetIsWandering: Binding<Bool> = .constant(false),
      clock: any Clock<Duration> = ContinuousClock()
    ) {
      self._showCanvas = showCanvas
      self._magnetIsWandering = magnetIsWandering
      self.clock = clock
      self.colors = colorGrid ?? ColorStylePicker.pick(columns: 4, rows: 4)
      self.columns = columns
      self.rows = rows
    }

    // Helper to generate default grid points when world isn't ready
    private func defaultGridPoints() -> [SIMD2<Float>] {
      var points: [SIMD2<Float>] = []
      for row in 0..<rows {
        for col in 0..<columns {
          let x = Float(col) / Float(columns - 1)
          let y = Float(row) / Float(rows - 1)
          points.append(SIMD2<Float>(x, y))
        }
      }
      return points
    }

    var body: some View {
      GeometryReader { geometry in
        ZStack {

          MeshGradient(
            width: columns,
            height: rows,
            points: world.renderableBodies.isEmpty ? defaultGridPoints() : world.renderableBodies,
            colors: (world.renderableBodies.isEmpty ? defaultGridPoints() : world.renderableBodies)
              .indices.map { index in
                let col = index % columns
                let row = index / columns
                return colors.getColor(atColumn: col, row: row)
              },
          )

          if world.ready && showCanvas {
            Canvas { context, size in
              for wall in world.walls {
                WallView(
                  context: &context,
                  start: world.coords.toScreen(wall.start),
                  end: world.coords.toScreen(wall.end),
                )
              }

              // Render static bodies
              for staticBody in world.immovables {
                StaticBodyView(
                  context: &context,
                  position: world.coords.toScreen(staticBody.position),
                  radius: world.coords.toScreen(staticBody.radius)
                )
              }

              for moveable in world.movables {
                MoveableView(
                  context: &context,
                  position: world.coords.toScreen(moveable.position),
                  radius: world.coords.toScreen(moveable.radius),
                  anchorPoint:
                    world.coords.toScreen(moveable.anchorPosition),
                  isTaut: moveable.isTaut,
                  isBeingDragged: world.isBodyBeingDragged(moveable.bodyId),
                )
              }

              // Render all magnets
              for magnet in world.magnets {
                MagnetView(
                  context: &context,
                  position: world.coords.toScreen(magnet.position),
                  radius: world.coords.toScreen(magnet.radius),
                  forceDistance: world.coords.toScreen(magnet.maxForceDistance),
                  isBeingDragged: world.isBodyBeingDragged(magnet.bodyId)
                )
              }
            }
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  world.onDragMove(to: value.location)
                }
                .onEnded { value in
                  world.onDragEnd()
                }
            )
          }
        }
        .onAppear {
          world.start(
            columns: columns,
            rows: rows,
            screenSize: geometry.size
          )
        }
        .onChange(of: geometry.size) { _, newSize in
          world.onResize(newSize)
        }
        .onChange(of: magnetIsWandering) { _, newValue in
          // Sync external state changes to the world
          if newValue != world.magnetIsWandering {
            world.toggleMagnetActive()
          }
        }
        .onChange(of: world.magnetIsWandering) { _, newValue in
          // Sync world state changes to external binding
          magnetIsWandering = newValue
        }
        .task {
          while !Task.isCancelled {
            world.step()

            do {
              let interval = Duration.milliseconds(Int64(world.timeStep * 1000))
              try await clock.sleep(for: interval)
            } catch {
              print("Clock sleep interrupted: \(error)")
              break
            }
          }
        }
      }
    }
  }

  struct WallView {
    init(
      context: inout GraphicsContext,
      start: CGPoint,
      end: CGPoint,
      lineWidth: CGFloat = 3.0,
    ) {
      var path = Path()
      path.move(to: start)
      path.addLine(to: end)

      context.stroke(
        path,
        with: .color(.white),
        lineWidth: lineWidth
      )
    }
  }

  struct StaticBodyView {
    init(
      context: inout GraphicsContext,
      position: CGPoint,
      radius: CGFloat
    ) {
      let rect = CGRect(
        x: position.x - radius,
        y: position.y - radius,
        width: radius * 2,
        height: radius * 2
      )

      // Fill with gray color to distinguish from moveable bodies
      context.fill(
        Path(ellipseIn: rect),
        with: .color(.gray)
      )

      // White outline
      context.stroke(
        Path(ellipseIn: rect),
        with: .color(.white),
        lineWidth: 1
      )
    }
  }

  struct MoveableView {
    init(
      context: inout GraphicsContext,
      position: CGPoint,
      radius: CGFloat,
      anchorPoint: CGPoint,
      isTaut: Bool,
      isBeingDragged: Bool = false,
    ) {
      let color: Color = isBeingDragged ? .green : .blue
      let bodyPoint = position

      // Draw spring joints
      var path = Path()
      path.move(to: anchorPoint)
      path.addLine(to: bodyPoint)

      // Use different colors for slack vs taut springs
      let springColor: Color = isTaut ? .orange : .blue
      let springOpacity: Double = isTaut ? 0.8 : 0.4

      context.stroke(
        path,
        with: .color(springColor.opacity(springOpacity)),
        lineWidth: 2
      )

      // Draw small circle at anchor point
      let anchorRadius: CGFloat = 3
      let anchorRect = CGRect(
        x: anchorPoint.x - anchorRadius,
        y: anchorPoint.y - anchorRadius,
        width: anchorRadius * 2,
        height: anchorRadius * 2
      )
      context.fill(
        Path(ellipseIn: anchorRect),
        with: .color(springColor)
      )

      let rect = CGRect(
        x: position.x - radius,
        y: position.y - radius,
        width: radius * 2,
        height: radius * 2
      )

      context.fill(
        Path(ellipseIn: rect),
        with: .color(color)
      )

      context.stroke(
        Path(ellipseIn: rect),
        with: .color(.white),
        lineWidth: 1
      )
    }
  }

  struct MagnetView {
    init(
      context: inout GraphicsContext,
      position: CGPoint,
      radius: CGFloat,
      forceDistance: CGFloat,
      isBeingDragged: Bool = false,
    ) {
      let fillColor: Color = isBeingDragged ? .green : .red

      let rect = CGRect(
        x: position.x - radius,
        y: position.y - radius,
        width: radius * 2,
        height: radius * 2
      )

      // Magnet body
      context.fill(
        Path(ellipseIn: rect),
        with: .color(fillColor)
      )

      // Body outline
      context.stroke(
        Path(ellipseIn: rect),
        with: .color(.white),
        lineWidth: 1
      )

      // forceDistance is the radius of the magnetic field (already in screen space)
      let forceRect = CGRect(
        x: position.x - forceDistance,
        y: position.y - forceDistance,
        width: forceDistance * 2,
        height: forceDistance * 2
      )

      // Magnetic field radius
      context.stroke(
        Path(ellipseIn: forceRect),
        with: .color(.red.opacity(0.3)),
        style: StrokeStyle(lineWidth: 2, dash: [5, 5])
      )
    }
  }

  struct Playground: View {
    @State private var showCanvas: Bool = false
    @State private var magnetIsWandering: Bool = false
    @State private var colorGrid: ColorGrid = ColorStylePicker.pick(columns: 4, rows: 4)

    var body: some View {
      VStack {
        AnimatedMesh(
          colorGrid: colorGrid,
          showCanvas: $showCanvas,
          magnetIsWandering: $magnetIsWandering
        )

        // Controls
        HStack {
          Button(action: {
            magnetIsWandering.toggle()
          }) {
            Text(magnetIsWandering ? "Stop Magnet" : "Start Magnet")
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)

          Button(action: {
            showCanvas.toggle()
          }) {
            Text(showCanvas ? "Hide Canvas" : "Show Canvas")
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
      }
    }
  }
}

#Preview {
  HStack {
    MagneticWanderer.Playground()
  }
  .padding(20)
}
