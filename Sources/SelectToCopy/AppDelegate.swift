import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var selectionObserver: SelectionObserver?
    private var startAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the status item in the system menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Using a system symbol for the icon
            button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "SelectToCopy")
        }
        
        constructMenu()

        // Check for accessibility permissions
        checkAccessibilityPermissions()

        // Start observing text selection (runs in degraded mode without permission)
        selectionObserver = SelectionObserver()
    }

    func constructMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "SelectToCopy is Running", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let startAtLoginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        startAtLoginItem.target = self
        menu.addItem(startAtLoginItem)
        startAtLoginMenuItem = startAtLoginItem
        menu.addItem(NSMenuItem(title: "Check Accessibility Permissions", action: #selector(checkPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SelectToCopy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        refreshStartAtLoginState()
    }

    @objc private func toggleStartAtLogin() {
        guard #available(macOS 13.0, *) else {
            let alert = NSAlert()
            alert.messageText = "Start at Login Unsupported"
            alert.informativeText = "This option requires macOS 13 or newer."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        do {
            let service = SMAppService.mainApp
            switch service.status {
            case .enabled:
                try service.unregister()
            case .notRegistered, .requiresApproval, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
            refreshStartAtLoginState()
        } catch {
            print("[AppDelegate] Failed to update start-at-login setting: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could Not Update Start at Login"
            alert.informativeText = "macOS could not change the login setting for this app. Make sure you run the bundled app from Applications and allow background login items if prompted."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func refreshStartAtLoginState() {
        guard let startAtLoginMenuItem else { return }
        guard #available(macOS 13.0, *) else {
            startAtLoginMenuItem.state = .off
            startAtLoginMenuItem.isEnabled = false
            return
        }

        let service = SMAppService.mainApp
        startAtLoginMenuItem.isEnabled = true
        startAtLoginMenuItem.state = service.status == .enabled ? .on : .off
    }

    @objc func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            print("[AppDelegate] Accessibility permission is not granted")
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "SelectToCopy needs Accessibility access to monitor text selection. Please enable it in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            selectionObserver?.refreshObservationForCurrentApp()
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Enabled"
            alert.informativeText = "SelectToCopy already has the necessary permissions."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }
    
    private func checkAccessibilityPermissions() {
        // Just check without prompting on startup to avoid annoying the user
        let accessEnabled = AXIsProcessTrusted()
        if !accessEnabled {
            print("[AppDelegate] Warning: Accessibility permissions not granted. App will run with limited functionality.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "Enable Accessibility for SelectToCopy"
                alert.informativeText = "SelectToCopy cannot auto-copy selections until Accessibility is enabled in System Settings > Privacy & Security > Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
