import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()
    static let didChangeNotification = Notification.Name("HotkeyDidChange")

    private var hotkeyRef: EventHotKeyRef?
    private(set) var keyCode: UInt32 = 19       // '2'
    private(set) var modifiers: UInt32 = 0      // cmdKey | shiftKey

    private let keyCodeKey = "hotkeyKeyCode"
    private let modifiersKey = "hotkeyModifiers"

    private init() {
        modifiers = UInt32(cmdKey | shiftKey)
    }

    // MARK: - Persistence

    func load() {
        if UserDefaults.standard.object(forKey: keyCodeKey) != nil {
            keyCode = UInt32(UserDefaults.standard.integer(forKey: keyCodeKey))
            modifiers = UInt32(UserDefaults.standard.integer(forKey: modifiersKey))
        }
    }

    private func saveToDefaults() {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey)
    }

    // MARK: - Registration

    func register() {
        unregister()

        let hotKeyID = EventHotKeyID(signature: 0x54535052, id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        hotkeyRef = ref
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { (_, _, _) -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .captureHotkey, object: nil)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        saveToDefaults()
        register()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    // MARK: - Display String

    func displayString() -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }
        if modifiers & UInt32(optionKey) != 0  { parts.append("\u{2325}") }
        if modifiers & UInt32(shiftKey) != 0   { parts.append("\u{21E7}") }
        if modifiers & UInt32(cmdKey) != 0     { parts.append("\u{2318}") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            // F-keys
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            118: "F4", 120: "F2", 122: "F1",
            // Special
            36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        ]
        return map[code] ?? "Key\(code)"
    }

    // MARK: - Hotkey Recorder

    func showRecorder() {
        unregister()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Hotkey"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.center()

        let container = NSView(frame: panel.contentView!.bounds)
        container.autoresizingMask = [.width, .height]

        let label = NSTextField(labelWithString: "Press your new shortcut...")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 55, width: 280, height: 30)
        label.autoresizingMask = [.width]
        container.addSubview(label)

        let hint = NSTextField(labelWithString: "Must include \u{2318}, \u{2303}, or \u{2325}")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 20, y: 35, width: 280, height: 18)
        hint.autoresizingMask = [.width]
        container.addSubview(hint)

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.frame = NSRect(x: 115, y: 8, width: 90, height: 24)
        cancelButton.bezelStyle = .rounded
        container.addSubview(cancelButton)

        panel.contentView = container

        var monitor: Any?
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = mods.contains(.command) || mods.contains(.control) || mods.contains(.option)

            guard hasModifier else {
                // Flash the hint red briefly
                hint.textColor = .systemRed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    hint.textColor = .secondaryLabelColor
                }
                return nil
            }

            // Convert NSEvent modifiers to Carbon modifiers
            var carbonMods: UInt32 = 0
            if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if mods.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
            if mods.contains(.option)  { carbonMods |= UInt32(optionKey) }
            if mods.contains(.control) { carbonMods |= UInt32(controlKey) }

            self.update(keyCode: UInt32(event.keyCode), modifiers: carbonMods)

            if let m = monitor { NSEvent.removeMonitor(m) }
            panel.close()
            NSSound(named: "Tink")?.play()
            return nil
        }

        cancelButton.target = panel
        cancelButton.action = #selector(NSPanel.close)

        // Re-register old hotkey when panel closes without selection
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            if let m = monitor { NSEvent.removeMonitor(m) }
            self?.register()
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
