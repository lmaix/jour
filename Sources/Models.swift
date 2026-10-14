import Foundation

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
    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    /// "Today", "Tomorrow", else "mer. 23 sept."
    static func relativeDay(_ d: Date, now: Date = Date(), calendarSystem cal: Calendar = .current, locale: Locale = .current) -> String {
        if cal.isDate(d, inSameDayAs: now) { return "Today" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return "Tomorrow" }
        let f = DateFormatter(); f.locale = locale; f.setLocalizedDateFormatFromTemplate("EEEdMMM"); return f.string(from: d)
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
