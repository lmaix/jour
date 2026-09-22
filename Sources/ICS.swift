import Foundation

/// Minimal iCalendar (RFC 5545) reader: VEVENTs with recurrence expansion. Pure, testable.
enum ICS {
    struct Property {
        let name: String
        let params: [String: String]
        let value: String
    }

    struct VEvent {
        var uid = ""
        var summary: String?
        var location: String?
        var status: String?
        var start: Date?
        var end: Date?
        var isAllDay = false
        var timeZone: TimeZone = .current
        var rrule: [String: String]?
        var exdates: [Date] = []
        var recurrenceID: Date?
        var declinedBy: [String] = []          // mailto addresses with PARTSTAT=DECLINED
    }

    struct Feed {
        var name: String?
        var events: [VEvent] = []
    }

    // MARK: - Parsing

    /// Unfolds continuation lines and splits "NAME;P=V:value".
    static func properties(_ text: String) -> [Property] {
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        return unfolded.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            // Find the first ':' that is not inside a quoted parameter value.
            var inQuotes = false
            var colon: String.Index? = nil
            for i in line.indices {
                let c = line[i]
                if c == "\"" { inQuotes.toggle() }
                else if c == ":" && !inQuotes { colon = i; break }
            }
            guard let ci = colon else { return nil }
            let head = line[line.startIndex..<ci]
            let value = String(line[line.index(after: ci)...])
            let parts = head.split(separator: ";")
            guard let name = parts.first else { return nil }
            var params: [String: String] = [:]
            for p in parts.dropFirst() {
                if let eq = p.firstIndex(of: "=") {
                    params[String(p[p.startIndex..<eq]).uppercased()] = String(p[p.index(after: eq)...]).replacingOccurrences(of: "\"", with: "")
                }
            }
            return Property(name: String(name).uppercased(), params: params, value: value)
        }
    }

    static func parse(_ text: String) -> Feed {
        var feed = Feed()
        var current: VEvent? = nil
        for p in properties(text) {
            switch p.name {
            case "X-WR-CALNAME": feed.name = unescape(p.value)
            case "BEGIN" where p.value.uppercased() == "VEVENT": current = VEvent()
            case "END" where p.value.uppercased() == "VEVENT":
                if let e = current, e.start != nil, !e.uid.isEmpty { feed.events.append(e) }
                current = nil
            default:
                guard current != nil else { continue }
                apply(p, to: &current!)
            }
        }
        return feed
    }

    private static func apply(_ p: Property, to e: inout VEvent) {
        switch p.name {
        case "UID": e.uid = p.value
        case "SUMMARY": e.summary = unescape(p.value)
        case "LOCATION": e.location = unescape(p.value)
        case "STATUS": e.status = p.value.uppercased()
        case "DTSTART":
            if let (d, allDay, tz) = parseDate(p) { e.start = d; e.isAllDay = allDay; e.timeZone = tz }
        case "DTEND":
            if let (d, _, _) = parseDate(p) { e.end = d }
        case "DURATION":
            if let s = e.start, e.end == nil, let secs = parseDuration(p.value) { e.end = s.addingTimeInterval(secs) }
        case "RRULE":
            var r: [String: String] = [:]
            for part in p.value.split(separator: ";") {
                if let eq = part.firstIndex(of: "=") { r[String(part[part.startIndex..<eq]).uppercased()] = String(part[part.index(after: eq)...]).uppercased() }
            }
            e.rrule = r
        case "EXDATE":
            for v in p.value.split(separator: ",") {
                if let (d, _, _) = parseDate(Property(name: "EXDATE", params: p.params, value: String(v))) { e.exdates.append(d) }
            }
        case "RECURRENCE-ID":
            if let (d, _, _) = parseDate(p) { e.recurrenceID = d }
        case "ATTENDEE":
            if p.params["PARTSTAT"]?.uppercased() == "DECLINED" {
                e.declinedBy.append(p.value.lowercased().replacingOccurrences(of: "mailto:", with: ""))
            }
        default: break
        }
    }

    /// DTSTART;TZID=Europe/Paris:20260922T123000 · DTSTART:20260922T103000Z · DTSTART;VALUE=DATE:20260922
    static func parseDate(_ p: Property, defaultZone: TimeZone = .current) -> (Date, Bool, TimeZone)? {
        let v = p.value.trimmingCharacters(in: .whitespaces)
        var tz = defaultZone
        if let id = p.params["TZID"], let z = TimeZone(identifier: id) ?? windowsZone(id) { tz = z }
        let allDay = p.params["VALUE"]?.uppercased() == "DATE" || (v.count == 8 && !v.contains("T"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = allDay ? defaultZone : (v.hasSuffix("Z") ? TimeZone(identifier: "UTC")! : tz)
        let digits = v.filter { $0.isNumber }
        guard digits.count >= 8, let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)), let d = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        var c = DateComponents(year: y, month: m, day: d)
        if !allDay, digits.count >= 14 {
            c.hour = Int(digits.dropFirst(8).prefix(2)); c.minute = Int(digits.dropFirst(10).prefix(2)); c.second = Int(digits.dropFirst(12).prefix(2))
        }
        guard let date = cal.date(from: c) else { return nil }
        return (date, allDay, v.hasSuffix("Z") ? defaultZone : tz)
    }

    private static func windowsZone(_ id: String) -> TimeZone? {
        let map = ["Romance Standard Time": "Europe/Paris", "W. Europe Standard Time": "Europe/Berlin", "GMT Standard Time": "Europe/London",
                   "Eastern Standard Time": "America/New_York", "Pacific Standard Time": "America/Los_Angeles", "Central European Standard Time": "Europe/Warsaw"]
        return map[id].flatMap { TimeZone(identifier: $0) }
    }

    /// PT1H30M, P1D, PT45M
    static func parseDuration(_ s: String) -> TimeInterval? {
        var total: TimeInterval = 0, num = "", inTime = false
        let sign: TimeInterval = s.hasPrefix("-") ? -1 : 1
        for c in s.uppercased() where c != "P" && c != "-" && c != "+" {
            if c.isNumber { num.append(c); continue }
            if c == "T" { inTime = true; continue }
            guard let n = Double(num) else { return nil }
            num = ""
            switch c {
            case "W": total += n * 604800
            case "D": total += n * 86400
            case "H": total += n * 3600
            case "M": total += inTime ? n * 60 : 0
            case "S": total += n
            default: return nil
            }
        }
        return total * sign
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Expansion

    /// Concrete occurrences of every event within [from, to), with EXDATE and RECURRENCE-ID overrides applied.
    static func occurrences(of feed: Feed, from: Date, to: Date, calendarName: String, colorHex: String?, account: String, selfEmail: String? = nil) -> [CalendarEvent] {
        let overrides = Dictionary(grouping: feed.events.filter { $0.recurrenceID != nil }, by: \.uid)
        var out: [CalendarEvent] = []
        for e in feed.events where e.recurrenceID == nil {
            guard let start = e.start else { continue }
            let end = e.end ?? (e.isAllDay ? start.addingTimeInterval(86400) : start)
            let duration = end.timeIntervalSince(start)
            let overridden = Set((overrides[e.uid] ?? []).compactMap(\.recurrenceID))
            for occStart in expand(e, from: from, to: to) {
                if e.exdates.contains(where: { sameInstant($0, occStart, allDay: e.isAllDay) }) { continue }
                if overridden.contains(where: { sameInstant($0, occStart, allDay: e.isAllDay) }) { continue }
                out.append(make(e, start: occStart, end: occStart.addingTimeInterval(duration), calendarName: calendarName, colorHex: colorHex, account: account))
            }
        }
        for (_, list) in overrides {
            for o in list {
                guard let s = o.start, s < to else { continue }
                let end = o.end ?? (o.isAllDay ? s.addingTimeInterval(86400) : s)
                guard end > from else { continue }
                out.append(make(o, start: s, end: end, calendarName: calendarName, colorHex: colorHex, account: account))
            }
        }
        return out.filter { ev in
            guard let e = feed.events.first(where: { $0.uid == ev.id.split(separator: "@@").first.map(String.init) }) else { return true }
            if e.status == "CANCELLED" { return false }
            if let me = selfEmail?.lowercased(), e.declinedBy.contains(me) { return false }
            return true
        }
    }

    private static func make(_ e: VEvent, start: Date, end: Date, calendarName: String, colorHex: String?, account: String) -> CalendarEvent {
        CalendarEvent(id: "\(e.uid)@@\(Int(start.timeIntervalSince1970))", title: e.summary?.isEmpty == false ? e.summary! : "(Sans titre)",
                      start: start, end: end, isAllDay: e.isAllDay,
                      location: e.location.flatMap { $0.isEmpty ? nil : $0 },
                      calendarName: calendarName, colorHex: colorHex, account: account)
    }

    private static func sameInstant(_ a: Date, _ b: Date, allDay: Bool) -> Bool {
        allDay ? Calendar.current.isDate(a, inSameDayAs: b) : abs(a.timeIntervalSince(b)) < 1
    }

    /// Occurrence start dates of `e` inside [from, to). Non-recurring events yield their own start if they overlap.
    static func expand(_ e: VEvent, from: Date, to: Date, maxIterations: Int = 5000) -> [Date] {
        guard let start = e.start else { return [] }
        let end = e.end ?? (e.isAllDay ? start.addingTimeInterval(86400) : start)
        let duration = max(end.timeIntervalSince(start), 0)
        guard let rule = e.rrule, let freq = rule["FREQ"] else {
            return (start < to && end > from) || (duration == 0 && start >= from && start < to) ? [start] : []
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = e.isAllDay ? .current : e.timeZone
        cal.firstWeekday = 2
        let interval = max(Int(rule["INTERVAL"] ?? "1") ?? 1, 1)
        let count = rule["COUNT"].flatMap { Int($0) }
        let until = rule["UNTIL"].flatMap { parseDate(Property(name: "UNTIL", params: [:], value: $0), defaultZone: cal.timeZone)?.0 }
        let byDay = rule["BYDAY"].map { $0.split(separator: ",").map(String.init) } ?? []
        let byMonthDay = rule["BYMONTHDAY"].map { $0.split(separator: ",").compactMap { Int($0) } } ?? []
        let byMonth = rule["BYMONTH"].map { $0.split(separator: ",").compactMap { Int($0) } } ?? []

        var results: [Date] = []
        var produced = 0
        var iterations = 0
        // `period` is the anchor of the current cycle (day / week start / month start / year start).
        var period = start
        func emit(_ d: Date) -> Bool {   // returns false when the rule is exhausted
            if d < start { return true }
            if let u = until, d > u { return false }
            produced += 1
            if let c = count, produced > c { return false }
            if d >= to { return false }
            if d.addingTimeInterval(duration) > from || (duration == 0 && d >= from) { results.append(d) }
            return true
        }
        loop: while iterations < maxIterations {
            iterations += 1
            var candidates: [Date] = []
            switch freq {
            case "DAILY":
                candidates = [period]
            case "WEEKLY":
                let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: period))!
                let tod = cal.dateComponents([.hour, .minute, .second], from: start)
                let days = byDay.isEmpty ? [weekdayCode(cal.component(.weekday, from: start))] : byDay
                for code in days {
                    guard let wd = weekdayNumber(code) else { continue }
                    let offset = (wd - cal.firstWeekday + 7) % 7
                    if var d = cal.date(byAdding: .day, value: offset, to: weekStart) {
                        d = cal.date(bySettingHour: tod.hour ?? 0, minute: tod.minute ?? 0, second: tod.second ?? 0, of: d) ?? d
                        candidates.append(d)
                    }
                }
            case "MONTHLY":
                let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: period))!
                let tod = cal.dateComponents([.hour, .minute, .second], from: start)
                if !byDay.isEmpty {
                    for code in byDay { if let d = nthWeekday(code, in: monthStart, cal: cal, tod: tod) { candidates.append(d) } }
                } else {
                    let days = byMonthDay.isEmpty ? [cal.component(.day, from: start)] : byMonthDay
                    let range = cal.range(of: .day, in: .month, for: monthStart)!
                    for day in days {
                        let dd = day < 0 ? range.count + day + 1 : day
                        guard range.contains(dd), var d = cal.date(byAdding: .day, value: dd - 1, to: monthStart) else { continue }
                        d = cal.date(bySettingHour: tod.hour ?? 0, minute: tod.minute ?? 0, second: tod.second ?? 0, of: d) ?? d
                        candidates.append(d)
                    }
                }
            case "YEARLY":
                let months = byMonth.isEmpty ? [cal.component(.month, from: start)] : byMonth
                let day = byMonthDay.first ?? cal.component(.day, from: start)
                let tod = cal.dateComponents([.hour, .minute, .second], from: start)
                let year = cal.component(.year, from: period)
                for m in months {
                    var c = DateComponents(year: year, month: m, day: day, hour: tod.hour, minute: tod.minute, second: tod.second)
                    if let d = cal.date(from: c), cal.component(.day, from: d) == day { candidates.append(d) } else { c.day = nil }
                }
            default:
                return [start]
            }
            for d in candidates.sorted() { if !emit(d) { break loop } }
            let step: Calendar.Component = freq == "DAILY" ? .day : freq == "WEEKLY" ? .weekOfYear : freq == "MONTHLY" ? .month : .year
            guard let next = cal.date(byAdding: step, value: interval, to: period) else { break }
            period = next
            if period >= to && candidates.allSatisfy({ $0 >= to }) { break }
        }
        return results
    }

    private static func weekdayNumber(_ code: String) -> Int? {
        let names = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        return names[String(code.suffix(2))]
    }
    private static func weekdayCode(_ n: Int) -> String { ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][max(min(n, 7), 1) - 1] }

    /// "2TU" → second Tuesday, "-1FR" → last Friday, "MO" → every Monday of the month.
    private static func nthWeekday(_ code: String, in monthStart: Date, cal: Calendar, tod: DateComponents) -> Date? {
        guard let wd = weekdayNumber(code) else { return nil }
        let n = Int(code.dropLast(2)) ?? 0
        let range = cal.range(of: .day, in: .month, for: monthStart)!
        var matches: [Date] = []
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: monthStart), cal.component(.weekday, from: d) == wd { matches.append(d) }
        }
        let pick: Date?
        if n == 0 { pick = matches.first }          // simplification: first occurrence when no ordinal
        else if n > 0 { pick = n <= matches.count ? matches[n - 1] : nil }
        else { pick = -n <= matches.count ? matches[matches.count + n] : nil }
        return pick.flatMap { cal.date(bySettingHour: tod.hour ?? 0, minute: tod.minute ?? 0, second: tod.second ?? 0, of: $0) }
    }
}
