import AppKit
import IOKit.pwr_mgt

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate {
    private var setup: NSWindow?
    private enum Mode { case create, ready, change, unavailable }
    private let store: PasswordStore
    private var mode = Mode.create
    private var saved: SessionPassword?
    private let current = NSSecureTextField()
    private let heading = NSTextField(labelWithString: "")
    private let primary = NSButton()
    private let headerActionButton = NSButton()
    private let setupPassword = NSSecureTextField()
    private let confirmation = NSSecureTextField()
    private let message = NSTextField(wrappingLabelWithString: "")
    init(store: PasswordStore = PasswordStore()) {
        self.store = store
        super.init()
    }
    private var password: SessionPassword?
    private var curtains: [NSNumber: CurtainWindow] = [:]
    private var savedPresentation: NSApplication.PresentationOptions = []
    private var activity = AgentActivity()
    private var idleSleepAssertion: IOPMAssertionID?
    private var activityTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 412, height: 268),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Curtains"
        window.delegate = self
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        setup = window

        let logo = NSImageView()
        logo.image = Bundle.main.url(forResource: "Skjermgardin", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.setAccessibilityElement(false)
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        message.font = .systemFont(ofSize: 13)
        message.textColor = .secondaryLabelColor
        setupPassword.placeholderString = "Password (8+ characters)"
        confirmation.placeholderString = "Confirm password"
        current.placeholderString = "Current password"
        for field in [current, setupPassword, confirmation] {
            field.setAccessibilityLabel(field.placeholderString)
            field.controlSize = .large
            field.font = .systemFont(ofSize: 15)
            field.bezelStyle = .roundedBezel
            field.alignment = .left
            field.delegate = self
            field.cell?.sendsActionOnEndEditing = false
            field.target = self
        }
        current.action = #selector(focusNewPassword)
        setupPassword.action = #selector(focusConfirmation)
        confirmation.action = #selector(savePassword)
        for button in [primary, headerActionButton] {
            button.bezelStyle = .rounded
            button.target = self
        }
        primary.action = #selector(primaryAction)
        headerActionButton.action = #selector(headerAction)
        primary.controlSize = .large
        let header = NSStackView(views: [logo, NSView(), headerActionButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        let footnote = NSTextField(wrappingLabelWithString: "Quitting the curtain reveals your desktop.")
        footnote.font = .systemFont(ofSize: 12)
        footnote.textColor = .secondaryLabelColor
        for label in [heading, message, footnote] { label.alignment = .left }
        let stack = NSStackView(views: [header, heading, message, current, setupPassword, confirmation, primary, footnote])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.setCustomSpacing(4, after: header)
        stack.setCustomSpacing(6, after: heading)
        stack.setCustomSpacing(12, after: message)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = window.contentView!
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 144),
            primary.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            logo.widthAnchor.constraint(equalToConstant: 40),
            logo.heightAnchor.constraint(equalTo: logo.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ] + [message, current, setupPassword, confirmation, footnote].map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
        reload()
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            let y = max(area.minY, area.midY - window.frame.height / 2)
            window.setFrameOrigin(NSPoint(x: round(area.midX - window.frame.width / 2), y: round(y)))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func reload() {
        do {
            saved = try store.load()
            show(saved == nil ? .create : .ready)
        } catch {
            show(.unavailable)
        }
    }

    private func show(_ newMode: Mode) {
        mode = newMode
        for field in [current, setupPassword, confirmation] {
            field.abortEditing()
            field.stringValue = ""
        }
        let editing = mode == .create || mode == .change
        current.isHidden = mode != .change
        setupPassword.isHidden = !editing
        confirmation.isHidden = !editing
        headerActionButton.isHidden = mode == .unavailable
        headerActionButton.title = editing ? "Save Password" : "Change Password"
        primary.isHidden = mode == .create
        primary.isBordered = mode != .ready
        primary.wantsLayer = true
        primary.layer?.cornerRadius = 6
        primary.layer?.backgroundColor = mode == .ready ? NSColor.systemBlue.cgColor : nil
        primary.contentTintColor = mode == .ready ? .white : nil
        primary.keyEquivalent = mode == .ready ? "\r" : ""
        message.textColor = .secondaryLabelColor
        let height: CGFloat
        switch mode {
        case .create:
            heading.stringValue = "Set a password"
            message.stringValue = "Choose a password to lift the curtain when you return."
            height = 258
        case .ready:
            heading.stringValue = "Ready to draw the curtain?"
            message.stringValue = "Your password is saved on this Mac."
            primary.title = "Activate Curtains"
            height = 218
        case .change:
            heading.stringValue = "Change password"
            message.stringValue = "Enter your current password and choose a new one."
            primary.title = "Cancel"
            height = 326
        case .unavailable:
            heading.stringValue = "Password unavailable"
            message.stringValue = "Curtains couldn’t read the saved password on this Mac."
            primary.title = "Try Again"
            height = 218
        }
        if mode == .ready {
            primary.attributedTitle = NSAttributedString(string: primary.title, attributes: [
                .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ])
        }
        setupPassword.placeholderString = mode == .change ? "New password (8+ characters)" : "Password (8+ characters)"
        setupPassword.setAccessibilityLabel(setupPassword.placeholderString)
        updateSaveButton()
        setup?.setContentSize(NSSize(width: 412, height: height))
        let focus: NSView = editing ? (mode == .change ? current : setupPassword) : primary
        setup?.initialFirstResponder = focus
        setup?.makeFirstResponder(focus)
    }

    private func updateSaveButton() {
        headerActionButton.isEnabled = (mode != .create && mode != .change) ||
            (setupPassword.stringValue.count >= 8 && setupPassword.stringValue == confirmation.stringValue &&
             (mode != .change || !current.stringValue.isEmpty))
    }

    func controlTextDidChange(_ notification: Notification) { updateSaveButton() }

    @objc private func focusNewPassword() { setup?.makeFirstResponder(setupPassword) }
    @objc private func focusConfirmation() { setup?.makeFirstResponder(confirmation) }

    @objc private func primaryAction() {
        switch mode {
        case .create: break
        case .change: reload()
        case .ready: activateCurtains()
        case .unavailable: reload()
        }
    }

    @objc private func headerAction() {
        if mode == .ready { show(.change) }
        else { savePassword() }
    }

    private func showError(_ text: String) {
        message.textColor = .systemRed
        message.stringValue = text
    }

    @objc private func savePassword() {
        guard (mode == .create || mode == .change), headerActionButton.isEnabled else { return }
        if mode == .change {
            switch saved?.check(current.stringValue) {
            case .accepted: break
            case .wait(let seconds): showError("Try again in \(seconds) s."); return
            default: showError("The current password is incorrect."); return
            }
        }
        guard let secret = SessionPassword(setupPassword.stringValue) else {
            showError("Couldn’t save your password. Try again.")
            return
        }
        do {
            try store.save(secret, replacing: saved)
            saved = secret
            show(.ready)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            reload()
            showError("Your saved password changed in another window.")
        } catch {
            showError("Couldn’t save your password. Try again.")
        }
    }

    private func activateCurtains() {
        guard mode == .ready, password == nil, !NSScreen.screens.isEmpty else { return }
        do {
            guard let secret = try store.load() else { reload(); return }
            var assertion = IOPMAssertionID()
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Keeping this Mac awake while Curtains is active" as CFString, &assertion)
            guard status == kIOReturnSuccess else {
                showError("Couldn’t keep this Mac awake. Try activating Curtains again.")
                return
            }
            idleSleepAssertion = assertion
            password = secret
        } catch {
            show(.unavailable)
            return
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

    private func releaseIdleSleepAssertion() {
        guard let assertion = idleSleepAssertion else { return }
        IOPMAssertionRelease(assertion)
        idleSleepAssertion = nil
    }

    func applicationWillTerminate(_ notification: Notification) { releaseIdleSleepAssertion() }

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
            releaseIdleSleepAssertion()
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
