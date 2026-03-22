import Cocoa
import ApplicationServices

class SelectionObserver {
    private var observer: AXObserver?
    private var currentPID: pid_t = 0
    private var lastCopiedText: String = ""
    private var isPermissionAvailable: Bool {
        AXIsProcessTrusted()
    }

    init() {
        // Watch for application switches to update the observer
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Initialize with the current frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            setupObserver(for: frontApp.processIdentifier)
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeCurrentObserver()
    }

    func refreshObservationForCurrentApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            log("No frontmost application available for observer refresh")
            return
        }
        setupObserver(for: frontApp.processIdentifier, force: true)
    }

    @objc private func appChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        setupObserver(for: app.processIdentifier)
    }

    private func setupObserver(for pid: pid_t, force: Bool = false) {
        if !force, currentPID == pid, observer != nil {
            return
        }

        removeCurrentObserver()

        guard isPermissionAvailable else {
            currentPID = 0
            log("Accessibility permission missing; observer not started")
            return
        }

        self.currentPID = pid
        
        // Create the observer for the specific PID
        var newObserver: AXObserver?
        let result = AXObserverCreate(pid, { (observer, element, notification, refcon) in
            guard let refcon = refcon else { return }
            let observerSelf = Unmanaged<SelectionObserver>.fromOpaque(refcon).takeUnretainedValue()
            observerSelf.handleSelectionChange(element: element)
        }, &newObserver)

        guard result == AXError.success, let observer = newObserver else {
            log("Failed to create AXObserver for pid \(pid): \(result.rawValue)")
            currentPID = 0
            return 
        }
        self.observer = observer

        // Add the notifications for selection changes
        let appElement = AXUIElementCreateApplication(pid)
        
        // kAXSelectedTextChangedNotification is standard for text changes
        let selectedTextChangedResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXSelectedTextChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        // kAXFocusedUIElementChangedNotification helps capture apps that miss selected-text notifications.
        let focusedElementChangedResult = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        if selectedTextChangedResult != AXError.success {
            log("Failed adding selected text changed notification for pid \(pid): \(selectedTextChangedResult.rawValue)")
        }

        if focusedElementChangedResult != AXError.success {
            log("Failed adding focused element changed notification for pid \(pid): \(focusedElementChangedResult.rawValue)")
        }

        if selectedTextChangedResult != AXError.success && focusedElementChangedResult != AXError.success {
            removeCurrentObserver()
            currentPID = 0
            return
        }
        
        // Add to current run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func handleSelectionChange(element: AXUIElement) {
        // Get the focused element to read the actual text
        var focusedElement: AnyObject?
        let systemWide = AXUIElementCreateSystemWide()
        
        let focusedElementResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedElementResult == AXError.success, let focusedElement else {
            log("Could not read focused UI element: \(focusedElementResult.rawValue)")
            return
        }
        let focusedAXElement = focusedElement as! AXUIElement

        var selectedText: AnyObject?
        let selectedTextResult = AXUIElementCopyAttributeValue(
            focusedAXElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        guard selectedTextResult == AXError.success else {
            log("Could not read selected text: \(selectedTextResult.rawValue)")
            return
        }

        guard let text = selectedText as? String else {
            log("Selected text value is not a String")
            return
        }

        guard !text.isEmpty else {
            return
        }

        copyToClipboard(text: text)
    }

    private func copyToClipboard(text: String) {
        // Avoid redundant copies if the selection hasn't changed content
        guard text != lastCopiedText else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        lastCopiedText = text
        print("Copied to clipboard: \(text.prefix(50))...")
    }

    private func removeCurrentObserver() {
        guard let oldObserver = observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(oldObserver), .defaultMode)
        observer = nil
    }

    private func log(_ message: String) {
        print("[SelectionObserver] \(message)")
    }
}
