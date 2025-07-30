import Foundation
import Testing

@testable import LookAway

struct TimeFormatterTests {

  @Test("Formats a duration over a minute")
  func testFormat_overAMinute() {
    #expect(TimeFormatter.format(duration: 95) == "01:35")
  }

  @Test("Formats a duration under a minute")
  func testFormat_underAMinute() {
    #expect(TimeFormatter.format(duration: 45) == "00:45")
  }

  @Test("Formats an exact minute")
  func testFormat_exactMinute() {
    #expect(TimeFormatter.format(duration: 120) == "02:00")
  }

  @Test("Formats a zero duration")
  func testFormat_zero() {
    #expect(TimeFormatter.format(duration: 0) == "00:00")
  }

  @Test("Formats a large duration")
  func testFormat_largeDuration() {
    // 59 minutes and 59 seconds
    #expect(TimeFormatter.format(duration: 3599) == "59:59")
  }
}
