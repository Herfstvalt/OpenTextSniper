import Cocoa
import Carbon

// MARK: - Toast Style

enum ToastStyle {
    case success, info, error

    var backgroundColor: NSColor {
        switch self {
        case .success: return NSColor(red: 0.18, green: 0.72, blue: 0.36, alpha: 0.92)
        case .info:    return NSColor(white: 0.15, alpha: 0.88)
        case .error:   return NSColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 0.90)
        }
    }

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        checkScreenCapturePermission()

        ClipboardHistory.shared.load()
        HotkeyManager.shared.load()
        HotkeyManager.shared.installHandler()
        HotkeyManager.shared.register()

        NotificationCenter.default.addObserver(
            self, selector: #selector(captureText),
            name: .captureHotkey, object: nil
        )

        setupStatusBar()
    }

    // MARK: - Permission

    private func checkScreenCapturePermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let image = NSImage(
                systemSymbolName: "text.viewfinder",
                accessibilityDescription: "OpenTextSniper"
            )?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate — rebuild menu each time it opens

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Capture
        let hotkeyStr = HotkeyManager.shared.displayString()
        let captureItem = NSMenuItem(title: "Capture Text", action: #selector(captureText), keyEquivalent: "")
        captureItem.attributedTitle = attributedMenuItem(
            title: "Capture Text", shortcut: hotkeyStr
        )
        menu.addItem(captureItem)

        menu.addItem(.separator())

        // Clipboard History
        let historyCount = ClipboardHistory.shared.entries.count
        let historyTitle = historyCount > 0
            ? "Clipboard History (\(historyCount))"
            : "Clipboard History"
        menu.addItem(
            withTitle: historyTitle,
            action: #selector(showClipboardHistory), keyEquivalent: ""
        )
        if historyCount > 0 {
            menu.addItem(
                withTitle: "Clear History",
                action: #selector(clearHistory), keyEquivalent: ""
            )
        }

        menu.addItem(.separator())

        // Preferences
        menu.addItem(withTitle: "Change Hotkey...", action: #selector(changeHotkey), keyEquivalent: "")

        menu.addItem(.separator())

        // About & Quit
        menu.addItem(withTitle: "About OpenTextSniper", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Quit OpenTextSniper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func attributedMenuItem(title: String, shortcut: String) -> NSAttributedString {
        let full = NSMutableAttributedString()
        full.append(NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 14),
        ]))
        full.append(NSAttributedString(string: "  \(shortcut)", attributes: [
            .font: NSFont.menuFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return full
    }

    // MARK: - Actions

    @objc func captureText() {
        // Close the menu if open
        statusItem.menu?.cancelTracking()

        ScreenCapture.beginSelection { [weak self] image in
            guard let image = image else { return }
            OCREngine.recognizeText(in: image) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text) where !text.isEmpty:
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        ClipboardHistory.shared.add(text)
                        NSSound(named: "Tink")?.play()
                        self?.showToast("Copied to clipboard!", style: .success)
                    case .success:
                        self?.showToast("No text found", style: .info)
                    case .failure:
                        self?.showToast("OCR failed", style: .error)
                    }
                }
            }
        }
    }

    @objc private func showClipboardHistory() {
        ClipboardWindowController.shared.show()
    }

    @objc private func clearHistory() {
        ClipboardHistory.shared.clear()
    }

    @objc private func changeHotkey() {
        HotkeyManager.shared.showRecorder()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let credits = """
        A free, open-source screen OCR tool for macOS.

        Built because I needed a TextSniper but wanted something \
        free and open-source. The idea came directly from TextSniper \
        (textsniper.app) — full kudos to the app that inspired this project.

        github.com/Herfstvalt/OpenTextSniper
        """

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "OpenTextSniper",
            .applicationVersion: "1.0",
            .version: "1",
            .credits: NSAttributedString(
                string: credits,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            ),
        ])
    }

    // MARK: - Toast

    private func showToast(_ message: String, style: ToastStyle) {
        let width: CGFloat = 280
        let height: CGFloat = 48

        let toast = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        toast.backgroundColor = .clear
        toast.level = .floating
        toast.isOpaque = false
        toast.hasShadow = true

        // Rounded background view
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = style.backgroundColor.cgColor
        bg.layer?.cornerRadius = 14
        bg.layer?.masksToBounds = true
        toast.contentView?.addSubview(bg)

        // Icon
        let iconSize: CGFloat = 18
        let iconView = NSImageView(frame: NSRect(x: 14, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
        if let img = NSImage(systemSymbolName: style.iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = .white
        }
        bg.addSubview(iconView)

        // Label
        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.sizeToFit()
        label.frame = NSRect(
            x: 40, y: (height - label.frame.height) / 2,
            width: width - 54, height: label.frame.height
        )
        bg.addSubview(label)

        // Position: bottom center of main screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - width / 2
            let y = screen.frame.height * 0.22
            toast.setFrameOrigin(NSPoint(x: x, y: y - 10)) // start 10pt lower for slide-up
        }

        toast.alphaValue = 0
        toast.orderFront(nil)

        // Animate in: fade + slide up
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toast.animator().alphaValue = 1
            var origin = toast.frame.origin
            origin.y += 10
            toast.animator().setFrameOrigin(origin)
        }) {
            // Hold, then animate out
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    toast.animator().alphaValue = 0
                }) {
                    toast.orderOut(nil)
                }
            }
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let captureHotkey = Notification.Name("com.opentextsniper.captureHotkey")
}
