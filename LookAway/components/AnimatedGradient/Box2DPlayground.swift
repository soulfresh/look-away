import SwiftUI
import box2d

struct Box2DPlayground: View {
  @StateObject private var physics = PhysicsWorld()
  private let renderScale: Float = 50.0  // Pixels per physics unit
  @State private var draggedBodyIndex: Int?

  var body: some View {
    GeometryReader { geometry in
      Canvas { context, size in
        let coords = CoordinateSystem(renderScale: renderScale, viewSize: size)

        for wall in physics.walls {
          let start = coords.toScreen(wall.start)
          let end = coords.toScreen(wall.end)

          var path = Path()
          path.move(to: start)
          path.addLine(to: end)

          context.stroke(
            path,
            with: .color(.white),
            lineWidth: 3
          )
        }

        // Draw all bodies in the physics world (scaled)
        for (index, bodyData) in physics.bodies.enumerated() {
          let center = coords.toScreen(bodyData.position)
          let radius = coords.toScreen(bodyData.radius)

          let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
          )

          // Highlight dragged body
          let isBeingDragged = draggedBodyIndex == index
          let fillColor: Color = isBeingDragged ? .green : .blue

          context.fill(
            Path(ellipseIn: rect),
            with: .color(fillColor)
          )

          // Draw outline
          context.stroke(
            Path(ellipseIn: rect),
            with: .color(.white),
            lineWidth: 1
          )
        }
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let coords = CoordinateSystem(renderScale: renderScale, viewSize: geometry.size)
            let physicsPos = coords.toWorld(value.location)

            // On first drag event, find which body (if any) was clicked
            if draggedBodyIndex == nil {
              // TODO Pass the coords to startDragging instead of
              // looking up the body here
              if let index = physics.findBodyAt(physicsPos, coords: coords) {
                draggedBodyIndex = index
                physics.startDragging(index: index, at: physicsPos)
              }
            } else {
              // Update the mouse joint target
              physics.updateDragging(to: physicsPos)
            }
          }
          .onEnded { _ in
            if draggedBodyIndex != nil {
              physics.stopDragging()
              draggedBodyIndex = nil
            }
          }
      )
      .onChange(of: geometry.size) { oldSize, newSize in
        let coords = CoordinateSystem(renderScale: renderScale, viewSize: newSize)
        physics.updateWorldSize(coords)
      }
      .onAppear {
        let coords = CoordinateSystem(renderScale: renderScale, viewSize: geometry.size)
        physics.updateWorldSize(coords)
        physics.start()
      }
      .onDisappear {
        physics.stop()
      }
    }
  }
}

struct CoordinateSystem {
  /// Pixels per physics unit for bodies
  let renderScale: Float
  let viewSize: CGSize

  let worldBounds: b2Vec2

  var centerX: CGFloat { viewSize.width / 2 }
  var centerY: CGFloat { viewSize.height / 2 }

  init(renderScale: Float, viewSize: CGSize) {
    self.renderScale = renderScale
    self.viewSize = viewSize

    self.worldBounds = b2Vec2(
      x: Float(viewSize.width / 2) / renderScale,
      y: Float(viewSize.height / 2) / renderScale
    )
  }

  /// Convert physics position to screen position
  func toScreen(_ physicsPos: b2Vec2) -> CGPoint {
    CGPoint(
      x: centerX + CGFloat(physicsPos.x) * CGFloat(renderScale),
      y: centerY - CGFloat(physicsPos.y) * CGFloat(renderScale)  // Flip Y
    )
  }

  /// Convert physics scalar distance to screen distance (for radius, etc.)
  func toScreen(_ physicsValue: Float) -> CGFloat {
    CGFloat(physicsValue) * CGFloat(renderScale)
  }

  /// Convert screen position to physics position
  func toWorld(_ screenPos: CGPoint) -> b2Vec2 {
    b2Vec2(
      x: Float((screenPos.x - centerX) / CGFloat(renderScale)),
      y: Float((centerY - screenPos.y) / CGFloat(renderScale))  // Flip Y
    )
  }

  func toWorld(_ screenValue: CGFloat) -> Float {
    Float(screenValue) / renderScale
  }
}

class PhysicsBody {
  struct Data {
    let position: b2Vec2
    let radius: Float
  }

  let bodyId: b2BodyId
  let radius: Float

  var summary: Data {
    Data(position: position, radius: radius)
  }

