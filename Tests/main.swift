import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg) (line \(line))") }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Paris")!
cal.locale = Locale(identifier: "fr_FR")
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
}
let paris = TimeZone(identifier: "Europe/Paris")!

// MARK: MonthGrid (September 2026 starts on a Tuesday)
let grid = MonthGrid.make(for: date(2026, 9, 22), calendarSystem: cal)
check(grid.cells.count == 42, "42 cellules")
check(grid.cells[0].date == date(2026, 8, 31) && !grid.cells[0].inMonth, "première cellule = lundi 31 août, hors mois")
check(grid.cells[22].date == date(2026, 9, 22) && grid.cells[22].inMonth, "cellule 22 = 22 septembre")
check(grid.cells[41].date == date(2026, 10, 11) && !grid.cells[41].inMonth, "dernière cellule = 11 octobre")
check(MonthGrid.make(for: date(2026, 6, 15), calendarSystem: cal).cells[0].date == date(2026, 6, 1), "mois commençant un lundi : pas de décalage")
check(MonthGrid.make(for: date(2026, 2, 10), calendarSystem: cal).cells[6].date == date(2026, 2, 1), "mois commençant un dimanche : 6 jours de décalage")

// MARK: ICS parsing
let ics = """
BEGIN:VCALENDAR\r
X-WR-CALNAME:Perso\r
BEGIN:VEVENT\r
UID:a\r
SUMMARY:Dej Camille\\, resto\r
LOCATION:L'Amourette\\, 54 Rue Robespierre\r
DTSTART;TZID=Europe/Paris:20260922T123000\r
DTEND;TZID=Europe/Paris:20260922T140000\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:b\r
SUMMARY:Séminaire\r
DTSTART;VALUE=DATE:20260923\r
DTEND;VALUE=DATE:20260925\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:c\r
SUMMARY:Annulé\r
STATUS:CANCELLED\r
DTSTART:20260922T070000Z\r
DTEND:20260922T080000Z\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:d\r
SUMMARY:Décliné\r
ATTENDEE;CN=Moi;PARTSTAT=DECLINED;CUTYPE=INDIVIDUAL:mailto:stephane@gmail.com\r
DTSTART:20260922T070000Z\r
DURATION:PT1H\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:e\r
SUMMARY:Standup\r
DTSTART;TZID=Europe/Paris:20260901T093000\r
DTEND;TZID=Europe/Paris:20260901T094500\r
RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261231T000000Z\r
EXDATE;TZID=Europe/Paris:20260923T093000\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:e\r
RECURRENCE-ID;TZID=Europe/Paris:20260925T093000\r
SUMMARY:Standup décalé\r
DTSTART;TZID=Europe/Paris:20260925T110000\r
DTEND;TZID=Europe/Paris:20260925T111500\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:f\r
SUMMARY:Loyer\r
DTSTART;VALUE=DATE:20260105\r
DTEND;VALUE=DATE:20260106\r
RRULE:FREQ=MONTHLY;COUNT=12\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:g\r
SUMMARY:Anniv\r
DTSTART;VALUE=DATE:19900922\r
RRULE:FREQ=YEARLY\r
END:VEVENT\r
BEGIN:VEVENT\r
UID:h\r
SUMMARY:Ligne pliée sur\r
  deux lignes\r
DTSTART;TZID=Europe/Paris:20260924T180000\r
DTEND;TZID=Europe/Paris:20260924T190000\r
END:VEVENT\r
END:VCALENDAR\r
"""
let feed = ICS.parse(ics)
check(feed.name == "Perso", "X-WR-CALNAME")
check(feed.events.count == 9, "9 VEVENT parsés")
let a = feed.events[0]
check(a.summary == "Dej Camille, resto" && a.location == "L'Amourette, 54 Rue Robespierre", "échappements \\, décodés")
check(a.start == date(2026, 9, 22, 12, 30) && a.end == date(2026, 9, 22, 14, 0) && !a.isAllDay, "DTSTART avec TZID")
check(feed.events[1].isAllDay && feed.events[1].start == date(2026, 9, 23), "VALUE=DATE = journée entière")
check(feed.events[3].end == feed.events[3].start?.addingTimeInterval(3600), "DURATION:PT1H")
check(feed.events[3].declinedBy == ["stephane@gmail.com"], "ATTENDEE déclinée")
check(feed.events[4].rrule?["FREQ"] == "WEEKLY" && feed.events[4].rrule?["BYDAY"] == "MO,WE,FR", "RRULE parsée")
check(feed.events[4].exdates.first == date(2026, 9, 23, 9, 30), "EXDATE")
check(feed.events[5].recurrenceID == date(2026, 9, 25, 9, 30), "RECURRENCE-ID")
check(feed.events[8].summary == "Ligne pliée sur deux lignes", "dépliage des lignes")
check(ICS.parseDuration("P1DT2H30M") == 86400 + 9000 && ICS.parseDuration("PT45M") == 2700, "durées")
check(ICS.parseDate(ICS.Property(name: "X", params: [:], value: "20260922T070000Z"))?.0 == date(2026, 9, 22, 9, 0), "date UTC -> Paris")

