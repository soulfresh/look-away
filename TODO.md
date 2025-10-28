Next:
- Break phase never starts
- Jump to next long break
  - Should be able to jump both when working or in a short break
  - This should not impact my skipped or delayed count
- Less frequent updates when menu closed and not blocking
- Update AppIcon

Tech:
- GitHub actions
- Disable activity listeners if schedule is empty

Other:
- Display shortcut keys in menu from KeyboardShortcuts library
- Startup screen with
  - open on login
  - set keyboard shortcuts
- Make settings window look more like a native Settings tab bar
- Don't reset schedule when closing settings if the settings didn't change
- Pause when certain apps are opened
- Exercise instructions
- Improve usablility of Schedule form
  - accessibility
  - tab focus
  - combine textfield/picker component
