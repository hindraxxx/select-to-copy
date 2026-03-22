import Cocoa
import ApplicationServices

class SelectionObserver {
    private var observer: AXObserver?
    private var globalMouseUpMonitor: Any?
    private var globalKeyUpMonitor: Any?
    private var currentPID: pid_t = 0
    private var lastCopiedText: String = ""
    private var lastFallbackAttemptAt: Date = .distantPast
    private let fallbackCooldownSeconds: TimeInterval = 0.35
    private let fallbackCopyEnabled = UserDefaults.standard.object(forKey: "FallbackCopyEnabled") as? Bool ?? true
    private let fallbackBundleIdentifiers: Set<String> = [
        "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram",
        "com.tdesktop.Telegram",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp"
    ]
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

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.captureSelection(trigger: "mouse-up")
        }

        globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] _ in
            self?.captureSelection(trigger: "key-up")
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
        }
        if let globalKeyUpMonitor {
            NSEvent.removeMonitor(globalKeyUpMonitor)
        }
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
        captureSelection(trigger: "ax-selection-change")
    }

    private func captureSelection(trigger: String) {
        // Get the focused element to read the actual text
        var focusedElement: AnyObject?
        let systemWide = AXUIElementCreateSystemWide()
        
        let focusedElementResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedElementResult == AXError.success, let focusedElement else {
            attemptFallbackCopy(reason: "focused-element-read-failed/\(trigger)")
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
            attemptFallbackCopy(reason: "selected-text-read-failed/\(trigger)")
            return
        }

        guard let text = selectedText as? String else {
            attemptFallbackCopy(reason: "selected-text-non-string/\(trigger)")
            return
        }

        guard !text.isEmpty else {
            attemptFallbackCopy(reason: "selected-text-empty/\(trigger)")
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

    private func attemptFallbackCopy(reason: String) {
        guard fallbackCopyEnabled else { return }
        guard isPermissionAvailable else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontApp.bundleIdentifier,
              fallbackBundleIdentifiers.contains(bundleIdentifier)
        else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastFallbackAttemptAt) > fallbackCooldownSeconds else { return }
        lastFallbackAttemptAt = now

        let pasteboard = NSPasteboard.general
        let beforeChangeCount = pasteboard.changeCount
        sendCommandC()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let updatedPasteboard = NSPasteboard.general
            guard updatedPasteboard.changeCount != beforeChangeCount else { return }
            guard let copiedText = updatedPasteboard.string(forType: .string), !copiedText.isEmpty else { return }
            guard copiedText != self.lastCopiedText else { return }
            self.lastCopiedText = copiedText
            self.log("Fallback copy succeeded (\(reason)) for \(bundleIdentifier)")
        }
    }

    private func sendCommandC() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log("Failed to create CGEventSource for fallback copy")
            return
        }

        let cKeyCode: CGKeyCode = 8
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        else {
            log("Failed to create keyboard events for fallback copy")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func log(_ message: String) {
        print("[SelectionObserver] \(message)")
    }
}
