import SwiftUI
import box2d

extension b2BodyId: Equatable {
  public static func == (lhs: b2BodyId, rhs: b2BodyId) -> Bool {
    return lhs.index1 == rhs.index1 && lhs.world0 == rhs.world0 && lhs.generation == rhs.generation
  }
}

extension MagneticWanderer {
  struct CoordinateSystem {
    /// Pixels per physics unit for bodies
    let renderScale: Float
    let viewSize: CGSize

    let worldHalfBounds: b2Vec2
    var worldBounds: b2Vec2 {
      b2Vec2(x: worldHalfBounds.x * 2, y: worldHalfBounds.y * 2)
    }

    var centerX: CGFloat { viewSize.width / 2 }
    var centerY: CGFloat { viewSize.height / 2 }

    init(renderScale: Float, viewSize: CGSize) {
      self.renderScale = renderScale
      self.viewSize = viewSize

      self.worldHalfBounds = b2Vec2(
        x: Float(viewSize.width / 2) / renderScale,
        y: Float(viewSize.height / 2) / renderScale
      )
    }

    /// Convert physics scalar distance to screen distance (for radius, etc.)
    func toScreen(_ physicsValue: Float) -> CGFloat {
      CGFloat(physicsValue) * CGFloat(renderScale)
    }

    /// Convert physics position to screen position
    func toScreen(_ worldPos: b2Vec2) -> CGPoint {
      CGPoint(
        x: CGFloat(worldPos.x) * CGFloat(renderScale),
        y: CGFloat(worldPos.y) * CGFloat(renderScale)
      )
    }

    /// Convert screen position to physics position
    func toWorld(_ screenPos: CGPoint) -> b2Vec2 {
      b2Vec2(
        x: Float((screenPos.x) / CGFloat(renderScale)),
        y: Float((screenPos.y) / CGFloat(renderScale))
      )
    }

    /// Convert screen scalar distance to physics distance
    func toWorld(_ screenValue: CGFloat) -> Float {
      Float(screenValue) / renderScale
    }

    /// Convert a percentage-based position (0.0 - 1.0) to world position
    func toWorld(asPercent: CGPoint) -> b2Vec2 {
      b2Vec2(
        x: Float(asPercent.x) * worldBounds.x,
        y: Float(asPercent.y) * worldBounds.y
      )
    }
  }

  class PhysicsSimulation: ObservableObject {
    private let magnetRadius: Float = 0.3
    private var magnetForceDistance: Float = 1.0
    private var magnetStrength: Float = 0.5

    private(set) var ready: Bool = false

    let timeStep: Float = 1.0 / 60.0  // 60 FPS
    /// More substeps for better constraint solving
    private let subStepCount: Int32 = 4
    // The world dimensions are based on a fixed width. This ensures that we scale the
    // physics boundaries so bodies don't need to move long distances on larger screens.
    let worldWidthInMeters = 20

    private(set) var coords = CoordinateSystem(
      renderScale: 1.0,
      viewSize: CGSize(width: 1, height: 1)
    )
    private var world: b2WorldId
    private var groundBody: b2BodyId  // Static ground body for joints

    private(set) var immovables: [Body] = []
    private(set) var movables: [SpringBody] = []
    private(set) var walls: [PhysicsWall] = []
    private(set) var magnets: [Magnet] = []

    /// The list of all draggable bodies in the world (excludes immovables).
    var draggableBodies: [MovableBody] {
      return movables + magnets
    }

    /// Used to synchronize drag events with physics world locking.
    /// The box2d world locks itself during the step function and throws if
    /// updates are made during that time. However, SwiftUI drag events can
    /// arrive at any time, so we need to retain the updates and only apply them
    /// before we process the next step.
    private var dragState: DragJoint

    init() {
      // Create the world
      var worldDef = b2DefaultWorldDef()
      worldDef.gravity = b2Vec2(x: 0, y: 0)

      // Create the Box2D world
      self.world = b2CreateWorld(&worldDef)

      // Create a static ground body for joints
      var groundDef = b2DefaultBodyDef()
      groundDef.type = b2_staticBody
      groundDef.position = b2Vec2(x: 0, y: 0)
      self.groundBody = b2CreateBody(world, &groundDef)

      // Create our drag handler
      self.dragState = DragJoint(world: self.world)
    }

