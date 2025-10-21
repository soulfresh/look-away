import SwiftUI
import box2d

struct Box2DPlayground: View {
  @StateObject private var physics = PhysicsWorld()
  private let renderScale: Float = 50.0  // Pixels per physics unit
  @State private var draggedBodyIndex: Int?
  @State private var isSimulationRunning = true
  @State private var showPhysics = false

  // Generate random colors for the mesh gradient
  private let meshColors: [Color] = {
    (0..<16).map { _ in
      Color(
        red: Double.random(in: 0...1),
        green: Double.random(in: 0...1),
        blue: Double.random(in: 0...1)
      )
    }
  }()

  // Calculate mesh points based on physics body positions
  private func calculateMeshPoints(size: CGSize) -> [SIMD2<Float>] {
    let coords = CoordinateSystem(renderScale: renderScale, viewSize: size)
    let bodies = physics.bodies

    // Convert physics positions to normalized coordinates (0.0 to 1.0)
    func toNormalized(_ physicsPos: b2Vec2) -> SIMD2<Float> {
      let screenPos = coords.toScreen(physicsPos)
      return SIMD2<Float>(
        Float(screenPos.x / size.width),
        Float(screenPos.y / size.height)
      )
    }

    // Fixed edge points
    let p00 = SIMD2<Float>(0.0, 0.0)
    let p10 = SIMD2<Float>(0.33, 0.0)
    let p20 = SIMD2<Float>(0.67, 0.0)
    let p30 = SIMD2<Float>(1.0, 0.0)

    let p03 = SIMD2<Float>(0.0, 1.0)
    let p13 = SIMD2<Float>(0.33, 1.0)
    let p23 = SIMD2<Float>(0.67, 1.0)
    let p33 = SIMD2<Float>(1.0, 1.0)

    // Edge middle points
    let p01 = SIMD2<Float>(0.0, 0.33)
    let p02 = SIMD2<Float>(0.0, 0.67)
    let p31 = SIMD2<Float>(1.0, 0.33)
    let p32 = SIMD2<Float>(1.0, 0.67)

    // Interior points controlled by physics bodies
    // Only use the 4 SpringBodies (not the magnet) to control the 2x2 interior grid
    let p11: SIMD2<Float>
    let p21: SIMD2<Float>
    let p12: SIMD2<Float>
    let p22: SIMD2<Float>

    if bodies.count >= 4 {
      // Bodies 0-3 are SpringBodies in grid positions
      // Body 4 (the Magnet) is not used for mesh control - it only influences the other bodies
      p11 = toNormalized(bodies[2].position)
      p21 = toNormalized(bodies[3].position)
      p12 = toNormalized(bodies[0].position)
      p22 = toNormalized(bodies[1].position)
    } else {
      // Fallback to default positions
      p11 = SIMD2<Float>(0.33, 0.33)
      p21 = SIMD2<Float>(0.67, 0.33)
      p12 = SIMD2<Float>(0.33, 0.67)
      p22 = SIMD2<Float>(0.67, 0.67)
    }

    // Return all 16 points in row-major order
    return [
      // Row 0 (top)
      p00, p10, p20, p30,
      // Row 1
      p01, p11, p21, p31,
      // Row 2
      p02, p12, p22, p32,
      // Row 3 (bottom)
      p03, p13, p23, p33,
    ]
  }

