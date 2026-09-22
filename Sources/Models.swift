import Foundation

struct CalendarInfo: Equatable {
    let id: String
    let name: String
    let colorHex: String?
    let account: String
    let selected: Bool
}

struct CalendarEvent: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let calendarName: String
    let colorHex: String?
    let account: String
}

enum ParseError: Error, Equatable {
    case invalidJSON
    case apiError(String)
}

/// Pure parsing of Google Calendar API v3 responses.
enum GoogleParsing {
    /// Google's event colorId palette (events carry an id, calendars carry a hex).
    static let eventColors: [String: String] = [
        "1": "#7986cb", "2": "#33b679", "3": "#8e24aa", "4": "#e67c73", "5": "#f6bf26", "6": "#f4511e",
        "7": "#039be5", "8": "#616161", "9": "#3f51b5", "10": "#0b8043", "11": "#d50000",
    ]

    static func object(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.invalidJSON }
        if let err = obj["error"] as? [String: Any] {
            throw ParseError.apiError((err["message"] as? String) ?? "erreur \(err["code"] ?? "?")")
        }
        return obj
    }

    /// users/me/calendarList
    static func calendars(from data: Data, account: String) throws -> [CalendarInfo] {
        let obj = try object(data)
        return ((obj["items"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return CalendarInfo(id: id,
                                name: (item["summaryOverride"] as? String) ?? (item["summary"] as? String) ?? id,
                                colorHex: item["backgroundColor"] as? String,
                                account: account,
                                selected: (item["selected"] as? Bool) ?? false)
        }
    }

    /// calendars/{id}/events with singleEvents=true. Skips cancelled events and ones the user declined.
    static func events(from data: Data, calendar cal: CalendarInfo, calendarSystem: Calendar = .current) throws -> [CalendarEvent] {
        let obj = try object(data)
        return ((obj["items"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let id = item["id"] as? String, item["status"] as? String != "cancelled",
                  let s = item["start"] as? [String: Any], let e = item["end"] as? [String: Any],
                  let (start, allDay) = parseDate(s, calendarSystem: calendarSystem),
                  let (end, _) = parseDate(e, calendarSystem: calendarSystem) else { return nil }
            if let attendees = item["attendees"] as? [[String: Any]],
               attendees.contains(where: { ($0["self"] as? Bool) == true && ($0["responseStatus"] as? String) == "declined" }) {
                return nil
            }
            let color = (item["colorId"] as? String).flatMap { eventColors[$0] } ?? cal.colorHex
            return CalendarEvent(id: cal.id + "/" + id,
                                 title: (item["summary"] as? String) ?? "(Sans titre)",
                                 start: start, end: end, isAllDay: allDay,
                                 location: (item["location"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                 calendarName: cal.name, colorHex: color, account: cal.account)
        }
    }

    /// {"dateTime": "2026-09-22T12:30:00+02:00"} or {"date": "2026-09-22"} (all-day, local midnight).
    static func parseDate(_ obj: [String: Any], calendarSystem: Calendar) -> (Date, Bool)? {
        if let s = obj["dateTime"] as? String {
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let d = f1.date(from: s) ?? f2.date(from: s) { return (d, false) }
            return nil
        }
        if let s = obj["date"] as? String {
            let parts = s.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
            guard let d = calendarSystem.date(from: c) else { return nil }
            return (d, true)
        }
        return nil
    }
}

/// A 6×7 Monday-first grid for one month.
struct MonthGrid: Equatable {
    struct Cell: Equatable {
        let date: Date
        let inMonth: Bool
    }
    let month: Date
    let cells: [Cell]

    static func make(for anyDate: Date, calendarSystem: Calendar = .current) -> MonthGrid {
        var cal = calendarSystem
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.year, .month], from: anyDate)
        let first = cal.date(from: comps)!
        let weekday = cal.component(.weekday, from: first)           // 1 = Sunday … 7 = Saturday
        let offset = (weekday - cal.firstWeekday + 7) % 7               // days before `first` to show
        let gridStart = cal.date(byAdding: .day, value: -offset, to: first)!
        let cells = (0..<42).map { i -> Cell in
            let d = cal.date(byAdding: .day, value: i, to: gridStart)!
            return Cell(date: d, inMonth: cal.isDate(d, equalTo: first, toGranularity: .month))
        }
        return MonthGrid(month: first, cells: cells)
    }

    /// Range to fetch so every visible cell has its events.
    var visibleRange: (start: Date, end: Date) {
        (cells.first!.date, Calendar.current.date(byAdding: .day, value: 1, to: cells.last!.date)!)
    }
}

enum EventIndex {
    /// Events keyed by local start-of-day. Multi-day events appear on every day they cover (end is exclusive).
    static func byDay(_ events: [CalendarEvent], calendarSystem cal: Calendar = .current) -> [Date: [CalendarEvent]] {
        var out: [Date: [CalendarEvent]] = [:]
        for e in events {
            var day = cal.startOfDay(for: e.start)
            let lastInstant = e.end > e.start ? e.end.addingTimeInterval(-1) : e.start
            let lastDay = cal.startOfDay(for: lastInstant)
            while day <= lastDay {
                out[day, default: []].append(e)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        for k in out.keys {
            out[k]!.sort { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.start < b.start
            }
        }
        return out
    }
}

extension EventIndex {
    /// Next events from `now`: still in progress or starting later, earliest first. Deduplicated by id.
    static func upcoming(_ events: [CalendarEvent], now: Date = Date(), limit: Int = 5) -> [CalendarEvent] {
        var seen = Set<String>()
        return events
            .filter { $0.end > now && seen.insert($0.id).inserted }
            .sorted { a, b in a.start != b.start ? a.start < b.start : a.title < b.title }
            .prefix(limit)
            .map { $0 }
    }
}

enum Fmt {
    /// "Aujourd'hui", "Demain", else "mer. 23 sept."
    static func relativeDay(_ d: Date, now: Date = Date(), calendarSystem cal: Calendar = .current, locale: Locale = .current) -> String {
        if cal.isDate(d, inSameDayAs: now) { return "Aujourd'hui" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "Demain" }
        let f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate("EEEdMMM"); return f.string(from: d)
    }
    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    /// "mardi 22 septembre"
    static func dayTitle(_ d: Date, locale: Locale = .current) -> String {
        let f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate("EEEEdMMMM"); return f.string(from: d)
    }
    /// "septembre 2026"
    static func monthTitle(_ d: Date, locale: Locale = .current) -> String {
        let f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate("MMMMyyyy"); return f.string(from: d)
    }
    /// Monday-first short weekday symbols: ["lun.", "mar.", …]
    static func weekdaySymbols(locale: Locale = .current) -> [String] {
        let f = DateFormatter(); f.locale = locale
        let s = f.shortWeekdaySymbols ?? []
        guard s.count == 7 else { return s }
        return Array(s[1...6]) + [s[0]]
    }
}
