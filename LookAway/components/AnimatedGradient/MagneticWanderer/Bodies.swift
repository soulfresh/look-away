import box2d

extension MagneticWanderer {
  /// Collision filter categories for Box2D physics
  enum CollisionCategory {
    static let wall: UInt64 = 0x0001        // Walls
    static let edgeBody: UInt64 = 0x0002    // Bodies on edges
    static let interiorBody: UInt64 = 0x0004 // Interior bodies
    static let magnet: UInt64 = 0x0008      // Magnet bodies
    static let staticBody: UInt64 = 0x0010  // Static corner bodies
  }

  /// Base class for static bodies that don't move
  class Body: CustomStringConvertible {
    let bodyId: b2BodyId
    let radius: Float

    var description: String {
      "Body(radius: \(radius))"
    }

    init(
      world: b2WorldId,
      position: b2Vec2,
      radius: Float,
      friction: Float = 1.0,
      restitution: Float = 0.2
    ) {
      self.radius = radius

      // Create static body
      var bodyDef = b2DefaultBodyDef()
      bodyDef.type = b2_staticBody
      bodyDef.position = position

      self.bodyId = b2CreateBody(world, &bodyDef)

      // Add circle shape
      var shapeDef = b2DefaultShapeDef()
      shapeDef.material.friction = friction
      shapeDef.material.restitution = restitution

      // Collision filtering: static bodies collide with walls and all other bodies
      shapeDef.filter.categoryBits = CollisionCategory.staticBody
      shapeDef.filter.maskBits = CollisionCategory.wall | CollisionCategory.interiorBody | CollisionCategory.magnet | CollisionCategory.edgeBody

      var circle = b2Circle()
      circle.center = b2Vec2(x: 0, y: 0)
      circle.radius = radius

      b2CreateCircleShape(bodyId, &shapeDef, &circle)
    }

    var position: b2Vec2 {
      b2Body_GetPosition(bodyId)
    }
  }

  /// Movable dynamic bodies
  class MovableBody: CustomStringConvertible {
    struct Data {
      // TODO Replace position with position2
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
      Data(
        position: position,
        radius: radius,
        isMagnet: isMagnet
      )
    }

    var description: String {
      "MovableBody(density: \(density), radius: \(radius), isMagnet: \(isMagnet))"
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

      // Collision filtering: set based on whether this is a magnet or interior body
      if isMagnet {
        shapeDef.filter.categoryBits = CollisionCategory.magnet
        shapeDef.filter.maskBits = CollisionCategory.wall | CollisionCategory.interiorBody | CollisionCategory.edgeBody | CollisionCategory.staticBody
      } else {
        shapeDef.filter.categoryBits = CollisionCategory.interiorBody
        shapeDef.filter.maskBits = CollisionCategory.wall | CollisionCategory.interiorBody | CollisionCategory.magnet | CollisionCategory.edgeBody | CollisionCategory.staticBody
      }

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

  class SpringBody: MovableBody {
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

  /// Edge body that moves along a wall edge (constrained to one axis) with spring force
  class EdgeBody: SpringBody {
    private var jointId: b2JointId?
    let axis: b2Vec2  // Movement axis (e.g., (1,0) for horizontal, (0,1) for vertical)

    override var description: String {
      "EdgeBody(density: \(density), radius: \(radius), axis: \(axis), slackLength: \(slackLength))"
    }

    init(
      world: b2WorldId,
      groundBody: b2BodyId,
      position: b2Vec2,
      axis: b2Vec2,
      radius: Float,
      density: Float = 0.3,
      slackLength: Float
    ) {
      self.axis = axis

      // Initialize the spring body first
      super.init(
        world: world,
        position: position,
        radius: radius,
        density: density,
        isMagnet: false,
        slackLength: slackLength
      )

      // Apply collision filtering to edge body - don't collide with walls but do collide with corners
      var shapeId = b2ShapeId()
      let shapeCount = b2Body_GetShapes(self.bodyId, &shapeId, 1)
      if shapeCount > 0 {
        var filter = b2Shape_GetFilter(shapeId)
        filter.categoryBits = CollisionCategory.edgeBody
        filter.maskBits = CollisionCategory.interiorBody | CollisionCategory.magnet | CollisionCategory.edgeBody | CollisionCategory.staticBody
        b2Shape_SetFilter(shapeId, filter)
      }

      // Create prismatic joint to constrain movement to the axis
      var prismaticDef = b2DefaultPrismaticJointDef()
      prismaticDef.bodyIdA = groundBody
      prismaticDef.bodyIdB = self.bodyId
      prismaticDef.localAnchorA = position
      prismaticDef.localAnchorB = b2Vec2(x: 0, y: 0)
      prismaticDef.localAxisA = axis
      prismaticDef.enableMotor = false
      prismaticDef.enableLimit = false

      self.jointId = b2CreatePrismaticJoint(world, &prismaticDef)
    }

    deinit {
      // Clean up the joint when the body is destroyed
      if let jointId = jointId {
        b2DestroyJoint(jointId)
      }
    }
  }

  class Magnet: MovableBody {
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

    func calculateWanderForce(timeStep: Float, worldBounds: b2Vec2) -> b2Vec2 {
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
      let centeringStrength: Float = 10.0
      let edgeBuffer: Float = 2.0

      var centeringForce = b2Vec2(x: 0, y: 0)

      // Calculate distances to walls (0,0 is top-left corner)
      let distToLeftWall = pos.x  // Distance from left wall (x = 0)
      let distToRightWall = worldBounds.x - pos.x  // Distance from right wall
      let distToTopWall = pos.y  // Distance from top wall (y = 0)
      let distToBottomWall = worldBounds.y - pos.y  // Distance from bottom wall

      // Apply centering force if near walls
      if distToLeftWall < edgeBuffer {
        centeringForce.x += (edgeBuffer - distToLeftWall) * centeringStrength
      }
      if distToRightWall < edgeBuffer {
        centeringForce.x -= (edgeBuffer - distToRightWall) * centeringStrength
      }
      if distToTopWall < edgeBuffer {
        centeringForce.y += (edgeBuffer - distToTopWall) * centeringStrength
      }
      if distToBottomWall < edgeBuffer {
        centeringForce.y -= (edgeBuffer - distToBottomWall) * centeringStrength
      }

      // Combine wander and centering forces
      return b2Vec2(
        x: wanderForce.x + centeringForce.x,
        y: wanderForce.y + centeringForce.y
      )
    }

    func updateContacts(bodies: [MovableBody], timeStep: Float) {
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
    func calculateMagneticForce(to body: MovableBody) -> (
      forceOnBody: b2Vec2, forceOnMagnet: b2Vec2
    )? {
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

      // Collision filtering: walls should collide with everything except edge bodies
      shapeDef.filter.categoryBits = CollisionCategory.wall
      shapeDef.filter.maskBits = CollisionCategory.interiorBody | CollisionCategory.magnet | CollisionCategory.staticBody

      var segment = b2Segment()
      segment.point1 = start
      segment.point2 = end

      b2CreateSegmentShape(bodyId, &shapeDef, &segment)
    }

    var summary: Data {
      Data(start: start, end: end)
    }
  }
}
