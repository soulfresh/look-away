import SwiftUI

@MainActor
class PhysicsEngine: ObservableObject {
  @Published var balls: [Ball]
  var redBallId: UUID
  var bounds: CGSize
  private let clock: any Clock<Duration>
  private var updateTask: Task<Void, Never>?

  // Physics constants
  private let repulsionStrength: CGFloat = 5000.0  // Force strength from red ball
  private let dampingFactor: CGFloat = 0.98  // Velocity damping per frame
  private let minDistance: CGFloat = 0.1  // Minimum distance for force calculations

  init(
    balls: [Ball] = [], redBallId: UUID = UUID(), bounds: CGSize = .zero,
    clock: some Clock<Duration> = ContinuousClock()
  ) {
    self.balls = balls
    self.redBallId = redBallId
    self.bounds = bounds
    self.clock = clock
  }

  func start() {
    updateTask = Task {
      while !Task.isCancelled {
        try? await clock.sleep(for: .milliseconds(16))  // ~60fps
        updatePhysics()
      }
    }
  }

  func stop() {
    updateTask?.cancel()
    updateTask = nil
  }

  private func updatePhysics() {
    let deltaTime: CGFloat = 1.0 / 60.0  // Fixed timestep

    // Find red ball
    guard let redBallIndex = balls.firstIndex(where: { $0.id == redBallId }) else { return }
    let redBall = balls[redBallIndex]

    // Update each blue ball
    for i in balls.indices {
      if balls[i].isStatic { continue }  // Skip static balls (red ball)

      // Calculate repulsion force from red ball
      let dx = balls[i].position.x - redBall.position.x
      let dy = balls[i].position.y - redBall.position.y
      let distanceSquared = dx * dx + dy * dy
      let distance = sqrt(distanceSquared)

      // Only apply force if not too close (avoid division by zero)
      if distance > minDistance {
        // Repulsion force (inverse square law)
        let forceMagnitude = repulsionStrength / distanceSquared

        // Normalize direction and apply force
        let forceX = (dx / distance) * forceMagnitude
        let forceY = (dy / distance) * forceMagnitude

        // Update velocity: v += (F / m) * dt
        balls[i].velocity.dx += (forceX / balls[i].mass) * deltaTime
        balls[i].velocity.dy += (forceY / balls[i].mass) * deltaTime
      }

      // Apply damping
      balls[i].velocity.dx *= dampingFactor
      balls[i].velocity.dy *= dampingFactor

      // Update position
      balls[i].position.x += balls[i].velocity.dx * deltaTime
      balls[i].position.y += balls[i].velocity.dy * deltaTime

      // Wall collision detection and response
      let radius = balls[i].radius

      // Left/Right walls
      if balls[i].position.x - radius < 0 {
        balls[i].position.x = radius
        balls[i].velocity.dx = abs(balls[i].velocity.dx) * 0.8  // Bounce with energy loss
      } else if balls[i].position.x + radius > bounds.width {
        balls[i].position.x = bounds.width - radius
        balls[i].velocity.dx = -abs(balls[i].velocity.dx) * 0.8
      }

      // Top/Bottom walls
      if balls[i].position.y - radius < 0 {
        balls[i].position.y = radius
        balls[i].velocity.dy = abs(balls[i].velocity.dy) * 0.8
      } else if balls[i].position.y + radius > bounds.height {
        balls[i].position.y = bounds.height - radius
        balls[i].velocity.dy = -abs(balls[i].velocity.dy) * 0.8
      }
    }

    // Ball-to-ball collision detection
    // First pass: handle collisions with static balls (red ball)
    for i in balls.indices {
      if balls[i].isStatic { continue }  // Skip static balls as the primary ball

      for j in balls.indices {
        if i == j { continue }  // Skip self
        if !balls[j].isStatic { continue }  // Only check against static balls in this pass

        let dx = balls[j].position.x - balls[i].position.x
        let dy = balls[j].position.y - balls[i].position.y
        let distance = sqrt(dx * dx + dy * dy)
        let minDist = balls[i].radius + balls[j].radius

        // Check for collision
        if distance < minDist && distance > 0 {
          // Normalize collision direction
          let nx = dx / distance
          let ny = dy / distance
          let overlap = minDist - distance

          // Collision with static ball (red ball)
          // Only push the dynamic ball (i) away, don't move the static ball
          balls[i].position.x -= nx * overlap
          balls[i].position.y -= ny * overlap

          // Bounce the dynamic ball off the static ball
          let velocityAlongNormal = balls[i].velocity.dx * nx + balls[i].velocity.dy * ny
          if velocityAlongNormal < 0 {
            let restitution: CGFloat = 0.8
            balls[i].velocity.dx -= (1 + restitution) * velocityAlongNormal * nx
            balls[i].velocity.dy -= (1 + restitution) * velocityAlongNormal * ny
          }
        }
      }
    }

    // Second pass: handle collisions between dynamic balls (blue-to-blue)
    // Use j > i to avoid processing each pair twice
    for i in balls.indices {
      if balls[i].isStatic { continue }

      for j in (i + 1)..<balls.count {
        if balls[j].isStatic { continue }

        let dx = balls[j].position.x - balls[i].position.x
        let dy = balls[j].position.y - balls[i].position.y
        let distance = sqrt(dx * dx + dy * dy)
        let minDist = balls[i].radius + balls[j].radius

        // Check for collision
        if distance < minDist && distance > 0 {
          // Normalize collision direction
          let nx = dx / distance
          let ny = dy / distance
          let overlap = minDist - distance

          // Collision between two dynamic balls
          // Separate balls to prevent overlap
          let separationX = nx * overlap * 0.5
          let separationY = ny * overlap * 0.5

          balls[i].position.x -= separationX
          balls[i].position.y -= separationY
          balls[j].position.x += separationX
          balls[j].position.y += separationY

          // Simple elastic collision response (equal mass assumption for simplicity)
          let relativeVelocityX = balls[j].velocity.dx - balls[i].velocity.dx
          let relativeVelocityY = balls[j].velocity.dy - balls[i].velocity.dy
          let velocityAlongNormal = relativeVelocityX * nx + relativeVelocityY * ny

          // Only resolve if balls are moving towards each other
          if velocityAlongNormal < 0 {
            let restitution: CGFloat = 0.8  // Bounciness
            let impulse = -(1 + restitution) * velocityAlongNormal / 2

            balls[i].velocity.dx -= impulse * nx
            balls[i].velocity.dy -= impulse * ny
            balls[j].velocity.dx += impulse * nx
            balls[j].velocity.dy += impulse * ny
          }
        }
      }
    }

    // Final pass: ensure all balls are within bounds after collision resolution
    for i in balls.indices {
      let radius = balls[i].radius

      // Clamp to bounds
      balls[i].position.x = min(max(balls[i].position.x, radius), bounds.width - radius)
      balls[i].position.y = min(max(balls[i].position.y, radius), bounds.height - radius)
    }
  }

