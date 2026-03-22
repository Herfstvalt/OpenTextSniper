import Cocoa
import ScreenCaptureKit

// MARK: - Overlay Window

class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Screen Capture Controller

class ScreenCapture {
    private static var overlayWindows: [NSWindow] = []
    private static var completion: ((CGImage?) -> Void)?
    private static var escapeMonitor: Any?
    private static var isActive = false

    static func beginSelection(completion: @escaping (CGImage?) -> Void) {
        guard !isActive else { return }
        isActive = true
        self.completion = completion

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .init(Int(CGWindowLevelForKey(.maximumWindow)))
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            window.contentView = view

            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                endSelection(rect: nil)
                return nil
            }
            return event
        }
    }

    static func endSelection(rect: NSRect?) {
        guard isActive else { return }
        isActive = false

        NSCursor.arrow.set()

        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        let windows = overlayWindows
        overlayWindows = []
        for window in windows { window.orderOut(nil) }

        guard let rect = rect, rect.width > 5, rect.height > 5 else {
            completion?(nil)
            completion = nil
            return
        }

        let primaryHeight = NSScreen.screens[0].frame.height
        let cgRect = CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        let captureCompletion = completion
        completion = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Task {
                let image = await captureScreen(rect: cgRect)
                await MainActor.run { captureCompletion?(image) }
            }
        }
    }

    private static func captureScreen(rect: CGRect) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            let center = CGPoint(x: rect.midX, y: rect.midY)
            guard let display = content.displays.first(where: { $0.frame.contains(center) })
                ?? content.displays.first else { return nil }

            let localRect = CGRect(
                x: rect.origin.x - display.frame.origin.x,
                y: rect.origin.y - display.frame.origin.y,
                width: rect.width,
                height: rect.height
            )

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = localRect
            config.width = Int(localRect.width * 2)
            config.height = Int(localRect.height * 2)
            config.scalesToFit = true
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Selection View (no full-screen dimming — just crosshair + selection rect)

class SelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Near-invisible fill so the window stays hit-testable
        NSColor.black.withAlphaComponent(0.005).setFill()
        bounds.fill()

        guard let start = startPoint, let current = currentPoint else { return }

        let sel = rectFrom(start, current)
        guard sel.width > 1, sel.height > 1 else { return }

        // Light blue tint inside selection
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: sel).fill()

        // White border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()

        // Blue dashed inner border
        NSColor.systemBlue.withAlphaComponent(0.8).setStroke()
        let inner = NSBezierPath(rect: sel.insetBy(dx: 1, dy: 1))
        inner.lineWidth = 1
        inner.setLineDash([6, 4], count: 2, phase: 0)
        inner.stroke()

        drawSizeLabel(for: sel)
    }

    private func drawSizeLabel(for rect: NSRect) {
        let text = "\(Int(rect.width)) \u{00D7} \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let bg = NSRect(
            x: rect.midX - size.width / 2 - 6,
            y: rect.minY - size.height - 10,
            width: size.width + 12,
            height: size.height + 4
        )

        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(
            at: NSPoint(x: bg.minX + 6, y: bg.minY + 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let start = startPoint, let end = currentPoint, let window = self.window else {
            ScreenCapture.endSelection(rect: nil)
            return
        }

        let viewRect = rectFrom(start, end)
        let windowRect = convert(viewRect, to: nil)
        let screenRect = window.convertToScreen(windowRect)
        ScreenCapture.endSelection(rect: screenRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        ScreenCapture.endSelection(rect: nil)
    }

    private func rectFrom(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x), y: min(a.y, b.y),
            width: abs(b.x - a.x), height: abs(b.y - a.y)
        )
    }
}