  init(
    world: b2WorldId,
    position: b2Vec2,
    radius: Float,
    density: Float = 1.0,
    friction: Float = 1.0,
    // 0 = no bounce, 1 = full bounce
    restitution: Float = 0.2

  ) {
    self.radius = radius

    // Create dynamic body
    var bodyDef = b2DefaultBodyDef()
    bodyDef.type = b2_dynamicBody
    bodyDef.position = position
    // Air resistance / ground friction
    bodyDef.linearDamping = 0.8

    self.bodyId = b2CreateBody(world, &bodyDef)

    // Add circle shape
    var shapeDef = b2DefaultShapeDef()
    shapeDef.density = density
    shapeDef.material.friction = friction
    shapeDef.material.restitution = restitution

    var circle = b2Circle()
    circle.center = b2Vec2(x: 0, y: 0)
    circle.radius = radius

    b2CreateCircleShape(bodyId, &shapeDef, &circle)
  }

  var position: b2Vec2 {
    b2Body_GetPosition(bodyId)
  }

  var velocity: b2Vec2 {
    b2Body_GetLinearVelocity(bodyId)
  }

  func applyForce(_ force: b2Vec2) {
    b2Body_ApplyForceToCenter(bodyId, force, true)
  }

  func applyImpulse(_ impulse: b2Vec2) {
    b2Body_ApplyLinearImpulseToCenter(bodyId, impulse, true)
  }

  func setVelocity(_ velocity: b2Vec2) {
    b2Body_SetLinearVelocity(bodyId, velocity)
  }

  func setPosition(_ position: b2Vec2) {
    b2Body_SetTransform(bodyId, position, b2Body_GetRotation(bodyId))
  }
}

class PhysicsWall {
  struct Data {
    let start: b2Vec2
    let end: b2Vec2
  }

  let bodyId: b2BodyId
  let start: b2Vec2
  let end: b2Vec2

  init(
    world: b2WorldId,
    start: b2Vec2,
    end: b2Vec2,
    friction: Float = 0.1
  ) {
    self.start = start
    self.end = end

    // Create static body
    var bodyDef = b2DefaultBodyDef()
    bodyDef.type = b2_staticBody
    bodyDef.position = b2Vec2(x: 0, y: 0)

    self.bodyId = b2CreateBody(world, &bodyDef)

    // Create segment shape
    var shapeDef = b2DefaultShapeDef()
    shapeDef.material.friction = friction

    var segment = b2Segment()
    segment.point1 = start
    segment.point2 = end

    b2CreateSegmentShape(bodyId, &shapeDef, &segment)
  }

  var summary: Data {
    Data(start: start, end: end)
  }
}

class PhysicsWorld: ObservableObject {
  private var world: b2WorldId?
  private var groundBody: b2BodyId?
  private var simulationTask: Task<Void, Never>?
  private let timeStep: Float = 1.0 / 60.0  // 60 FPS
  private let subStepCount: Int32 = 4  // More substeps for better constraint solving
  private let clock: any Clock<Duration>

  private var physicsBodies: [PhysicsBody] = []
  private var physicsWalls: [PhysicsWall] = []

  // Pending mouse joint target to apply during next physics step
  private var pendingMouseTarget: b2Vec2?
  private var pendingDestroyMouseJoint = false

  var bodies: [PhysicsBody.Data] {
    physicsBodies.map { $0.summary }
  }

  var walls: [PhysicsWall.Data] {
    physicsWalls.map { $0.summary }
  }

  init(clock: any Clock<Duration> = ContinuousClock()) {
    self.clock = clock
    setupWorld()
  }

  deinit {
    cleanup()
  }

  private func setupWorld() {
    // Create world definition with zero gravity (top-down view)
    var worldDef = b2DefaultWorldDef()
    worldDef.gravity = b2Vec2(x: 0, y: 0)

    // Create the Box2D world
    world = b2CreateWorld(&worldDef)

    // Create a static ground body for mouse joint anchor
    guard let world = world else { return }
    var groundDef = b2DefaultBodyDef()
    groundDef.type = b2_staticBody
    groundDef.position = b2Vec2(x: 0, y: 0)
    groundBody = b2CreateBody(world, &groundDef)
  }

  private func setupBodies(
    _ coords: CoordinateSystem
  ) {
    guard let world = world else { return }

    let worldBounds = coords.worldBounds

    // Create multiple bodies at random positions within the world bounds
    let bodyCount = 5
    let radiusRange: ClosedRange<Float> = 0.25...0.4

    // Add some padding so bodies don't spawn too close to walls
    let padding: Float = 1.0
    let xRange = -(worldBounds.x - padding)...(worldBounds.x - padding)
    let yRange = -(worldBounds.y - padding)...(worldBounds.y - padding)

    for _ in 0..<bodyCount {
      let x = Float.random(in: xRange)
      let y = Float.random(in: yRange)
      let radius = Float.random(in: radiusRange)

      let body = PhysicsBody(
        world: world,
        position: b2Vec2(x: x, y: y),
        radius: radius
      )
      physicsBodies.append(body)
    }
  }

