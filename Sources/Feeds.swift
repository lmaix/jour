import Foundation
import Security

/// One iCal subscription: Google's "secret address in iCal format" (or any .ics URL).
struct Feed: Codable, Equatable, Identifiable {
    var id: String { url }
    var name: String
    var url: String
    var colorHex: String

    /// For a Google secret address the calendar id (often the account email) sits in the path:
    /// https://calendar.google.com/calendar/ical/<id>/private-…/basic.ics
    var ownerEmail: String? {
        guard let u = URL(string: url), u.host?.contains("google") == true else { return nil }
        let parts = u.pathComponents
        guard let i = parts.firstIndex(of: "ical"), i + 1 < parts.count else { return nil }
        let id = parts[i + 1].removingPercentEncoding ?? parts[i + 1]
        return id.contains("@") ? id.lowercased() : nil
    }
}

/// Named colors offered in the "add calendar" dialog, mapped to macOS system colors.
enum FeedColor: String, CaseIterable {
    case blue = "Bleu", green = "Vert", red = "Rouge", orange = "Orange", yellow = "Jaune", purple = "Violet", pink = "Rose", teal = "Turquoise", gray = "Gris"

    var hex: String {
        switch self {
        case .blue: return "#0a84ff"
        case .green: return "#30d158"
        case .red: return "#ff453a"
        case .orange: return "#ff9f0a"
        case .yellow: return "#ffd60a"
        case .purple: return "#bf5af2"
        case .pink: return "#ff375f"
        case .teal: return "#64d2ff"
        case .gray: return "#8e8e93"
        }
    }
}

/// All feeds live in one Keychain item (the URLs are secrets).
enum FeedStore {
    // Nom historique de l'app : le changer perdrait les agendas déjà enregistrés dans le Trousseau.
    static let service = "ClaudeCalendarBar"
    static let account = "feeds"

    static func load() -> [Feed] {
        guard let d = read(), let feeds = try? JSONDecoder().decode([Feed].self, from: d) else { return [] }
        return feeds
    }

    @discardableResult
    static func save(_ feeds: [Feed]) -> Bool {
        guard let d = try? JSONEncoder().encode(feeds) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let st = SecItemUpdate(base as CFDictionary, [kSecValueData as String: d] as CFDictionary)
        if st == errSecSuccess { return true }
        guard st == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = d
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func add(_ feed: Feed) -> Bool {
        var feeds = load().filter { $0.url != feed.url }
        feeds.append(feed)
        return save(feeds)
    }

    static func remove(url: String) {
        save(load().filter { $0.url != url })
    }

    private static func read() -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess else { return nil }
        return r as? Data
    }
}

/// Downloads every feed and expands it over a date range.
final class FeedFetcher {
    struct Result {
        var events: [CalendarEvent] = []
        var errors: [String] = []
    }

    func fetch(_ feeds: [Feed], from: Date, to: Date, completion: @escaping (Result) -> Void) {
        let group = DispatchGroup()
        var result = Result()
        let lock = NSLock()
        for feed in feeds {
            guard let url = URL(string: feed.url) else { result.errors.append("\(feed.name) : URL invalide"); continue }
            group.enter()
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            req.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: req) { data, resp, err in
                defer { group.leave() }
                lock.lock(); defer { lock.unlock() }
                if let err = err { result.errors.append("\(feed.name) : \(err.localizedDescription)"); return }
                guard let http = resp as? HTTPURLResponse, let data = data else { result.errors.append("\(feed.name) : réponse vide"); return }
                guard (200..<300).contains(http.statusCode) else { result.errors.append("\(feed.name) : HTTP \(http.statusCode)"); return }
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    result.errors.append("\(feed.name) : encodage illisible"); return
                }
                let parsed = ICS.parse(text)
                guard !parsed.events.isEmpty || text.contains("BEGIN:VCALENDAR") else { result.errors.append("\(feed.name) : pas un fichier iCal"); return }
                let name = feed.name.isEmpty ? (parsed.name ?? "Agenda") : feed.name
                result.events += ICS.occurrences(of: parsed, from: from, to: to, calendarName: name, colorHex: feed.colorHex,
                                                 account: feed.url, selfEmail: feed.ownerEmail)
            }.resume()
        }
        group.notify(queue: .main) { completion(result) }
    }
}