    func start(columns: Int, rows: Int, screenSize: CGSize) {
      // Updates our coordinate system and creates the world boundaries.
      onResize(screenSize)

      // let colors = ColorGrid(columns: columns, rows: rows)
      // Calculate slack length in world/physics space
      let slackLength = coords.worldBounds.x / Float(columns)

      // Create bodies for the grid.
      // - Corner bodies will be static.
      // - Edge bodies (non-corner but on edge) will be constrained to move along the edge.
      // - Interior bodies will be dynamic with springs.
      for col in 0..<columns {
        for row in 0..<rows {
          let cols = GridHelper.identity(columns)
          let rowsCount = GridHelper.identity(rows)
          let x = cols == 1 ? 0.5 : CGFloat(col) / CGFloat(cols - 1)
          let y = rowsCount == 1 ? 0.5 : CGFloat(row) / CGFloat(rowsCount - 1)

          let position = coords.toWorld(asPercent: CGPoint(x: x, y: y))

          // Determine body type based on position
          let type = GridHelper.edgeType(
            column: col,
            row: row,
            columns: columns,
            rows: rows
          )

          switch type {
          case .corner:
            // Create static body for corners
            immovables.append(
              Body(
                world: world,
                position: position,
                radius: 0.3
              )
            )
          case .top, .bottom:
            movables.append(
              EdgeBody(
                world: world,
                groundBody: groundBody,
                position: position,
                // Top or bottom edge: can move horizontally
                axis: b2Vec2(x: 1, y: 0),
                radius: 0.3,
                density: 0.3,
                slackLength: slackLength
              )
            )
          case .left, .right:
            movables.append(
              EdgeBody(
                world: world,
                groundBody: groundBody,
                position: position,
                // Left or right edge: can move vertically
                axis: b2Vec2(x: 0, y: 1),
                radius: 0.3,
                density: 0.3,
                slackLength: slackLength
              )
            )
          case .inner:
            // Create dynamic spring body for interior positions
            movables.append(
              SpringBody(
                world: world,
                position: position,
                radius: 0.3,
                density: 0.3,
                isMagnet: false,
                slackLength: slackLength
              )
            )
          }
        }
      }

      // Create our magnets.
      let worldBounds = coords.worldHalfBounds
      // self.magnetForceDistance = 20
      self.magnetForceDistance =
        sqrt(worldBounds.x * worldBounds.x + worldBounds.y * worldBounds.y)

      let magnetBody = Magnet(
        world: world,
        position: b2Vec2(
          x: coords.worldBounds.x * 0.5,
          y: coords.worldBounds.y * 0.5
        ),
        radius: magnetRadius,
        density: magnetRadius * 4,
        isMagnet: true,
        magneticStrength: magnetStrength,
        maxForceDistance: magnetForceDistance
      )
      magnets.append(magnetBody)

      ready = true
    }

    deinit {
      cleanup()
    }

    // This version must be manually stepped. The timer will be handled by the
    // view.
    func step() {
      guard ready else { return }

      // Apply any pending drag updates
      dragState.apply()

      guard let magnet = magnets.getElement(at: 0) else { return }

      // Update the magnet's wander behavior
      magnet.updateContacts(bodies: movables, timeStep: timeStep)
      let wanderForce = magnet.calculateWanderForce(
        timeStep: timeStep, worldBounds: coords.worldBounds)
      magnet.applyForce(wanderForce)

      for body in movables {
        if let forces = magnet.calculateMagneticForce(to: body) {
          body.applyForce(forces.forceOnBody)
          magnet.applyForce(forces.forceOnMagnet)
        }

        body.applySpringConstraint(timeStep: timeStep)
      }

      // Step the physics simulation forward
      b2World_Step(world, timeStep, subStepCount)

      // Notify observers that bodies have updated (must be on main thread)
      Task { @MainActor in
        objectWillChange.send()
      }
    }

    func findBodyAt(_ position: b2Vec2, coords: CoordinateSystem) -> MovableBody? {
      // Check bodies in reverse order (top to bottom in rendering)
      for (index, body) in draggableBodies.enumerated().reversed() {
        let bodyPos = body.position
        let dx = position.x - bodyPos.x
        let dy = position.y - bodyPos.y
        let distanceSquared = dx * dx + dy * dy
        let radiusSquared = body.radius * body.radius

        if distanceSquared <= radiusSquared {
          return body
        }
      }
      return nil
    }

    func isBodyBeingDragged(_ bodyId: b2BodyId) -> Bool {
      return dragState.isBodyBeingDragged(bodyId)
    }

    /// Update the coordinate system based on the current view size.
    func updateCoords(_ size: CGSize) {
      coords = CoordinateSystem(
        renderScale: Float(size.width) / Float(worldWidthInMeters),
        viewSize: size
      )
    }