// MARK: Expansion over 21–27 September 2026
let from = date(2026, 9, 21), to = date(2026, 9, 28)
let occ = ICS.occurrences(of: feed, from: from, to: to, calendarName: "Perso", colorHex: "#0a84ff", account: "u", selfEmail: "stephane@gmail.com")
func titles(_ d: Date) -> [String] { occ.filter { cal.isDate($0.start, inSameDayAs: d) }.sorted { $0.start < $1.start }.map(\.title) }
check(titles(date(2026, 9, 22)) == ["Anniv", "Dej Camille, resto"], "22 : anniv annuel + déjeuner ; annulé et décliné exclus — \(titles(date(2026, 9, 22)))")
check(titles(date(2026, 9, 21)) == ["Standup"] && titles(date(2026, 9, 25)) == ["Standup décalé"], "hebdo lundi + override vendredi")
check(titles(date(2026, 9, 23)) == ["Séminaire"], "EXDATE du mercredi retire le standup ; journée entière présente")
check(titles(date(2026, 9, 24)) == ["Ligne pliée sur deux lignes"], "24 : pas de standup (jeudi) — \(titles(date(2026, 9, 24)))")
check(occ.filter { $0.title == "Standup" }.count == 1, "un seul standup de base dans la plage (23 exclu, 25 remplacé, 28 hors plage)")
let loyer = ICS.occurrences(of: feed, from: date(2026, 1, 1), to: date(2027, 6, 1), calendarName: "P", colorHex: nil, account: "u").filter { $0.title == "Loyer" }
check(loyer.count == 12 && cal.component(.day, from: loyer[11].start) == 5 && cal.component(.month, from: loyer[11].start) == 12, "mensuel COUNT=12 : 12 occurrences, dernière en décembre")
let dst = ICS.occurrences(of: feed, from: date(2026, 11, 2), to: date(2026, 11, 3), calendarName: "P", colorHex: nil, account: "u").filter { $0.title == "Standup" }
check(dst.first.map { cal.component(.hour, from: $0.start) } == 9, "heure locale conservée après le changement d'heure")

// MARK: EventIndex + Fmt
let byDay = EventIndex.byDay(occ, calendarSystem: cal)
check(byDay[date(2026, 9, 24)]?.contains { $0.title == "Séminaire" } == true && byDay[date(2026, 9, 25)]?.contains { $0.title == "Séminaire" } == false, "journée entière sur 23 et 24, fin exclusive")
let now22 = date(2026, 9, 22, 12, 0)
let up = EventIndex.upcoming(occ, now: now22, limit: 3)
check(up.map(\.title) == ["Anniv", "Dej Camille, resto", "Séminaire"], "à venir : journée entière en cours d'abord, puis par heure — \(up.map(\.title))")
check(EventIndex.upcoming(occ + occ, now: now22).count == EventIndex.upcoming(occ, now: now22).count, "doublons dédupliqués")
check(Fmt.relativeDay(date(2026, 9, 22, 18), now: now22, calendarSystem: cal) == "Aujourd'hui" && Fmt.relativeDay(date(2026, 9, 23), now: now22, calendarSystem: cal) == "Demain", "Aujourd'hui / Demain")
check(Fmt.weekdaySymbols(locale: Locale(identifier: "fr_FR")).first?.hasPrefix("lun") == true, "semaine commence lundi")

// MARK: Feed helpers
check(Feed(name: "", url: "https://calendar.google.com/calendar/ical/stephane%40gmail.com/private-abc/basic.ics", colorHex: "#000").ownerEmail == "stephane@gmail.com", "email propriétaire extrait de l'URL Google")
check(Feed(name: "", url: "https://example.com/cal.ics", colorHex: "#000").ownerEmail == nil, "pas d'email pour une URL quelconque")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
