import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private var setup: NSWindow?
    private let setupPassword = NSSecureTextField()
    private let confirmation = NSSecureTextField()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let setupHint = "Confirm your password to activate the curtain."
    private var password: SessionPassword?
    private var curtains: [NSNumber: CurtainWindow] = [:]
    private var savedPresentation: NSApplication.PresentationOptions = []
    private var activity = AgentActivity()
    private var activityTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 412, height: 268),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Skjermgardin"
        window.delegate = self
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        setup = window

        let logo = NSImageView()
        logo.image = Bundle.main.url(forResource: "Skjermgardin", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityElement(false)
        let heading = NSTextField(labelWithString: "Set a password")
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        message.stringValue = setupHint
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        setupPassword.placeholderString = "Password (8+ characters)"
        confirmation.placeholderString = "Confirm password"
        setupPassword.setAccessibilityHelp(setupHint)
        for field in [setupPassword, confirmation] {
            field.setAccessibilityLabel(field.placeholderString)
            field.controlSize = .large
            field.font = .systemFont(ofSize: 15)
            field.bezelStyle = .roundedBezel
            field.alignment = .left
            field.delegate = self
            field.cell?.sendsActionOnEndEditing = false
            field.target = self
        }
        setupPassword.action = #selector(focusConfirmation)
        confirmation.action = #selector(arm)
        setupPassword.nextKeyView = confirmation
        confirmation.nextKeyView = setupPassword

        let footnote = NSTextField(wrappingLabelWithString: "Quitting the curtain reveals your desktop.")
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = .secondaryLabelColor
        for label in [heading, message, footnote] { label.alignment = .left }
        let stack = NSStackView(views: [logo, heading, message, setupPassword, confirmation, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.setCustomSpacing(4, after: logo)
        stack.setCustomSpacing(6, after: heading)
        stack.setCustomSpacing(12, after: message)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = window.contentView!
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 40),
            logo.heightAnchor.constraint(equalTo: logo.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ] + [message, setupPassword, confirmation, footnote].map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        window.initialFirstResponder = setupPassword
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            let y = max(area.minY, area.midY - window.frame.height / 2)
            window.setFrameOrigin(NSPoint(x: round(area.midX - window.frame.width / 2), y: round(y)))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard password == nil else { return }
        message.stringValue = setupHint
        message.textColor = .secondaryLabelColor
        let value = setupPassword.stringValue
        let matches = value.count >= 8 && value == confirmation.stringValue
        let editor = (notification.object as? NSTextField)?.currentEditor() as? NSTextView
        guard matches, editor?.hasMarkedText() != true else { return }
        arm()
    }

    @objc private func focusConfirmation() { setup?.makeFirstResponder(confirmation) }

    @objc private func arm() {
        guard password == nil else { return }
        guard setupPassword.stringValue.count >= 8 else {
            message.textColor = .systemRed
            message.stringValue = "Use at least 8 characters."
            setup?.makeFirstResponder(setupPassword)
            return
        }
        guard confirmation.stringValue == setupPassword.stringValue else {
            message.textColor = .systemRed
            message.stringValue = confirmation.stringValue.isEmpty ? "Enter your password again." : "The passwords don’t match. Try again."
            confirmation.selectText(nil)
            return
        }
        guard !NSScreen.screens.isEmpty, let secret = SessionPassword(setupPassword.stringValue) else {
            message.textColor = .systemRed
            message.stringValue = "Couldn’t activate the curtain. Try again."
            return
        }
        password = secret
        for field in [setupPassword, confirmation] {
            field.abortEditing()
            field.stringValue = ""
        }
        savedPresentation = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        reconcileDisplays()
        let queue = DispatchQueue(label: "Skjermgardin.activity", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            let snapshot = AgentActivity.current()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.password != nil else { return }
                self.activity = snapshot
                for curtain in self.curtains.values { curtain.mascots.show(snapshot) }
            }
        }
        activityTimer = timer
        timer.resume()
        setup?.orderOut(nil)
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) { reconcileDisplays() }

    private func reconcileDisplays() {
        guard password != nil else { return }
        var current = Set<NSNumber>()
        var mainWindow: CurtainWindow?
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            current.insert(id)
            let window = curtains[id] ?? CurtainWindow(frame: screen.frame)
            window.onSubmit = { [weak self] candidate in self?.unlock(candidate) }
            curtains[id] = window
            window.setFrame(screen.frame, display: true)
            window.contentView?.layoutSubtreeIfNeeded()
            window.mascots.show(activity)
            window.orderFrontRegardless()
            if mainWindow == nil { mainWindow = window }
        }
        for id in Set(curtains.keys).subtracting(current) {
            let removed = curtains.removeValue(forKey: id)
            removed?.mascots.show(AgentActivity())
            removed?.close()
        }
        if !curtains.values.contains(where: { $0.isKeyWindow }) {
            mainWindow?.makeKeyAndOrderFront(nil)
            mainWindow?.clearEntry()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard password != nil else { return }
        // A foreground switch must not leave ordinary typing directed to an exposed app.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.password != nil, !NSApp.isActive,
                  NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.loginwindow" else { return }
            NSApp.activate()
        }
    }

    private func unlock(_ candidate: String) {
        guard let result = password?.check(candidate) else { return }
        let hint: String
        switch result {
        case .accepted:
            activityTimer?.cancel()
            activityTimer = nil
            password = nil
            NSApp.presentationOptions = savedPresentation
            for window in curtains.values { window.close() }
            curtains.removeAll()
            NSApp.terminate(nil)
            return
        case .rejected: hint = "Incorrect password. Try again."
        case .wait(let seconds): hint = "Try again in \(seconds) s"
        }
        for window in curtains.values { window.passwordField.placeholderString = hint }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === setup, password == nil { NSApp.terminate(nil) }
    }
}
