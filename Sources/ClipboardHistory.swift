import Foundation

class ClipboardHistory {
    static let shared = ClipboardHistory()
    static let didChangeNotification = Notification.Name("ClipboardHistoryDidChange")

    struct Entry: Codable, Identifiable {
        let id: UUID
        let text: String
        let timestamp: Date

        init(text: String) {
            self.id = UUID()
            self.text = text
            self.timestamp = Date()
        }

        var menuTitle: String {
            let cleaned = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)
            let truncated = cleaned.count > 60 ? String(cleaned.prefix(60)) + "..." : cleaned
            return "\(relativeTime)  \(truncated)"
        }

        var relativeTime: String {
            let interval = Date().timeIntervalSince(timestamp)
            if interval < 60 { return "just now" }
            if interval < 3600 { return "\(Int(interval / 60))m ago" }
            if interval < 86400 { return "\(Int(interval / 3600))h ago" }
            if interval < 604800 { return "\(Int(interval / 86400))d ago" }
            let fmt = DateFormatter()
            fmt.dateStyle = .short
            return fmt.string(from: timestamp)
        }
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 50
    private let maxTextLength = 10_000
    private let storageKey = "clipboardHistory"

    private init() {}

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        entries = decoded
    }

    func add(_ text: String) {
        let trimmed = text.count > maxTextLength ? String(text.prefix(maxTextLength)) : text
        let entry = Entry(text: trimmed)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func remove(at index: Int) {
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func clear() {
        entries.removeAll()
        save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
