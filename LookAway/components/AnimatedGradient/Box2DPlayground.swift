import SwiftUI
import box2d

struct Box2DPlayground: View {
  @StateObject private var physics = PhysicsWorld()
  private let renderScale: Float = 50.0  // Pixels per physics unit
  @State private var draggedBodyIndex: Int?
  @State private var magneticStrength: Float = 0.0

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .top) {
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

          // Draw spring joints
          for joint in physics.springJoints {
            let anchorPoint = coords.toScreen(joint.anchor)
            let bodyPoint = coords.toScreen(joint.bodyPos)

            var path = Path()
            path.move(to: anchorPoint)
            path.addLine(to: bodyPoint)

            // Use different colors for slack vs taut springs
            let springColor: Color = joint.isTaut ? .orange : .cyan
            let springOpacity: Double = joint.isTaut ? 0.8 : 0.4

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
          }

          // Draw magnetic force boundary circle
          if let magnetData = physics.magnetData {
            let center = coords.toScreen(magnetData.position)
            let radius = coords.toScreen(magnetData.radius)

            let boundaryRect = CGRect(
              x: center.x - radius,
              y: center.y - radius,
              width: radius * 2,
              height: radius * 2
            )

            context.stroke(
              Path(ellipseIn: boundaryRect),
              with: .color(.red.opacity(0.3)),
              style: StrokeStyle(lineWidth: 2, dash: [5, 5])
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

            // Determine body color: green if dragged, red if magnet, blue otherwise
            let isBeingDragged = draggedBodyIndex == index
            let fillColor: Color = isBeingDragged ? .green : (bodyData.isMagnet ? .red : .blue)

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
        .onChange(of: magneticStrength) { oldValue, newValue in
          physics.magneticStrength = newValue
        }
        .onAppear {
          let coords = CoordinateSystem(renderScale: renderScale, viewSize: geometry.size)
          physics.updateWorldSize(coords)
          physics.start()
        }
        .onDisappear {
          physics.stop()
        }

        // Slider overlay
        VStack {
          HStack {
            Text("Repel")
              .font(.caption)
              .foregroundColor(.white)
            Slider(value: $magneticStrength, in: -8...8, step: 0.1)
              .frame(width: 200)
            Text("Attract")
              .font(.caption)
              .foregroundColor(.white)
          }
          .padding()
          .background(Color.black.opacity(0.5))
          .cornerRadius(8)
          .padding()
          Spacer()
        }
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

class PhysicsBody: CustomStringConvertible {
  struct Data {
    let position: b2Vec2
    let radius: Float
    let isMagnet: Bool
  }

  let bodyId: b2BodyId
  let radius: Float
  let isMagnet: Bool
  let density: Float
  let anchorPosition: b2Vec2  // Original position for spring anchor
  let slackLength: Float  // Maximum distance before spring force applies

  var summary: Data {
    Data(position: position, radius: radius, isMagnet: isMagnet)
  }

  var description: String {
    "PhysicsBody(density: \(density), radius: \(radius), isMagnet: \(isMagnet))"
  }

  init(
    world: b2WorldId,
    position: b2Vec2,
    radius: Float,
    density: Float = 1.0,
    friction: Float = 1.0,
    // 0 = no bounce, 1 = full bounce
    restitution: Float = 0.2,
    isMagnet: Bool = false,
    slackLength: Float = 1.0
  ) {
    self.radius = radius
    self.isMagnet = isMagnet
    self.density = density
    self.anchorPosition = position  // Store original position
    self.slackLength = slackLength

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
  /// Maximum distance for applying magnetic forces
  private var maxForceDistance: Float = 1.0

  // Pending mouse joint target to apply during next physics step
  private var pendingMouseTarget: b2Vec2?
  private var pendingDestroyMouseJoint = false

  // Magnetic force strength (positive = attract, negative = repel)
  var magneticStrength: Float = 0.0

  var bodies: [PhysicsBody.Data] {
    physicsBodies.map { $0.summary }
  }

  var walls: [PhysicsWall.Data] {
    physicsWalls.map { $0.summary }
  }

  var magnetData: (position: b2Vec2, radius: Float)? {
    guard let magnet = physicsBodies.first(where: { $0.isMagnet }) else { return nil }
    return (position: magnet.position, radius: maxForceDistance)
  }

  var springJoints: [(anchor: b2Vec2, bodyPos: b2Vec2, isTaut: Bool)] {
    physicsBodies
      .filter { !$0.isMagnet }
      .map { body in
        let dx = body.position.x - body.anchorPosition.x
        let dy = body.position.y - body.anchorPosition.y
        let length = sqrt(dx * dx + dy * dy)
        let isTaut = length > body.slackLength
        return (anchor: body.anchorPosition, bodyPos: body.position, isTaut: isTaut)
      }
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
    let radius: Float = 0.3

    // Create 4 blue bodies in a grid pattern
    // Divide the world into 3 sections (left, center, right) and (top, center, bottom)
    // Place bodies at the 4 corners of the inner grid
    let gridSpacing = worldBounds.x * 2 / 3  // Divide width into thirds
    let gridSpacingY = worldBounds.y * 2 / 3  // Divide height into thirds

    let gridPositions: [(Float, Float)] = [
      (-gridSpacing / 2, -gridSpacingY / 2),  // Bottom-left
      (gridSpacing / 2, -gridSpacingY / 2),  // Bottom-right
      (-gridSpacing / 2, gridSpacingY / 2),  // Top-left
      (gridSpacing / 2, gridSpacingY / 2),  // Top-right
    ]

    for (i, (x, y)) in gridPositions.enumerated() {
      let anchorPos = b2Vec2(x: x, y: y)

      // Calculate slack length - distance from anchor to nearest wall
      let distToLeftWall = worldBounds.x + anchorPos.x
      let distToRightWall = worldBounds.x - anchorPos.x
      let distToBottomWall = worldBounds.y + anchorPos.y
      let distToTopWall = worldBounds.y - anchorPos.y
      let slackLength = min(distToLeftWall, distToRightWall, distToBottomWall, distToTopWall)

      let body = PhysicsBody(
        world: world,
        position: anchorPos,
        radius: radius,
        density: radius,
        isMagnet: false,
        slackLength: slackLength
      )
      print("Created body[\(i)]: \(body)")
      physicsBodies.append(body)
    }

    // Create magnet in the center
    let magnetBody = PhysicsBody(
      world: world,
      position: b2Vec2(x: 0, y: 0),  // Center of the world
      radius: radius,
      density: radius * 4,  // Higher density for magnet
      isMagnet: true
    )
    print("Created body[4] (magnet): \(magnetBody)")
    physicsBodies.append(magnetBody)
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

    // Apply magnetic forces
    applyMagneticForces()

    // Apply spring constraints (rope-like behavior)
    applySpringConstraints()

    // Step the physics simulation forward
    b2World_Step(world, timeStep, subStepCount)

    // Notify observers that bodies have updated (must be on main thread)
    Task { @MainActor in
      objectWillChange.send()
    }
  }

  private func applyMagneticForces() {
    // Find the magnet body
    guard let magnetBody = physicsBodies.first(where: { $0.isMagnet }) else { return }
    let magnetPos = magnetBody.position

    // Apply attractive force to all non-magnet bodies
    for body in physicsBodies where !body.isMagnet {
      let bodyPos = body.position

      // Calculate direction vector from body to magnet
      let dx = magnetPos.x - bodyPos.x
      let dy = magnetPos.y - bodyPos.y
      let distanceSquared = dx * dx + dy * dy
      let distance = sqrt(distanceSquared)

      // Skip if too close (avoid division by zero and excessive force)
      guard distance > 0.1 else { continue }

      // Skip if beyond maximum effective distance
      guard distance <= maxForceDistance else { continue }

      // Calculate falloff factor (1.0 at center, 0.0 at maxForceDistance)
      // Using smooth falloff: (1 - distance/maxForceDistance)^2
      let normalizedDistance = distance / maxForceDistance
      let falloffFactor = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)

      // Calculate magnetic force with falloff
      // Positive magneticStrength = attract, negative = repel
      let baseForceMagnitude = magneticStrength / distanceSquared
      let forceMagnitude = baseForceMagnitude * falloffFactor

      // Apply force in direction of magnet to the body
      let forceX = (dx / distance) * forceMagnitude
      let forceY = (dy / distance) * forceMagnitude

      body.applyForce(b2Vec2(x: forceX, y: forceY))

      // Apply equal and opposite force to the magnet (Newton's third law)
      magnetBody.applyForce(b2Vec2(x: -forceX, y: -forceY))
    }
  }

  // Here is the code for the user constraint approach from the Box2D examples:
  // static float hertz = 3.0f;
  // static float zeta = 0.7f;
  // static float maxForce = 1000.0f;
  // float omega = 2.0f * B2_PI * hertz;
  // float sigma = 2.0f * zeta + timeStep * omega;
  // float s = timeStep * omega * sigma;
  // float impulseCoefficient = 1.0f / ( 1.0f + s );
  // float massCoefficient = s * impulseCoefficient;
  // float biasCoefficient = omega / sigma;
  //
  // b2Vec2 localAnchors[2] = { { 1.0f, -0.5f }, { 1.0f, 0.5f } };
  // float mass = b2Body_GetMass( m_bodyId );
  // float invMass = mass < 0.0001f ? 0.0f : 1.0f / mass;
  // float inertiaTensor = b2Body_GetRotationalInertia( m_bodyId );
  // float invI = inertiaTensor < 0.0001f ? 0.0f : 1.0f / inertiaTensor;
  //
  // b2Vec2 vB = b2Body_GetLinearVelocity( m_bodyId );
  // float omegaB = b2Body_GetAngularVelocity( m_bodyId );
  // b2Vec2 pB = b2Body_GetWorldCenterOfMass( m_bodyId );
  //
  // for ( int i = 0; i < 2; ++i )
  // {
  // 	b2Vec2 anchorA = { 3.0f, 0.0f };
  // 	b2Vec2 anchorB = b2Body_GetWorldPoint( m_bodyId, localAnchors[i] );
  //
  // 	b2Vec2 deltaAnchor = b2Sub( anchorB, anchorA );
  //
  // 	float slackLength = 1.0f;
  // 	float length = b2Length( deltaAnchor );
  // 	float C = length - slackLength;
  // 	if ( C < 0.0f || length < 0.001f )
  // 	{
  // 		m_context->draw.DrawSegment( anchorA, anchorB, b2_colorLightCyan );
  // 		m_impulses[i] = 0.0f;
  // 		continue;
  // 	}
  //
  // 	m_context->draw.DrawSegment( anchorA, anchorB, b2_colorViolet );
  // 	b2Vec2 axis = b2Normalize( deltaAnchor );
  //
  // 	b2Vec2 rB = b2Sub( anchorB, pB );
  // 	float Jb = b2Cross( rB, axis );
  // 	float K = invMass + Jb * invI * Jb;
  // 	float invK = K < 0.0001f ? 0.0f : 1.0f / K;
  //
  // 	float Cdot = b2Dot( vB, axis ) + Jb * omegaB;
  // 	float impulse = -massCoefficient * invK * ( Cdot + biasCoefficient * C );
  // 	float appliedImpulse = b2ClampFloat( impulse, -maxForce * timeStep, 0.0f );
  //
  // 	vB = b2MulAdd( vB, invMass * appliedImpulse, axis );
  // 	omegaB += appliedImpulse * invI * Jb;
  //
  // 	m_impulses[i] = appliedImpulse;
  // }
  //
  // b2Body_SetLinearVelocity( m_bodyId, vB );
  // b2Body_SetAngularVelocity( m_bodyId, omegaB );

  private func applySpringConstraints() {
    // Spring constraint parameters (from UserConstraint example)
    let hertz: Float = 3.0  // Spring frequency
    let zeta: Float = 0.7  // Damping ratio
    let maxForce: Float = 1000.0
    let omega = 2.0 * Float.pi * hertz
    let sigma = 2.0 * zeta + timeStep * omega
    let s = timeStep * omega * sigma
    let impulseCoefficient = 1.0 / (1.0 + s)
    let massCoefficient = s * impulseCoefficient
    let biasCoefficient = omega / sigma

    for body in physicsBodies where !body.isMagnet {
      let anchorA = body.anchorPosition
      let anchorB = body.position

      // Calculate deltaAnchor (from anchorA to anchorB)
      let deltaAnchor = b2Vec2(x: anchorB.x - anchorA.x, y: anchorB.y - anchorA.y)

      // Calculate length
      let length = sqrt(deltaAnchor.x * deltaAnchor.x + deltaAnchor.y * deltaAnchor.y)

      // Constraint violation (how much over slack length)
      let C = length - body.slackLength

      // If not stretched beyond slack length, no constraint force
      if C < 0.0 || length < 0.001 {
        continue
      }

      // Normalize to get axis
      let axis = b2Vec2(x: deltaAnchor.x / length, y: deltaAnchor.y / length)

      // Get body properties
      let mass = b2Body_GetMass(body.bodyId)
      let invMass = mass < 0.0001 ? 0.0 : 1.0 / mass

      // For a point mass at the center, invI and Jb are both 0, so K = invMass
      let K = invMass
      let invK = K < 0.0001 ? 0.0 : 1.0 / K

      var vB = b2Body_GetLinearVelocity(body.bodyId)

      // Calculate velocity along constraint axis (Cdot)
      let Cdot = vB.x * axis.x + vB.y * axis.y

      // Calculate impulse
      let impulse = -massCoefficient * invK * (Cdot + biasCoefficient * C)

      // Clamp impulse (only allow negative impulse to pull body back)
      let appliedImpulse = max(min(impulse, 0.0), -maxForce * timeStep)

      // Apply impulse: vB = vB + invMass * appliedImpulse * axis
      vB.x += invMass * appliedImpulse * axis.x
      vB.y += invMass * appliedImpulse * axis.y

      b2Body_SetLinearVelocity(body.bodyId, vB)
    }
  }

  func updateWorldSize(_ coords: CoordinateSystem) {
    // Store world bounds for magnetic force calculations
    let worldBounds = coords.worldBounds

    maxForceDistance = sqrt(worldBounds.x * worldBounds.x + worldBounds.y * worldBounds.y) / 2

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
