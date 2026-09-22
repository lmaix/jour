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

// MARK: MonthGrid (September 2026 starts on a Tuesday)
let grid = MonthGrid.make(for: date(2026, 9, 22), calendarSystem: cal)
check(grid.cells.count == 42, "42 cellules")
check(grid.cells[0].date == date(2026, 8, 31) && !grid.cells[0].inMonth, "première cellule = lundi 31 août, hors mois")
check(grid.cells[1].date == date(2026, 9, 1) && grid.cells[1].inMonth, "2e cellule = 1er septembre")
check(grid.cells[22].date == date(2026, 9, 22), "cellule 22 = 22 septembre")
check(grid.cells[41].date == date(2026, 10, 11) && !grid.cells[41].inMonth, "dernière cellule = 11 octobre")
let june = MonthGrid.make(for: date(2026, 6, 15), calendarSystem: cal)   // 1er juin 2026 est un lundi
check(june.cells[0].date == date(2026, 6, 1), "mois commençant un lundi : pas de décalage")
let feb = MonthGrid.make(for: date(2026, 2, 10), calendarSystem: cal)    // 1er février 2026 est un dimanche
check(feb.cells[6].date == date(2026, 2, 1), "mois commençant un dimanche : 6 jours de décalage")

// MARK: Google parsing
let calListJSON = """
{"items":[{"id":"stephane@gmail.com","summary":"stephane@gmail.com","summaryOverride":"Perso","backgroundColor":"#9a9cff","selected":true},
          {"id":"holidays","summary":"Jours fériés","backgroundColor":"#16a765"},
          {"summary":"sans id"}]}
""".data(using: .utf8)!
let cals = try! GoogleParsing.calendars(from: calListJSON, account: "stephane@gmail.com")
check(cals.count == 2, "agendas parsés (entrée sans id ignorée)")
check(cals[0].name == "Perso" && cals[0].colorHex == "#9a9cff" && cals[0].selected, "summaryOverride, couleur, selected")
check(!cals[1].selected, "selected absent = false")

let eventsJSON = """
{"items":[
 {"id":"a","summary":"Dej Camille","start":{"dateTime":"2026-09-22T12:30:00+02:00"},"end":{"dateTime":"2026-09-22T14:00:00+02:00"},"location":"L'Amourette, 54 Rue Robespierre"},
 {"id":"b","summary":"Séminaire","start":{"date":"2026-09-23"},"end":{"date":"2026-09-25"}},
 {"id":"c","summary":"Annulé","status":"cancelled","start":{"dateTime":"2026-09-22T09:00:00Z"},"end":{"dateTime":"2026-09-22T10:00:00Z"}},
 {"id":"d","summary":"Décliné","start":{"dateTime":"2026-09-22T09:00:00Z"},"end":{"dateTime":"2026-09-22T10:00:00Z"},
  "attendees":[{"email":"x","responseStatus":"accepted"},{"email":"me","self":true,"responseStatus":"declined"}]},
 {"id":"e","start":{"dateTime":"2026-09-22T06:56:00+02:00"},"end":{"dateTime":"2026-09-22T08:30:00+02:00"},"colorId":"11","location":""}
]}
""".data(using: .utf8)!
let evs = try! GoogleParsing.events(from: eventsJSON, calendar: cals[0], calendarSystem: cal)
check(evs.map(\.id) == ["stephane@gmail.com/a", "stephane@gmail.com/b", "stephane@gmail.com/e"], "annulé et décliné ignorés")
check(evs[0].start == date(2026, 9, 22, 12, 30) && !evs[0].isAllDay && evs[0].location == "L'Amourette, 54 Rue Robespierre", "dateTime avec fuseau")
check(evs[1].isAllDay && evs[1].start == date(2026, 9, 23) && evs[1].end == date(2026, 9, 25), "journée entière")
check(evs[0].colorHex == "#9a9cff" && evs[2].colorHex == "#d50000", "couleur : agenda par défaut, colorId sinon")
check(evs[2].title == "(Sans titre)" && evs[2].location == nil, "titre absent, lieu vide -> nil")

do { _ = try GoogleParsing.events(from: "{\"error\":{\"code\":401,\"message\":\"Invalid Credentials\"}}".data(using: .utf8)!, calendar: cals[0]); check(false, "erreur API -> throw") }
catch let e as ParseError { check(e == .apiError("Invalid Credentials"), "erreur API remontée") }
catch { check(false, "mauvais type d'erreur") }

// MARK: EventIndex
let byDay = EventIndex.byDay(evs, calendarSystem: cal)
check(byDay[date(2026, 9, 22)]?.map(\.id) == ["stephane@gmail.com/e", "stephane@gmail.com/a"], "22 : trié par heure")
check(byDay[date(2026, 9, 23)]?.count == 1 && byDay[date(2026, 9, 24)]?.count == 1 && byDay[date(2026, 9, 25)] == nil, "journée entière sur 23 et 24, fin exclusive")

// MARK: Formatting
check(Fmt.weekdaySymbols(locale: Locale(identifier: "fr_FR")).first?.hasPrefix("lun") == true, "semaine commence lundi")
check(Fmt.dayTitle(date(2026, 9, 22), locale: Locale(identifier: "fr_FR")).contains("22 septembre"), "titre du jour en français")

// MARK: OAuth helpers
check(GoogleAuth.queryParams(fromRequestLine: "GET /?state=abc&code=4%2FxyZ&scope=email HTTP/1.1\r\nHost: x") == ["state": "abc", "code": "4/xyZ", "scope": "email"], "paramètres de la redirection")
check(GoogleAuth.queryParams(fromRequestLine: "GET /favicon.ico HTTP/1.1").isEmpty, "requête sans paramètres")
check(GoogleAuth.formEncode("a b/c+d") == "a%20b%2Fc%2Bd", "encodage formulaire")
check(Data([0xfb, 0xff]).base64URL() == "-_8", "base64url sans padding")
check(GoogleAuth.randomString(64).count == 64, "verifier PKCE de 64 caractères")

print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
