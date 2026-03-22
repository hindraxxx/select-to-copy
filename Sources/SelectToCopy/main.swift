import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// NSApplicationMain is a bit cleaner for bootstrapping the standard app lifecycle
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
