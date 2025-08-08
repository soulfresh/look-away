import Foundation
import SwiftUI

extension Color {
  static let theme = Theme()
}

struct Theme {
  let primary = Color("PrimaryColor")
  let secondary = Color("SecondaryColor")
  let accent = Color("AccentColor")

  let background = Color("BackgroundColor")
  let foreground = Color("ForegroundColor")

  let error = Color("ErrorColor")
  let success = Color("SuccessColor")
  let warning = Color("WarningColor")

  let border = Color("BorderColor")
}
