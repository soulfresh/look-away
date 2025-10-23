import SwiftUI
import box2d

/// Public namespace for the Magnetic Wanderer components/classes
public enum MagneticWanderer {}

extension MagneticWanderer {
  struct ColorGrid {
    let columns: Int
    let rows: Int

    func getColor(atColumn column: Int, row: Int) -> Color {
      // Generate a color based on position
      let hue = Double(column) / Double(columns)
      let saturation = Double(row) / Double(rows)
      return Color(hue: hue, saturation: saturation, brightness: 0.8)
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

      // TODO why do I need to halve this value? I would expect forceDistance
      // to be the radius of the magnetic field already. We are correctly
      // converting forceDistance to screen space before passing it to this
      // view.
      let force = forceDistance / 2.0
      let forceRect = CGRect(
        x: position.x - force,
        y: position.y - force,
        width: force * 2,
        height: force * 2,
      )

      // Magnetic field radius
      context.stroke(
        Path(ellipseIn: forceRect),
        with: .color(.red.opacity(0.3)),
        style: StrokeStyle(lineWidth: 2, dash: [5, 5])
      )
    }
  }

  struct AnimatedMesh: View {
    let columns = 4
    let rows = 4
    @StateObject private var world = PhysicsSimulation()
    @State private var clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
      self.clock = clock
    }

    var body: some View {
      GeometryReader { geometry in
        ZStack {
          if world.ready {
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

              if !world.magnets.isEmpty {
                MagnetView(
                  context: &context,
                  // TODO Update the magnets to return their screen values
                  position: world.coords.toScreen(world.magnets[0].position),
                  radius: world.coords.toScreen(world.magnets[0].radius),
                  forceDistance: world.coords.toScreen(world.magnets[0].maxForceDistance),
                  isBeingDragged: world.isBodyBeingDragged(world.magnets[0].bodyId),
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
}

#Preview {
  HStack {
    MagneticWanderer.AnimatedMesh()
  }
  .padding(20)
}
