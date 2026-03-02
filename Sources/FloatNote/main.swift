import AppKit

// Entry point for the FloatNote SPM executable.
// We use NSApplicationMain-style bootstrap manually since @main isn't
// available without -parse-as-library in SPM executable targets.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Suppress Dock icon programmatically as belt-and-suspenders
// (Info.plist LSUIElement is the primary mechanism).
app.setActivationPolicy(.accessory)

app.run()
