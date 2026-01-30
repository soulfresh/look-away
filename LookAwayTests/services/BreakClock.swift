import Clocks
import Foundation

class BreakClock {
  let clock = TestClock()

  func tick() async {
    await clock.advance(by: .zero)
  }

  func advanceBy(_ seconds: TimeInterval) async {
    // We need to call advance in a loop because the code does not call clock.sleep(100)
    // Instead it calls `clock.sleep(1)`, advances 1s and then calls `clock.sleep(1)` again.
    // To replicate that, we need to call `clock.advance()` as many times as the
    // number of seconds we want to move forward in time.
    for _ in 0..<Int(seconds) {
      await clock.advance(by: .seconds(1))
    }
  }

  func run() async {
    await clock.run()
  }
}
