import Clocks
import Combine
import Foundation
import Testing

@testable import LookAway

final class BreakSpy: Break {
  var cancelCallCount = 0

  override func cancel() {
    cancelCallCount += 1
    super.cancel()
  }
}

// Actor to safely manage the continuation and cancellable across concurrent tasks.
private actor ContinuationActor<Output> {
  var continuation: CheckedContinuation<Output, Error>?
  var cancellable: AnyCancellable?

  func set(continuation: CheckedContinuation<Output, Error>, cancellable: AnyCancellable) {
    self.continuation = continuation
    self.cancellable = cancellable
  }

  func resume(returning value: Output) {
    continuation?.resume(returning: value)
    continuation = nil
    cancellable = nil
  }

  func resume(throwing error: Error) {
    continuation?.resume(throwing: error)
    continuation = nil
    cancellable = nil
  }

  func cancel() {
    cancellable?.cancel()
    self.resume(throwing: CancellationError())
  }
}

/// Awaits the first value from a publisher that satisfies a given condition.
/// Throws a `CancellationError` if the timeout is reached or the task is cancelled.
func awaitPublisher<P: Publisher>(
  _ publisher: P,
  timeout: TimeInterval = 1,
  while condition: @escaping (P.Output) -> Bool = { _ in true }
) async throws -> P.Output where P.Failure == Never {
  let actor = ContinuationActor<P.Output>()

  return try await withTaskCancellationHandler {
    try await withCheckedThrowingContinuation { continuation in
      let cancellable =
        publisher
        .first(where: condition)
        .sink { value in
          Task { await actor.resume(returning: value) }
        }

      Task {
        await actor.set(continuation: continuation, cancellable: cancellable)
      }

      Task {
        try await Task.sleep(for: .seconds(timeout))
        await actor.resume(throwing: CancellationError())
      }
    }
  } onCancel: {
    Task { await actor.cancel() }
  }
}

struct BreakTests {
  let clock: TestClock<Duration>!
  var breakInstance: BreakSpy!

  init() {
    clock = TestClock()
    breakInstance = BreakSpy(
      frequency: 100,
      duration: 50,
      performance: PerformanceTimer(),
      clock: clock
    )
  }

  func afterEach() async {
    breakInstance.cancel()
    await clock.run()
  }

  @Test("Starts in the idle state.")
  func testInitialState() async {
    #expect(breakInstance.phase == .idle)
    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.frequency == 100)
    #expect(breakInstance.duration == 50)
    #expect(breakInstance.cancelCallCount == 0)

    await afterEach()
  }

  @Test("Cancels the timer on destruction.")
  func testCancelOnDestruction() {}

  @Test("Should be able to start working.")
  func testStartWorking() async throws {
    async let phaseAfterOneSecond = awaitPublisher(breakInstance.$phase) { phase in
      if case .working(let remaining) = phase {
        return remaining == 99.0
      }
      return false
    }

    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()

    print("> Advance 0")
    // Ensure the asynchronous task has started.
    await clock.advance(by: .zero)

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)

    print("> Advance 1")
    await clock.advance(by: .seconds(1))
    try await phaseAfterOneSecond

    #expect(breakInstance.phase == .working(remaining: 99))

    async let breakingPhase = awaitPublisher(breakInstance.$phase) {
      $0 == .breaking(remaining: 50)
    }
    print("> Advance 100")
    // Advance into the breaking phase
    await clock.advance(by: .seconds(100))
    try await breakingPhase

    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)

    print("> Done")
    await afterEach()
  }

  @Test("Should be able to restart the working phase with a given duration while it is running.")
  func testRestartWorking() async {
    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startWorking()

    // Ensure the asynchronous task has started.
    await clock.advance(by: .zero)

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .working(remaining: 100))
    #expect(breakInstance.isRunning == true)

    await clock.advance(by: .seconds(10))

    #expect(breakInstance.phase == .working(remaining: 90))

    breakInstance.startWorking(20)

    #expect(breakInstance.cancelCallCount == 2)

    await clock.advance(by: .zero)

    #expect(breakInstance.phase == .working(remaining: 20))
    #expect(breakInstance.isRunning == true)

    await afterEach()
  }

  @Test("Should be able to start a break.")
  func testStartBreak() async {
    #expect(breakInstance.cancelCallCount == 0)

    breakInstance.startBreak()

    // Ensure the asynchronous task has started.
    await clock.advance(by: .zero)

    #expect(breakInstance.cancelCallCount == 1)
    #expect(breakInstance.phase == .breaking(remaining: 50))
    #expect(breakInstance.isRunning == true)

    await clock.advance(by: .seconds(1))

    #expect(breakInstance.phase == .breaking(remaining: 49))

    await clock.advance(by: .seconds(50))

    #expect(breakInstance.phase == .finished)
    #expect(breakInstance.isRunning == false)

    await afterEach()
  }

  @Test("Should be able to transition from working to breaking to finished.")
  func testFullFlow() async {
    breakInstance.startWorking()

    await clock.advance(by: .seconds(1))

    #expect(breakInstance.phase == .working(remaining: 99))

    await clock.advance(by: .seconds(100))

    #expect(breakInstance.phase == .breaking(remaining: 50))

    await clock.advance(by: .seconds(51))

    #expect(breakInstance.phase == .finished)
    #expect(breakInstance.isRunning == false)

    await afterEach()
  }

  @Test("Should be able to pause and resume.")
  func testPauseAndResume() async {
    breakInstance.startWorking()

    #expect(breakInstance.cancelCallCount == 1)

    await clock.advance(by: .seconds(10))

    #expect(breakInstance.phase == .working(remaining: 90))

    breakInstance.pause()

    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    await clock.advance(by: .seconds(5))

    #expect(breakInstance.phase == .working(remaining: 90))

    breakInstance.resume()

    await clock.advance(by: .zero)

    #expect(breakInstance.isRunning == true)
    #expect(breakInstance.phase == .working(remaining: 90))

    await clock.advance(by: .seconds(5))

    #expect(breakInstance.phase == .working(remaining: 85))

    await afterEach()
  }

  @Test("Should be able to reset the break to the beginning.")
  func testReset() async {
    breakInstance.startWorking()

    await clock.advance(by: .zero)
    await clock.advance(by: .seconds(10))

    #expect(breakInstance.phase == .working(remaining: 90))
    #expect(breakInstance.isRunning == true)

    breakInstance.reset()

    #expect(breakInstance.phase == .idle)

    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    await afterEach()
  }

  @Test("Should be able to cancel the timer task without affecting the phase.")
  func testCancelTimerTask() async {
    breakInstance.startWorking()

    await clock.advance(by: .zero)
    await clock.advance(by: .seconds(10))

    #expect(breakInstance.phase == .working(remaining: 90))
    #expect(breakInstance.isRunning == true)

    breakInstance.cancel()

    #expect(breakInstance.isRunning == false)
    #expect(breakInstance.cancelCallCount == 2)

    await clock.advance(by: .seconds(5))

    #expect(breakInstance.phase == .working(remaining: 90))

    await afterEach()
  }
}