    func onResize(_ newSize: CGSize) {
      updateCoords(newSize)

      // Remove existing walls
      for wall in walls {
        b2DestroyBody(wall.bodyId)
      }
      walls.removeAll()

      // TODO Return world bounds in world space (I think this is the only place
      // we need them)
      let width = coords.worldBounds.x
      let height = coords.worldBounds.y

      // Create four walls (static bodies) in physics coordinates
      let wallDefinitions: [(b2Vec2, b2Vec2)] = [
        // Top wall
        (b2Vec2(x: 0, y: 0), b2Vec2(x: width, y: 0)),
        // Bottom wall
        (b2Vec2(x: 0, y: height), b2Vec2(x: width, y: height)),
        // Left wall
        (b2Vec2(x: 0, y: 0), b2Vec2(x: 0, y: height)),
        // Right wall
        (b2Vec2(x: width, y: 0), b2Vec2(x: width, y: height)),
      ]

      for (start, end) in wallDefinitions {
        let wall = PhysicsWall(world: world, start: start, end: end)
        walls.append(wall)
      }
    }

    // We still need to sync drag events with world locking by maintaining that
    // state internally.
    func onDragMove(to position: CGPoint) {
      let mousePosition = coords.toWorld(position)

      if !dragState.dragging {
        guard let body = findBodyAt(mousePosition, coords: coords) else {
          print("No body found at position \(mousePosition)")
          return
        }

        dragState.onDragStart(bodyId: body.bodyId, position: mousePosition)
      }

      dragState.onDragMove(position: mousePosition)
    }

    func onDragEnd() {
      dragState.onDragEnd()
    }

    func cleanup() {}
  }

  class DragJoint {
    var joint: b2JointId?
    var bodyId: b2BodyId?
    var target: b2Vec2?
    var destroyed: Bool = true
    var dragging: Bool {
      return joint != nil && !destroyed
    }

    private var world: b2WorldId
    private var groundBody: b2BodyId

    // Higher stiffness for more responsive dragging
    let hertz: Float = 10.0
    let dampingRatio: Float = 0.7

    init(world: b2WorldId) {
      self.world = world

      // Create a static ground body that can be used to initialize the joint.
      var groundDef = b2DefaultBodyDef()
      groundDef.type = b2_staticBody
      groundDef.position = b2Vec2(x: 0, y: 0)

      self.groundBody = b2CreateBody(world, &groundDef)
    }

    func isBodyBeingDragged(_ id: b2BodyId) -> Bool {
      guard let currentBodyId = bodyId else { return false }
      return dragging && currentBodyId == id
    }

    /// Initializes the drag joint state. This will be called for you on the first
    /// `onDragMove` event but is exposed in case you need to manually start a drag.
    func onDragStart(
      /// The body to drag
      bodyId: b2BodyId,
      /// The initial position of the drag
      position: b2Vec2,
    ) {
      // Wake up the body
      b2Body_SetAwake(bodyId, true)

      let mass = b2Body_GetMass(bodyId)

      // Create a mouse joint to smoothly drag the body
      var mouseDef = b2DefaultMouseJointDef()
      mouseDef.bodyIdA = self.groundBody
      mouseDef.bodyIdB = bodyId
      mouseDef.target = position
      mouseDef.hertz = hertz
      mouseDef.dampingRatio = dampingRatio
      mouseDef.maxForce = 10000.0 * mass

      self.destroyed = false
      self.target = position
      self.bodyId = bodyId
      self.joint = b2CreateMouseJoint(world, &mouseDef)

      print("Started drag joint for body \(bodyId) to position \(position)")
    }

    /// Updates the drag joint target position.
    func onDragMove(position: b2Vec2) {
      self.target = position
    }

    /// Marks the drag joint for destruction. Should be called when the view stops dragging.
    func onDragEnd() {
      self.destroyed = true
      print("Marked drag joint for destruction")
    }

    /// Applies the pending drag updates to the physics world.
    /// Call this right before the world step function.
    func apply() {
      if destroyed {
        cleanup()
        return
      } else if let joint = joint, let target = target {
        b2MouseJoint_SetTarget(joint, target)
        self.target = nil
      }
    }

    /// Destroy the current drag state. This will be called automatically for you
    /// but is exposed in case you need to manually reset the drag state.
    func cleanup() {
      guard let joint = joint else { return }

      b2DestroyJoint(joint)
      self.joint = nil
      self.bodyId = nil
      self.destroyed = true
      self.target = nil
      print("Destroyed drag joint")
    }
  }
}