  func updateRedBallPosition(_ position: CGPoint) {
    if let index = balls.firstIndex(where: { $0.id == redBallId }) {
      balls[index].position = position
    }
  }
}

struct Ball: Identifiable {
  let id = UUID()
  var position: CGPoint
  var velocity: CGVector
  var radius: CGFloat
  var mass: CGFloat
  var color: Color
  var isStatic: Bool  // true for red ball (user-controlled), false for blue balls
}

struct PhysicsPlayground: View {
  @StateObject private var physicsEngine = PhysicsEngine()
  @State private var viewSize: CGSize = .zero
  @State private var initialized: Bool = false

  var body: some View {
    GeometryReader { geometry in
      if initialized {
        Canvas { context, size in
          // Draw all balls
          for (index, ball) in physicsEngine.balls.enumerated() {
            var path = Path()
            path.addEllipse(
              in: CGRect(
                x: ball.position.x - ball.radius,
                y: ball.position.y - ball.radius,
                width: ball.radius * 2,
                height: ball.radius * 2
              ))
            context.fill(path, with: .color(ball.color))

            // Draw index for blue balls (non-static balls)
            if !ball.isStatic {
              let text = Text("\(index)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
              context.draw(text, at: ball.position)
            }
          }
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              // Clamp position to stay within bounds
              if let redBall = physicsEngine.balls.first(where: { $0.id == physicsEngine.redBallId }
              ) {
                let x = min(max(value.location.x, redBall.radius), viewSize.width - redBall.radius)
                let y = min(max(value.location.y, redBall.radius), viewSize.height - redBall.radius)
                physicsEngine.updateRedBallPosition(CGPoint(x: x, y: y))
              }
            }
        )
      }
      Color.clear
        .onAppear {
          if !initialized {
            viewSize = geometry.size

            var balls: [Ball] = []

            // Create red ball (static, user-controlled)
            var redBall = Ball(
              position: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2),
              velocity: .zero,
              radius: 20,
              mass: 1.0,
              color: .red,
              isStatic: true
            )
            balls.append(redBall)

            // Initialize blue balls with random positions
            let blueBallRadius: CGFloat = 15
            for _ in 0..<3 {
              let x = CGFloat.random(in: blueBallRadius...(geometry.size.width - blueBallRadius))
              let y = CGFloat.random(in: blueBallRadius...(geometry.size.height - blueBallRadius))
              let ball = Ball(
                position: CGPoint(x: x, y: y),
                velocity: .zero,
                radius: blueBallRadius,
                mass: 1.0,
                color: .blue,
                isStatic: false
              )
              balls.append(ball)
            }

            // Update physics engine
            physicsEngine.balls = balls
            physicsEngine.redBallId = redBall.id
            physicsEngine.bounds = geometry.size

            // Start the physics simulation
            physicsEngine.start()

            initialized = true
          }
        }
        .onDisappear {
          physicsEngine.stop()
        }
    }
    .background(Color.black.opacity(0.1))
  }
}

#Preview {
  PhysicsPlayground()
    .frame(width: 600, height: 600)
}
