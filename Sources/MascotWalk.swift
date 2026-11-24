import AppKit
import QuartzCore

final class MascotWalk: NSView {
    private var display: CADisplayLink?
    private var pets: [String: PetMotion] = [:]
    private var previousTick: Double = 0
    private var bubbleAt: Double = 0
    private var speakerIndex = 0
    private var activity = AgentActivity()
    private static let claudeIcon: NSImage? = {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
        else { return nil }
        return workspace.icon(forFile: url.path)
    }()

    private static let codexIcon: NSImage? = {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex")
        else { return nil }
        // The unified desktop app includes a separate icon for its Codex surface.
        if let asset = Bundle(url: url)?.url(forResource: "icon-codex-light", withExtension: "png"),
           let icon = NSImage(contentsOf: asset) { return icon }
        if url.deletingPathExtension().lastPathComponent == "Codex" {
            return workspace.icon(forFile: url.path)
        }
        return nil
    }()

    // Optional private eight-frame strips; the app bundle contains no character artwork.
    private static func frames(for name: String) -> [NSImage] {
        let file = URL.applicationSupportDirectory
            .appending(path: "Skjermgardin/Characters").appending(path: name + ".png")
        guard let sheet = NSImage(contentsOf: file),
              let atlas = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil),
              atlas.width >= 8, atlas.width.isMultiple(of: 8) else { return [] }
        let width = atlas.width / 8
        return (0..<8).compactMap { i in
            guard let cell = atlas.cropping(to: CGRect(x: i * width, y: 0, width: width, height: atlas.height))
            else { return nil }
            return NSImage(cgImage: cell, size: NSSize(width: width, height: atlas.height))
        }
    }
    private static let clawd = frames(for: "Claude")
    private static let codexPet = frames(for: "Codex")
    private static let codexLeft = frames(for: "Codex-left")
    private var reducedMotion = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ next: AgentActivity) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard activity != next || reducedMotion != reduce else { return }
        activity = next
        reducedMotion = reduce
        let agents = next.agents
        let liveIDs = Set(agents.map(\.id))
        pets = pets.filter { liveIDs.contains($0.key) }
        for (i, agent) in agents.enumerated() where pets[agent.id] == nil {
            pets[agent.id] = PetMotion(position: (CGFloat(i) + 0.5) * bounds.width / CGFloat(agents.count))
        }
        let active = !agents.isEmpty
        setAccessibilityElement(active)
        if active {
            let claude = agents.filter { $0.kind == .claude }.count
            setAccessibilityRole(.image)
            setAccessibilityLabel("\(claude) Claude and \(agents.count - claude) Codex working")
        }
        if active && !reduce {
            if display == nil {
                previousTick = CACurrentMediaTime()
                bubbleAt = previousTick + 2
                let link = displayLink(target: self, selector: #selector(tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                link.add(to: .main, forMode: .common)
                display = link
            }
        } else {
            display?.invalidate()
            display = nil
        }
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { show(AgentActivity()) }
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - previousTick, 0), 0.08)
        previousTick = now
        let size = petSize
        for agent in activity.agents {
            pets[agent.id]?.advance(seconds: dt, width: bounds.width, side: size)
        }
        if now > bubbleAt + 3 {
            speakerIndex += 1
            bubbleAt = now + .random(in: 5...10)
        }
        needsDisplay = true
    }

    private var petSize: CGFloat {
        min(48, bounds.width * 0.88 / CGFloat(max(activity.agents.count, 1)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let agents = activity.agents
        guard !agents.isEmpty, bounds.width > 0 else { return }
        let side = petSize
        var bubble: (String, NSRect)?
        let now = CACurrentMediaTime()
        for (index, agent) in agents.enumerated() {
            guard let pet = pets[agent.id] else { continue }
            let claude = agent.kind == .claude
            let codexFrames = pet.facesLeft && !Self.codexLeft.isEmpty ? Self.codexLeft : Self.codexPet
            let strip = claude ? Self.clawd : codexFrames
            let image = strip.isEmpty ? (claude ? Self.claudeIcon : Self.codexIcon)
                : strip[Int(pet.stride) % strip.count]
            let rect = NSRect(x: pet.x - side / 2, y: pet.y, width: side, height: side)
            // Clawd has no lettering. Keep the Codex terminal symbol readable.
            let flipClawd = claude && pet.facesLeft && !strip.isEmpty
            if flipClawd {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: rect.midX * 2, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
                transform.concat()
            }
            drawCharacter(image, name: claude ? "Claude" : "Codex", in: rect)
            if flipClawd { NSGraphicsContext.restoreGraphicsState() }
            if !reducedMotion, index == speakerIndex % agents.count, now >= bubbleAt, now < bubbleAt + 3 {
                bubble = (agent.note, rect)
            }
        }
        if let (note, pet) = bubble { drawBubble(note, above: pet) }
    }

    private func drawBubble(_ text: String, above pet: NSRect) {
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.black
        ])
        let size = label.size()
        let w = ceil(size.width) + 14
        let x = round(max(2, min(pet.midX - w / 2, bounds.width - w - 2)))
        let box = NSRect(x: x, y: round(pet.maxY + 3), width: w, height: 21)
        let tip = round(max(box.minX + 5, min(pet.midX, box.maxX - 9)))
        NSColor.black.setFill()
        box.insetBy(dx: 2, dy: 0).fill()
        box.insetBy(dx: 0, dy: 2).fill()
        NSRect(x: tip, y: box.minY - 3, width: 7, height: 4).fill()
        NSRect(x: tip, y: box.minY - 5, width: 3, height: 3).fill()
        NSColor.white.setFill()
        box.insetBy(dx: 2, dy: 2).fill()
        NSRect(x: tip + 2, y: box.minY - 1, width: 3, height: 4).fill()
        label.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
    }

    private func drawCharacter(_ image: NSImage?, name: String, in rect: NSRect) {
        if let image {
            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.minY + 1,
                                  width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let label = NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.black
            ])
            label.draw(at: NSPoint(x: rect.midX - label.size().width / 2, y: rect.midY - label.size().height / 2))
        }
    }
}
