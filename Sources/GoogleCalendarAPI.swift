import Foundation

/// Fetches every selected calendar of every account for a date range.
final class GoogleCalendarAPI {
    static let base = "https://www.googleapis.com/calendar/v3"
    private let auth: GoogleAuth

    init(auth: GoogleAuth) { self.auth = auth }

    struct FetchResult {
        var events: [CalendarEvent] = []
        var errors: [String] = []
    }

    func fetchAll(accounts: [GoogleAccount], client: OAuthClient, from: Date, to: Date,
                  completion: @escaping (FetchResult) -> Void) {
        let group = DispatchGroup()
        var result = FetchResult()
        let lock = NSLock()
        for account in accounts {
            group.enter()
            fetch(account: account, client: client, from: from, to: to) { events, errors in
                lock.lock(); result.events += events; result.errors += errors; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(result) }
    }

    private func fetch(account: GoogleAccount, client: OAuthClient, from: Date, to: Date,
                       completion: @escaping ([CalendarEvent], [String]) -> Void) {
        auth.accessToken(for: account, client: client) { r in
            switch r {
            case .failure(let e): completion([], ["\(account.email) : \(e.message)"])
            case .success(let token):
                self.get("\(Self.base)/users/me/calendarList", token: token) { r in
                    guard case .success(let data) = r else {
                        if case .failure(let e) = r { completion([], ["\(account.email) : \(e)"]) }
                        return
                    }
                    let calendars: [CalendarInfo]
                    do { calendars = try GoogleParsing.calendars(from: data, account: account.email).filter(\.selected) }
                    catch { return completion([], ["\(account.email) : \(error)"]) }
                    let group = DispatchGroup()
                    var events: [CalendarEvent] = [], errors: [String] = []
                    let lock = NSLock()
                    let iso = ISO8601DateFormatter()
                    for cal in calendars {
                        group.enter()
                        var c = URLComponents(string: "\(Self.base)/calendars/\(GoogleAuth.formEncode(cal.id))/events")!
                        c.queryItems = [
                            .init(name: "timeMin", value: iso.string(from: from)),
                            .init(name: "timeMax", value: iso.string(from: to)),
                            .init(name: "singleEvents", value: "true"),
                            .init(name: "orderBy", value: "startTime"),
                            .init(name: "maxResults", value: "2500"),
                        ]
                        self.get(c.url!.absoluteString, token: token) { r in
                            lock.lock()
                            switch r {
                            case .success(let d):
                                do { events += try GoogleParsing.events(from: d, calendar: cal) }
                                catch { errors.append("\(cal.name) : \(error)") }
                            case .failure(let e): errors.append("\(cal.name) : \(e)")
                            }
                            lock.unlock()
                            group.leave()
                        }
                    }
                    group.notify(queue: .global()) { completion(events, errors) }
                }
            }
        }
    }

    struct HTTPError: Error, CustomStringConvertible {
        let description: String
    }

    private func get(_ url: String, token: String, completion: @escaping (Result<Data, HTTPError>) -> Void) {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(HTTPError(description: err.localizedDescription))) }
            guard let http = resp as? HTTPURLResponse, let data = data else { return completion(.failure(HTTPError(description: "réponse vide"))) }
            guard (200..<300).contains(http.statusCode) else {
                var msg = ""
                do { _ = try GoogleParsing.object(data) } catch ParseError.apiError(let m) { msg = m } catch {}
                return completion(.failure(HTTPError(description: "HTTP \(http.statusCode) \(msg)")))
            }
            completion(.success(data))
        }.resume()
    }
}
