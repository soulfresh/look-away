import KeyboardShortcuts

extension KeyboardShortcuts.Name {
  // TODO: Show a welcome screen on first launch and ask the user to customize these?
  // Or just leave the default where they are not customized until user visits the settings?
  static let togglePause = Self("togglePause", default: .init(.p, modifiers: [.command, .option, .control]))
  static let takeBreak = Self("takeBreak", default: .init(.b, modifiers: [.command, .option, .control]))
}
