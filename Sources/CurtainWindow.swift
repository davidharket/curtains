import AppKit

private final class CurtainBackground: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
    }
}

private final class UnlockCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.drawingRect(forBounds: rect)
        textRect.size.width = max(0, textRect.width - 30)
        return textRect
    }
}

private final class UnlockField: NSSecureTextField {
    override class var cellClass: AnyClass? {
        get { UnlockCell.self }
        set { super.cellClass = newValue }
    }
}

final class CurtainWindow: NSWindow {
    let passwordField: NSSecureTextField = UnlockField()
    private let unlockButton = NSButton()
    let mascots = MascotWalk()
    private var idleTimer: Timer?
    var onSubmit: ((String) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isRestorable = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .white
        appearance = NSAppearance(named: .aqua)
        hasShadow = false
        let surface = CurtainBackground(frame: NSRect(origin: .zero, size: frame.size))
        contentView = surface
        passwordField.placeholderString = "Curtain password"
        passwordField.setAccessibilityLabel("Curtain password. Press Return to unlock.")
        passwordField.controlSize = .large
        passwordField.font = .systemFont(ofSize: 16)
        passwordField.isBezeled = true
        passwordField.bezelStyle = .roundedBezel
        passwordField.drawsBackground = true
        passwordField.backgroundColor = .white
        passwordField.textColor = .black
        passwordField.alignment = .left
        passwordField.cell?.sendsActionOnEndEditing = false
        passwordField.target = self
        passwordField.action = #selector(submit)
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(passwordField)
        unlockButton.image = NSImage(systemSymbolName: "arrow.right.square.fill", accessibilityDescription: nil)
        unlockButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        unlockButton.imagePosition = .imageOnly
        unlockButton.isBordered = false
        unlockButton.contentTintColor = .secondaryLabelColor
        unlockButton.setAccessibilityLabel("Unlock curtain")
        unlockButton.target = self
        unlockButton.action = #selector(submit)
        unlockButton.isHidden = true
        unlockButton.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(unlockButton)
        mascots.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(mascots)
        NSLayoutConstraint.activate([
            mascots.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            mascots.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            mascots.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            mascots.heightAnchor.constraint(equalToConstant: 94),
            passwordField.centerXAnchor.constraint(equalTo: surface.centerXAnchor),
            passwordField.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            passwordField.widthAnchor.constraint(equalToConstant: 260),
            unlockButton.trailingAnchor.constraint(equalTo: passwordField.trailingAnchor, constant: -4),
            unlockButton.centerYAnchor.constraint(equalTo: passwordField.centerYAnchor),
            unlockButton.widthAnchor.constraint(equalToConstant: 24),
            unlockButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        initialFirstResponder = nil
        // Keep secure keyboard entry confined to the time someone is typing.
        autorecalculatesKeyViewLoop = false
        NotificationCenter.default.addObserver(self, selector: #selector(entryEdited),
            name: NSControl.textDidBeginEditingNotification, object: passwordField)
        NotificationCenter.default.addObserver(self, selector: #selector(entryEdited),
            name: NSControl.textDidChangeNotification, object: passwordField)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { clearEntry(); return }
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              event.characters?.isEmpty == false,
              makeFirstResponder(passwordField),
              let editor = passwordField.currentEditor() else { return }
        editor.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func resignKey() {
        super.resignKey()
        clearEntry()
    }

    func clearEntry() {
        idleTimer?.invalidate()
        idleTimer = nil
        passwordField.abortEditing()
        passwordField.stringValue = ""
        unlockButton.isHidden = true
        makeFirstResponder(self)
    }

    @objc private func entryEdited() {
        unlockButton.isHidden = passwordField.stringValue.isEmpty
        idleTimer?.invalidate()
        idleTimer = .scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearEntry() }
        }
    }

    @objc private func submit() {
        let candidate = passwordField.stringValue
        clearEntry()
        onSubmit?(candidate)
    }
}
