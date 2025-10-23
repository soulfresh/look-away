import SwiftUI
import box2d

/// Public namespace for the Magnetic Wanderer components/classes
public enum MagneticWanderer {}

extension MagneticWanderer {

  struct AnimatedMesh: View {
    let columns = 4
    let rows = 4
    @StateObject private var world = PhysicsSimulation()
    @State private var clock: any Clock<Duration>
    @State private var showCanvas: Bool = false
    @State private var colors: ColorGrid

    static func pickColorStyle(columns: Int, rows: Int) -> ColorGrid {
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
            brightness: Double.random(in: 0.5...0.9),
          ),
        )
      case 1:
        return BlobColorGrid(
          columns: columns,
          rows: rows,
          blobCount: Int.random(in: 1...2),
          backgroundColor: Color(
            hue: Double.random(in: 0...1),
            saturation: Double.random(in: 0.2...0.5),
            brightness: Double.random(in: 0.1...0.2),
          ),
          saturation: 0.1...0.3,
          brightness: 0.2...0.5,
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

    init(clock: any Clock<Duration> = ContinuousClock()) {
      self.clock = clock
      self.colors = AnimatedMesh.pickColorStyle(columns: columns, rows: rows)
    }

    func copyColorsToClipboard() {
      #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(colors.colorList, forType: .string)
      #elseif os(iOS)
        UIPasteboard.general.string = colors.description
      #endif
    }

    var body: some View {
      VStack {
        GeometryReader { geometry in
          ZStack {

            MeshGradient(
              width: columns,
              height: rows,
              points: world.renderableBodies,
              colors: world.renderableBodies.indices.map { index in
                // let body = world.renderableBodies[index]
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

        // Controls
        HStack {
          Button(action: {
            world.toggleMagnetActive()
          }) {
            Text(world.magnetIsWandering ? "Stop Magnet" : "Start Magnet")
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

          Button(action: {
            copyColorsToClipboard()
          }) {
            Text("Copy Colors")
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
          }
          .buttonStyle(.borderedProminent)
        }
        .padding()
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
}

#Preview {
  HStack {
    MagneticWanderer.AnimatedMesh()
  }
  .padding(20)
}