  func updateWalls(_ coords: CoordinateSystem) {
    guard let world = world else { return }

    // Remove existing walls
    for wall in physicsWalls {
      b2DestroyBody(wall.bodyId)
    }
    physicsWalls.removeAll()

    let halfWidth = coords.worldBounds.x
    let halfHeight = coords.worldBounds.y

    // Create four walls (static bodies) in physics coordinates
    let wallDefinitions: [(b2Vec2, b2Vec2)] = [
      // Top wall
      (b2Vec2(x: -halfWidth, y: halfHeight), b2Vec2(x: halfWidth, y: halfHeight)),
      // Bottom wall
      (b2Vec2(x: -halfWidth, y: -halfHeight), b2Vec2(x: halfWidth, y: -halfHeight)),
      // Left wall
      (b2Vec2(x: -halfWidth, y: -halfHeight), b2Vec2(x: -halfWidth, y: halfHeight)),
      // Right wall
      (b2Vec2(x: halfWidth, y: -halfHeight), b2Vec2(x: halfWidth, y: halfHeight)),
    ]

    for (start, end) in wallDefinitions {
      let wall = PhysicsWall(world: world, start: start, end: end)
      physicsWalls.append(wall)
    }
  }

  func start() {
    // Start the physics simulation loop
    simulationTask = Task { [weak self] in
      guard let self = self else { return }

      let interval = Duration.milliseconds(Int64(self.timeStep * 1000))

      while !Task.isCancelled {
        self.step()

        do {
          try await self.clock.sleep(for: interval)
        } catch {
          break
        }
      }
    }
  }

  func stop() {
    simulationTask?.cancel()
    simulationTask = nil
  }

  private func step() {
    guard let world = world else { return }

    // Destroy mouse joint if requested (BEFORE the physics step)
    if pendingDestroyMouseJoint, let joint = mouseJoint {
      b2DestroyJoint(joint)
      mouseJoint = nil
      pendingDestroyMouseJoint = false
      pendingMouseTarget = nil
    }

    // Apply pending mouse joint target BEFORE the physics step
    if let target = pendingMouseTarget, let joint = mouseJoint {
      b2MouseJoint_SetTarget(joint, target)
      pendingMouseTarget = nil
    }

    // Step the physics simulation forward
    b2World_Step(world, timeStep, subStepCount)

    // Notify observers that bodies have updated (must be on main thread)
    Task { @MainActor in
      objectWillChange.send()
    }
  }

  func updateWorldSize(_ coords: CoordinateSystem) {
    updateWalls(coords)

    // Create bodies on first call when we know the world size
    if physicsBodies.isEmpty {
      setupBodies(coords)
    }

    // Notify observers that walls have updated
    objectWillChange.send()
  }

  func findBodyAt(_ position: b2Vec2, coords: CoordinateSystem) -> Int? {
    // Check bodies in reverse order (top to bottom in rendering)
    for (index, body) in physicsBodies.enumerated().reversed() {
      let bodyPos = body.position
      let dx = position.x - bodyPos.x
      let dy = position.y - bodyPos.y
      let distanceSquared = dx * dx + dy * dy
      let radiusSquared = body.radius * body.radius

      if distanceSquared <= radiusSquared {
        return index
      }
    }
    return nil
  }

  private var mouseJoint: b2JointId?

  func startDragging(index: Int, at position: b2Vec2) {
    guard index >= 0 && index < physicsBodies.count else { return }
    guard let world = world, let groundBody = groundBody else { return }

    let body = physicsBodies[index]
    let mass = b2Body_GetMass(body.bodyId)

    // Wake up the body
    b2Body_SetAwake(body.bodyId, true)

    // Create a mouse joint to smoothly drag the body
    var mouseDef = b2DefaultMouseJointDef()
    mouseDef.bodyIdA = groundBody  // Static ground body anchor
    mouseDef.bodyIdB = body.bodyId
    mouseDef.target = position
    mouseDef.hertz = 10.0  // Higher stiffness for more responsive dragging
    mouseDef.dampingRatio = 0.7  // Damping
    mouseDef.maxForce = 10000.0 * mass  // Much higher force

    let joint = b2CreateMouseJoint(world, &mouseDef)
    mouseJoint = joint
  }

  func updateDragging(to position: b2Vec2) {
    // Queue the target to be applied before the next physics step
    // This avoids modifying the world while it's locked during a step
    pendingMouseTarget = position
  }

  func stopDragging() {
    // Queue the joint destruction to happen before the next physics step
    // This avoids destroying the joint while the world is locked
    pendingMouseTarget = nil
    pendingDestroyMouseJoint = true
  }

  private func cleanup() {
    stop()
    if let world = world {
      b2DestroyWorld(world)
    }
    world = nil
  }
}

#Preview {
  Box2DPlayground()
    .frame(width: 400, height: 400)
}
