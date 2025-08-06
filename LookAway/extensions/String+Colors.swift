import Foundation

extension String {
  enum Colors {
    static let red = "\u{001B}[0;31m"
    static let green = "\u{001B}[0;32m"
    static let yellow = "\u{001B}[0;33m"
    static let blue = "\u{001B}[0;34m"
    static let magenta = "\u{001B}[0;35m"
    static let cyan = "\u{001B}[0;36m"
    static let white = "\u{001B}[0;37m"
    static let grey = "\u{001B}[0;90m"
    static let reset = "\u{001B}[0m"
  }

  private func colorize(with color: String) -> String {
    // Use this to enable/disable colorization
    if ProcessInfo.processInfo.environment["WITH_COLOR"] == "1" {
      return "\(color)\(self.withColorReset())"
    }
    return self
  }

  func withColorReset() -> String {
    "\(self)\(Colors.reset)"
  }

  func red() -> String {
    colorize(with: Colors.red)
  }

  func green() -> String {
    colorize(with: Colors.green)
  }

  func yellow() -> String {
    colorize(with: Colors.yellow)
  }

  func blue() -> String {
    colorize(with: Colors.blue)
  }

  func magenta() -> String {
    colorize(with: Colors.magenta)
  }

  func cyan() -> String {
    colorize(with: Colors.cyan)
  }

  func grey() -> String {
    colorize(with: Colors.grey)
  }
}
