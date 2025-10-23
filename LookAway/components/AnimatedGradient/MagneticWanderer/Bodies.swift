import box2d
import simd

extension MagneticWanderer {
  /// Collision filter categories for Box2D physics
  enum CollisionCategory {
    static let wall: UInt64 = 0x0001  // Walls
    static let edgeBody: UInt64 = 0x0002  // Bodies on edges
    static let interiorBody: UInt64 = 0x0004  // Interior bodies
    static let magnet: UInt64 = 0x0008  // Magnet bodies
    static let staticBody: UInt64 = 0x0010  // Static corner bodies
  }

  /// Base class for all bodies
  ///
  /// Hierarchy:
  /// - Body: Base class and used for corner bodies
  ///   - MovableBody: Base class for movable dynamic bodies
  ///     - Magnet: Wandering magnets
  ///     - SpringBody: Base class for spring-constrained bodies
  ///       - InnerBody: Interior grid bodies with polygon boundary constraints
  ///       - EdgeBody: Bodies constrained to wall edges with prismatic joints
  class Body: CustomStringConvertible {
    let bodyId: b2BodyId
    let radius: Float

    var description: String {
      "Body(r: \(radius), pos: \(position))"
    }

    init(
      world: b2WorldId,
      type: b2BodyType = b2_staticBody,
      position: b2Vec2,
      radius: Float,
      friction: Float = 1.0,
      /// 0 = no bounce, 1 = full bounce
      restitution: Float = 0.2,
    ) {
      self.radius = radius

      // Create static body
      var bodyDef = b2DefaultBodyDef()
      bodyDef.type = type
      bodyDef.position = position

      self.bodyId = b2CreateBody(world, &bodyDef)

      // Add circle shape
      var shapeDef = b2DefaultShapeDef()
      shapeDef.material.friction = friction
      shapeDef.material.restitution = restitution

      // Collision filtering: static bodies collide with walls and all other bodies
      shapeDef.filter.categoryBits = CollisionCategory.staticBody
      shapeDef.filter.maskBits =
        CollisionCategory.wall
        | CollisionCategory.interiorBody
        | CollisionCategory.magnet
        | CollisionCategory.edgeBody

      var circle = b2Circle()
      circle.center = b2Vec2(x: 0, y: 0)
      circle.radius = radius

      b2CreateCircleShape(bodyId, &shapeDef, &circle)
    }

    var position: b2Vec2 {
      b2Body_GetPosition(bodyId)
    }

    /// Update the collision mask bits for this body, specifying which
    /// categories of shapes it should collide with.
    func setShapeFilter(category categoryBits: UInt64, influencing maskBits: UInt64) {
      var shapeId = b2ShapeId()
      let shapeCount = b2Body_GetShapes(self.bodyId, &shapeId, 1)
      if shapeCount > 0 {
        var filter = b2Shape_GetFilter(shapeId)
        filter.categoryBits = categoryBits
        filter.maskBits = maskBits

        b2Shape_SetFilter(shapeId, filter)
      }
    }
  }

  /// Movable dynamic bodies
  class MovableBody: Body {
    let density: Float

    override var description: String {
      "MovableBody(r: \(radius), density: \(density), pos: \(position))"
    }

    init(
      world: b2WorldId,
      position: b2Vec2,
      radius: Float,
      density: Float = 1.0,
      friction: Float = 1.0,
      restitution: Float = 0.2,
    ) {
      self.density = density

      super.init(
        world: world,
        type: b2_dynamicBody,
        position: position,
        radius: radius,
        friction: friction,
        restitution: restitution,
      )

      b2Body_SetLinearDamping(bodyId, 0.8)
    }

    var velocity: b2Vec2 {
      b2Body_GetLinearVelocity(bodyId)
    }

    func setVelocity(_ velocity: b2Vec2) {
      b2Body_SetLinearVelocity(bodyId, velocity)
    }

    func applyForce(_ force: b2Vec2) {
      b2Body_ApplyForceToCenter(bodyId, force, true)
    }

    func applyImpulse(_ impulse: b2Vec2) {
      b2Body_ApplyLinearImpulseToCenter(bodyId, impulse, true)
    }

    func setPosition(_ position: b2Vec2) {
      b2Body_SetTransform(bodyId, position, b2Body_GetRotation(bodyId))
    }
  }

  class SpringBody: MovableBody {
    override var description: String {
      """
      SpringBody(
        r: \(radius)
        density: \(density)
        pos: \(position)
      )
      """
    }

    /// Maximum distance before spring force applies
    let slackLength: Float
    /// Original position for spring anchor
    let anchorPosition: b2Vec2