  var body: some View {
    GeometryReader { geometry in
      let meshPoints = calculateMeshPoints(size: geometry.size)

      ZStack(alignment: .top) {
        // Background MeshGradient
        MeshGradient(
          width: 4,
          height: 4,
          points: meshPoints,
          colors: meshColors
        )

        if showPhysics {
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
        }

        // Control button overlay
        VStack {
          HStack {
            Button(action: {
              if isSimulationRunning {
                physics.stop()
              } else {
                physics.start()
              }
              isSimulationRunning.toggle()
            }) {
              Text(isSimulationRunning ? "Stop" : "Start")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }

            Button(action: {
              showPhysics.toggle()
            }) {
              Text(showPhysics ? "Hide Physics" : "Show Physics")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }

            Spacer()
          }
          .padding()
          Spacer()
        }
      }
      .onChange(of: geometry.size) { oldSize, newSize in
        let coords = CoordinateSystem(renderScale: renderScale, viewSize: newSize)
        physics.updateWorldSize(coords)
      }
      .onAppear {
        let coords = CoordinateSystem(renderScale: renderScale, viewSize: geometry.size)
        physics.updateWorldSize(coords)
        if isSimulationRunning {
          physics.start()
        }
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

class SpringBody: PhysicsBody {
  override var description: String {
    "SpringBody(density: \(density), radius: \(radius), slackLength: \(slackLength))"
  }

  /// Calculate and apply spring constraint to keep body within slack length of anchor
  /// Returns true if constraint was applied, false if body is within slack length
  func applySpringConstraint(timeStep: Float) -> Bool {
    // Spring constraint parameters (from UserConstraint example)
    let hertz: Float = 1.0  // Spring frequency
    let zeta: Float = 0.3  // Damping ratio
    let maxForce: Float = 1000.0
    let omega = 2.0 * Float.pi * hertz
    let sigma = 2.0 * zeta + timeStep * omega
    let s = timeStep * omega * sigma
    let impulseCoefficient = 1.0 / (1.0 + s)
    let massCoefficient = s * impulseCoefficient
    let biasCoefficient = omega / sigma

    let anchorA = anchorPosition
    let anchorB = position

    // Calculate deltaAnchor (from anchorA to anchorB)
    let deltaAnchor = b2Vec2(x: anchorB.x - anchorA.x, y: anchorB.y - anchorA.y)

    // Calculate length
    let length = sqrt(deltaAnchor.x * deltaAnchor.x + deltaAnchor.y * deltaAnchor.y)

    // Constraint violation (how much over slack length)
    let C = length - slackLength

    // If not stretched beyond slack length, no constraint force
    if C < 0.0 || length < 0.001 {
      return false
    }

    // Normalize to get axis
    let axis = b2Vec2(x: deltaAnchor.x / length, y: deltaAnchor.y / length)

    // Get body properties
    let mass = b2Body_GetMass(bodyId)
    let invMass = mass < 0.0001 ? 0.0 : 1.0 / mass

    // For a point mass at the center, invI and Jb are both 0, so K = invMass
    let K = invMass
    let invK = K < 0.0001 ? 0.0 : 1.0 / K

    var vB = b2Body_GetLinearVelocity(bodyId)

    // Calculate velocity along constraint axis (Cdot)
    let Cdot = vB.x * axis.x + vB.y * axis.y

    // Calculate impulse
    let impulse = -massCoefficient * invK * (Cdot + biasCoefficient * C)

    // Clamp impulse (only allow negative impulse to pull body back)
    let appliedImpulse = max(min(impulse, 0.0), -maxForce * timeStep)

    // Apply impulse: vB = vB + invMass * appliedImpulse * axis
    vB.x += invMass * appliedImpulse * axis.x
    vB.y += invMass * appliedImpulse * axis.y

    b2Body_SetLinearVelocity(bodyId, vB)

    return true
  }

  /// Check if spring is currently taut (stretched beyond slack length)
  var isTaut: Bool {
    let dx = position.x - anchorPosition.x
    let dy = position.y - anchorPosition.y
    let length = sqrt(dx * dx + dy * dy)
    return length > slackLength
  }
}

class Magnet: PhysicsBody {
  private var wanderAngle: Float = 0.0
  private var contacts: [Int: Float] = [:]
  // Global repulsion state - applies to all bodies when active
  private var repulsionTimeRemaining: Float = 0.0

  // Magnetic force strength (positive = attract, negative = repel)
  private let magneticStrength: Float
  // Maximum distance for applying magnetic forces
  let maxForceDistance: Float

  // Movement control
  var isMoving: Bool = true

  // Constants for repulsion behavior
  private let contactThreshold: Float = 2.0  // Trigger repulsion after 2s of contact
  private let repulsionDuration: Float = 2.0  // Repel for 2 seconds

  /// Check if magnet is currently in repulsion mode
  var isRepelling: Bool {
    repulsionTimeRemaining > 0
  }

  override var description: String {
    "Magnet(density: \(density), radius: \(radius), strength: \(magneticStrength), contacts: \(contacts.count), repelling: \(isRepelling))"
  }

  init(
    world: b2WorldId,
    position: b2Vec2,
    radius: Float,
    density: Float = 1.0,
    friction: Float = 1.0,
    restitution: Float = 0.2,
    isMagnet: Bool = true,
    magneticStrength: Float = 0.5,
    maxForceDistance: Float
  ) {
    self.magneticStrength = magneticStrength
    self.maxForceDistance = maxForceDistance
    super.init(
      world: world,
      position: position,
      radius: radius,
      density: density,
      friction: friction,
      restitution: restitution,
      isMagnet: isMagnet,
      slackLength: 0  // Magnet doesn't need slack length
    )
  }

  func calculateWanderForce(timeStep: Float) -> b2Vec2 {
    // If not moving, return zero force
    guard isMoving else {
      return b2Vec2(x: 0, y: 0)
    }

    // Wander behavior parameters
    let wanderStrength: Float = 2.0
    let wanderRate: Float = 10.0

    // Randomly adjust wander angle each frame
    let angleChange = Float.random(in: -wanderRate...wanderRate) * timeStep
    wanderAngle += angleChange

    // Calculate wander force in the current wander direction
    let wanderForce = b2Vec2(
      x: cos(wanderAngle) * wanderStrength,
      y: sin(wanderAngle) * wanderStrength
    )

    // Add centering force to keep magnet away from walls
    let pos = position
    let centeringStrength: Float = 3.0
    let edgeBuffer: Float = 1.0

    var centeringForce = b2Vec2(x: 0, y: 0)

    // Calculate distances to walls
    let distToLeftWall = maxForceDistance + pos.x
    let distToRightWall = maxForceDistance - pos.x
    let distToBottomWall = maxForceDistance + pos.y
    let distToTopWall = maxForceDistance - pos.y

    // Apply centering force if near walls
    if distToLeftWall < edgeBuffer {
      centeringForce.x += (edgeBuffer - distToLeftWall) * centeringStrength
    }
    if distToRightWall < edgeBuffer {
      centeringForce.x -= (edgeBuffer - distToRightWall) * centeringStrength
    }
    if distToBottomWall < edgeBuffer {
      centeringForce.y += (edgeBuffer - distToBottomWall) * centeringStrength
    }
    if distToTopWall < edgeBuffer {
      centeringForce.y -= (edgeBuffer - distToTopWall) * centeringStrength
    }

    // Combine wander and centering forces
    return b2Vec2(
      x: wanderForce.x + centeringForce.x,
      y: wanderForce.y + centeringForce.y
    )
  }

  func updateContacts(bodies: [PhysicsBody], timeStep: Float) {
    let magnetPos = position
    let magnetRadius = radius

    var currentContacts = Set<Int>()
    var anyContactExceedsThreshold = false

    // Check each non-magnet body for collision
    for (index, body) in bodies.enumerated() where !body.isMagnet {
      let bodyPos = body.position
      let bodyRadius = body.radius

      // Calculate distance between centers
      let dx = magnetPos.x - bodyPos.x
      let dy = magnetPos.y - bodyPos.y
      let distance = sqrt(dx * dx + dy * dy)

      // Check if bodies are touching
      if distance < (magnetRadius + bodyRadius) {
        currentContacts.insert(index)

        // Update contact duration
        let newDuration: Float
        if let existingDuration = contacts[index] {
          newDuration = existingDuration + timeStep
          contacts[index] = newDuration
        } else {
          newDuration = timeStep
          contacts[index] = newDuration
        }

        // Check if any contact exceeds threshold
        if newDuration >= contactThreshold {
          anyContactExceedsThreshold = true
        }
      }
    }

    // Remove contacts that are no longer touching
    contacts = contacts.filter { currentContacts.contains($0.key) }

    // Trigger global repulsion if any contact exceeds threshold and not already repelling
    if anyContactExceedsThreshold && !isRepelling {
      repulsionTimeRemaining = repulsionDuration
    }

    // Decrement repulsion timer if active
    if repulsionTimeRemaining > 0 {
      repulsionTimeRemaining -= timeStep
      if repulsionTimeRemaining < 0 {
        repulsionTimeRemaining = 0
      }
    }
  }

  func getContactInfo() -> (count: Int, totalDuration: Float) {
    let count = contacts.count
    let totalDuration = contacts.values.reduce(0, +)
    return (count: count, totalDuration: totalDuration)
  }

  /// Calculate magnetic force between this magnet and another body
  /// Returns a tuple of (forceOnBody, forceOnMagnet) following Newton's third law
  func calculateMagneticForce(to body: PhysicsBody) -> (forceOnBody: b2Vec2, forceOnMagnet: b2Vec2)?
  {
    let magnetPos = position
    let bodyPos = body.position

    // Calculate direction vector from body to magnet
    let dx = magnetPos.x - bodyPos.x
    let dy = magnetPos.y - bodyPos.y
    let distanceSquared = dx * dx + dy * dy
    let distance = sqrt(distanceSquared)

    // Skip if too close (avoid division by zero and excessive force)
    guard distance > 0.1 else { return nil }

    // Skip if beyond maximum effective distance
    guard distance <= maxForceDistance else { return nil }

    // Calculate falloff factor (1.0 at center, 0.0 at maxForceDistance)
    // Using smooth falloff: (1 - distance/maxForceDistance)^2
    let normalizedDistance = distance / maxForceDistance
    let falloffFactor = (1.0 - normalizedDistance) * (1.0 - normalizedDistance)

    // If in repulsion mode, invert the strength to push all bodies away
    let effectiveStrength = isRepelling ? -abs(magneticStrength) : magneticStrength

    // Calculate magnetic force with falloff
    // Positive strength = attract, negative = repel
    let baseForceMagnitude = effectiveStrength / distanceSquared
    let forceMagnitude = baseForceMagnitude * falloffFactor

    // Apply force in direction of magnet to the body
    let forceX = (dx / distance) * forceMagnitude
    let forceY = (dy / distance) * forceMagnitude

    let forceOnBody = b2Vec2(x: forceX, y: forceY)
    // Newton's third law - equal and opposite force on magnet
    let forceOnMagnet = b2Vec2(x: -forceX, y: -forceY)

    return (forceOnBody: forceOnBody, forceOnMagnet: forceOnMagnet)
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

  var bodies: [PhysicsBody.Data] {
    physicsBodies.map { $0.summary }
  }

  var walls: [PhysicsWall.Data] {
    physicsWalls.map { $0.summary }
  }

  var magnetData: (position: b2Vec2, radius: Float)? {
    guard let magnet = physicsBodies.first(where: { $0.isMagnet }) as? Magnet else { return nil }
    return (position: magnet.position, radius: magnet.maxForceDistance)
  }

  var springJoints: [(anchor: b2Vec2, bodyPos: b2Vec2, isTaut: Bool)] {
    physicsBodies
      .compactMap { $0 as? SpringBody }
      .map { springBody in
        return (
          anchor: springBody.anchorPosition, bodyPos: springBody.position, isTaut: springBody.isTaut
        )
      }
  }

  var magnetContactInfo: (count: Int, totalDuration: Float) {
    guard let magnet = physicsBodies.first(where: { $0.isMagnet }) as? Magnet else {
      return (count: 0, totalDuration: 0)
    }
    return magnet.getContactInfo()
  }

  var isMagnetMoving: Bool {
    guard let magnet = physicsBodies.first(where: { $0.isMagnet }) as? Magnet else {
      return false
    }
    return magnet.isMoving
  }

  func toggleMagnetMovement() {
    guard let magnet = physicsBodies.first(where: { $0.isMagnet }) as? Magnet else { return }
    magnet.isMoving.toggle()
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

      let body = SpringBody(
        world: world,
        position: anchorPos,
        radius: radius,
        density: radius,
        isMagnet: false,
        slackLength: slackLength
      )
      physicsBodies.append(body)
    }

    // Create magnet in the center
    let magnetBody = Magnet(
      world: world,
      position: b2Vec2(x: 0, y: 0),  // Center of the world
      radius: radius,
      density: radius * 4,  // Higher density for magnet
      isMagnet: true,
      magneticStrength: 0.5,  // Attractive force
      maxForceDistance: maxForceDistance
    )
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
    print("PhysicsWorld: Starting simulation")
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

    // Update magnet contact tracking and apply wander force
    if let magnet = physicsBodies.first(where: { $0.isMagnet }) as? Magnet {
      magnet.updateContacts(bodies: physicsBodies, timeStep: timeStep)
      let wanderForce = magnet.calculateWanderForce(timeStep: timeStep)
      magnet.applyForce(wanderForce)
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
    guard let magnet = physicsBodies.first(where: { $0.isMagnet }) as? Magnet else { return }

    // Apply magnetic force to all non-magnet bodies
    for body in physicsBodies where !body.isMagnet {
      if let forces = magnet.calculateMagneticForce(to: body) {
        body.applyForce(forces.forceOnBody)
        magnet.applyForce(forces.forceOnMagnet)
      }
    }
  }

  private func applySpringConstraints() {
    // Apply spring constraints to all spring bodies
    for body in physicsBodies {
      if let springBody = body as? SpringBody {
        springBody.applySpringConstraint(timeStep: timeStep)
      }
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