    init(
      world: b2WorldId,
      position: b2Vec2,
      radius: Float,
      density: Float = 1.0,
      slackLength: Float = 1.0,
    ) {
      self.slackLength = slackLength
      self.anchorPosition = position

      super.init(
        world: world,
        position: position,
        radius: radius,
        density: density,
      )
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

  /// Inner grid body with spring constraint and polygon boundary constraint
  class InnerBody: SpringBody {
    /// Grid position metadata for boundary calculation
    let gridIndex: Int
    let columns: Int
    let rows: Int

    /// Pre-calculated boundary polygon indices (never changes, only positions change)
    private let boundaryIndices: [Int]

    override var description: String {
      """
      InnerBody(
        r: \(radius)
        density: \(density)
        pos: \(position)
        grid: (\(gridIndex % columns), \(gridIndex / columns))
      )
      """
    }

    init(
      world: b2WorldId,
      position: b2Vec2,
      radius: Float,
      density: Float = 1.0,
      slackLength: Float = 1.0,
      gridIndex: Int,
      columns: Int,
      rows: Int
    ) {
      self.gridIndex = gridIndex
      self.columns = columns
      self.rows = rows

      // Pre-calculate boundary polygon indices (topology never changes)
      let col = gridIndex % columns
      let row = gridIndex / columns

      let leftNeighbor = GridPoint(
        column: col - 1,
        row: row,
        index: row * columns + (col - 1)
      )
      let leftDiagonal = GridHelper.diagonalLine(
        through: leftNeighbor,
        columns: columns,
        rows: rows
      )

      let rightNeighbor = GridPoint(
        column: col + 1,
        row: row,
        index: row * columns + (col + 1)
      )
      let rightDiagonal = GridHelper.diagonalLine(
        through: rightNeighbor,
        columns: columns,
        rows: rows
      )

      // Construct the closed polygon: left diagonal (top→bottom) + right diagonal (bottom→top)
      let boundaryGridPoints = leftDiagonal + rightDiagonal.reversed()
      self.boundaryIndices = boundaryGridPoints.map { $0.index }

      super.init(
        world: world,
        position: position,
        radius: radius,
        density: density,
        slackLength: slackLength
      )

      // Set collision filter for interior bodies
      setShapeFilter(
        category: CollisionCategory.interiorBody,
        influencing: CollisionCategory.wall
          | CollisionCategory.interiorBody
          | CollisionCategory.magnet
          | CollisionCategory.edgeBody
          | CollisionCategory.staticBody
      )
    }

    /// Apply boundary constraint force to keep body within its diagonal polygon bounds.
    /// Inner points are constrained to a polygon defined by diagonal bands running through
    /// their left and right neighbors.
    /// - Parameters:
    ///   - allBodies: Array of all grid bodies in row-major order for neighbor lookup
    ///   - timeStep: Physics time step for force calculations
    /// - Returns: true if constraint force was applied, false if body is within bounds
    func applyBoundaryConstraint(allBodies: [Body], timeStep: Float) -> Bool {
      // Constraint parameters
      let softZoneDistance: Float = 0.5  // Start applying force this far from boundary
      let hardLimitDistance: Float = 0.8  // Maximum allowed penetration
      let stiffness: Float = 20.0  // Base force multiplier
      let exponentialFactor: Float = 3.0  // How aggressively force ramps up
      let dampingRatio: Float = 0.7  // Velocity damping near boundary

      // Convert pre-calculated boundary indices to actual positions
      var polygon: [SIMD2<Float>] = []
      for index in boundaryIndices {
        guard index >= 0 && index < allBodies.count else { continue }
        let bodyPos = allBodies[index].position
        polygon.append(SIMD2<Float>(bodyPos.x, bodyPos.y))
      }

      // Need at least 3 points for a valid polygon
      guard polygon.count >= 3 else { return false }

      // Get current position as SIMD2
      let currentPos = position
      let p = SIMD2<Float>(currentPos.x, currentPos.y)

      // Check if point is inside the polygon
      let isInside = GridHelper.isInsidePoly(p, bounds: polygon)

      if isInside {
        // Check if we're in the soft zone (near boundary)
        // Find distance to nearest edge
        let distanceToBoundary = distanceToPolygonBoundary(p, polygon: polygon)

        if distanceToBoundary < softZoneDistance {
          // Apply soft force to slow down approach to boundary
          let penetrationRatio = 1.0 - (distanceToBoundary / softZoneDistance)
          let forceMagnitude = stiffness * pow(penetrationRatio, exponentialFactor)

          // Calculate direction away from nearest boundary point
          let nearestPoint = nearestPointOnPolygon(p, polygon: polygon)
          let direction = normalize(p - nearestPoint)

          // Apply force away from boundary
          let force = b2Vec2(
            x: direction.x * forceMagnitude,
            y: direction.y * forceMagnitude
          )
          applyForce(force)

          // Apply velocity damping
          let currentVelocity = velocity
          let dampedVelocity = b2Vec2(
            x: currentVelocity.x * (1.0 - (1.0 - dampingRatio) * penetrationRatio),
            y: currentVelocity.y * (1.0 - (1.0 - dampingRatio) * penetrationRatio)
          )
          setVelocity(dampedVelocity)

          return true
        }

        return false
      } else {
        // Point is outside - clamp to boundary and apply strong restoring force
        let nearestPoint = GridHelper.clampToPolyBounds(p, bounds: polygon)
        let displacement = p - nearestPoint
        let penetrationDepth = simd_length(displacement)

        // Hard limit check
        if penetrationDepth > hardLimitDistance {
          // Teleport back to hard limit boundary
          let direction = normalize(displacement)
          let clampedPoint = nearestPoint + direction * hardLimitDistance
          setPosition(b2Vec2(x: clampedPoint.x, y: clampedPoint.y))

          // Zero out velocity component pointing away from polygon
          let currentVelocity = velocity
          let velocityVec = SIMD2<Float>(currentVelocity.x, currentVelocity.y)
          let velocityDirection = normalize(velocityVec)

          // If velocity points away from boundary, zero it
          if simd_dot(velocityDirection, direction) > 0 {
            setVelocity(b2Vec2(x: 0, y: 0))
          }
        }

        // Apply exponential restoring force
        let forceMagnitude = stiffness * exp(penetrationDepth * exponentialFactor)
        let direction = normalize(nearestPoint - p)

        let force = b2Vec2(
          x: direction.x * forceMagnitude,
          y: direction.y * forceMagnitude
        )
        applyForce(force)

        // Apply strong velocity damping
        let currentVelocity = velocity
        let dampedVelocity = b2Vec2(
          x: currentVelocity.x * dampingRatio,
          y: currentVelocity.y * dampingRatio
        )
        setVelocity(dampedVelocity)

        return true
      }
    }

    /// Calculate distance from point to nearest edge of polygon
    private func distanceToPolygonBoundary(_ p: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Float {
      var minDistance = Float.greatestFiniteMagnitude
      for i in 0..<polygon.count {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        let closestPoint = GridHelper.projectPointToSegment(p, a: a, b: b)
        let distance = simd_distance(p, closestPoint)
        minDistance = min(minDistance, distance)
      }
      return minDistance
    }

    /// Find nearest point on polygon boundary to given point
    private func nearestPointOnPolygon(_ p: SIMD2<Float>, polygon: [SIMD2<Float>]) -> SIMD2<Float> {
      var minDistance = Float.greatestFiniteMagnitude
      var nearest = polygon[0]
      for i in 0..<polygon.count {
        let a = polygon[i]
        let b = polygon[(i + 1) % polygon.count]
        let closestPoint = GridHelper.projectPointToSegment(p, a: a, b: b)
        let distance = simd_distance(p, closestPoint)
        if distance < minDistance {
          minDistance = distance
          nearest = closestPoint
        }
      }
      return nearest
    }

    /// Normalize a vector, returning zero vector if length is too small
    private func normalize(_ v: SIMD2<Float>) -> SIMD2<Float> {
      let length = simd_length(v)
      guard length > 0.0001 else { return SIMD2<Float>(0, 0) }
      return v / length
    }
  }

  /// Edge body that moves along a wall edge (constrained to one axis) with spring force
  class EdgeBody: SpringBody {
    private var jointId: b2JointId?
    let axis: b2Vec2  // Movement axis (e.g., (1,0) for horizontal, (0,1) for vertical)

    override var description: String {
      """
      EdgeBody(
        r: \(radius)
        density: \(density)
        axis: \(axis)
        pos: \(position)
      )
      """
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
        slackLength: slackLength
      )

      setShapeFilter(
        category: CollisionCategory.edgeBody,
        influencing: CollisionCategory.interiorBody
          | CollisionCategory.magnet
          | CollisionCategory.edgeBody
          | CollisionCategory.staticBody
      )

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
      """
      Magnet(
        r: \(radius)
        density: \(density)
        pos: \(position)
        contacts: \(contacts.count)
        repelling: \(isRepelling)
      )
      """
    }

    init(
      world: b2WorldId,
      position: b2Vec2,
      radius: Float,
      density: Float = 1.0,
      friction: Float = 1.0,
      restitution: Float = 0.2,
      magneticStrength: Float = 0.5,
      maxForceDistance: Float,
      wanderAngle: Float = 0.0
    ) {
      self.magneticStrength = magneticStrength
      self.maxForceDistance = maxForceDistance
      self.wanderAngle = wanderAngle

      super.init(
        world: world,
        position: position,
        radius: radius,
        density: density,
        friction: friction,
        restitution: restitution,
      )

      setShapeFilter(
        category: CollisionCategory.magnet,
        influencing: CollisionCategory.wall
          | CollisionCategory.interiorBody
          | CollisionCategory.edgeBody
          | CollisionCategory.staticBody
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
      // for (index, body) in bodies.enumerated() where !body.isMagnet {
      for (index, body) in bodies.enumerated() {
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
      shapeDef.filter.maskBits =
        CollisionCategory.interiorBody
        | CollisionCategory.magnet
        | CollisionCategory.staticBody

      var segment = b2Segment()
      segment.point1 = start
      segment.point2 = end

      b2CreateSegmentShape(bodyId, &shapeDef, &segment)
    }
  }
}
