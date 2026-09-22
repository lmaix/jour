import AppKit
import CryptoKit
import Foundation
import Network

enum AuthError: Error {
    case noClient, noAccount, cancelled, http(Int, String), network(String), invalidResponse(String), noRefreshToken

    var message: String {
        switch self {
        case .noClient: return "Identifiant OAuth manquant : clic droit → Configurer l'identifiant OAuth…"
        case .noAccount: return "Aucun compte : clic droit → Ajouter un compte Google…"
        case .cancelled: return "Connexion annulée"
        case .http(let c, let s): return "Google HTTP \(c) : \(s)"
        case .network(let s): return "Réseau : \(s)"
        case .invalidResponse(let s): return "Réponse inattendue : \(s)"
        case .noRefreshToken: return "Google n'a pas renvoyé de refresh token : retire l'accès de l'app sur myaccount.google.com/permissions puis réessaie"
        }
    }
}

/// OAuth 2.0 for a desktop app: PKCE, loopback redirect, refresh tokens kept in the Keychain.
final class GoogleAuth {
    static let scopes = "https://www.googleapis.com/auth/calendar.readonly openid email"
    static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    static let userinfoURL = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!

    private var cache: [String: (token: String, expiry: Date)] = [:]
    private var listener: NWListener?
    private var openConnections: [NWConnection] = []

    // MARK: - Access tokens

    func accessToken(for account: GoogleAccount, client: OAuthClient, completion: @escaping (Result<String, AuthError>) -> Void) {
        if let c = cache[account.email], c.expiry > Date().addingTimeInterval(60) { return completion(.success(c.token)) }
        Self.post(Self.tokenURL, form: [
            "client_id": client.id, "client_secret": client.secret,
            "refresh_token": account.refreshToken, "grant_type": "refresh_token",
        ]) { [weak self] r in
            switch r {
            case .failure(let e): completion(.failure(e))
            case .success(let obj):
                guard let t = obj["access_token"] as? String else { return completion(.failure(.invalidResponse("pas d'access_token"))) }
                let exp = Date().addingTimeInterval((obj["expires_in"] as? Double) ?? 3600)
                self?.cache[account.email] = (t, exp)
                completion(.success(t))
            }
        }
    }

    func forget(email: String) { cache[email] = nil }

    // MARK: - Sign-in flow

    /// Starts a loopback server, opens the browser, exchanges the code, resolves the account email.
    func signIn(client: OAuthClient, completion: @escaping (Result<GoogleAccount, AuthError>) -> Void) {
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
        let state = Self.randomString(16)
        cancelListener()

        guard let listener = try? NWListener(using: .tcp, on: .any) else { return completion(.failure(.network("port local indisponible"))) }
        self.listener = listener
        var finished = false
        let finish: (Result<GoogleAccount, AuthError>) -> Void = { [weak self] r in
            guard !finished else { return }
            finished = true
            self?.cancelListener()
            DispatchQueue.main.async { completion(r) }
        }

        listener.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            switch st {
            case .ready:
                guard let port = listener.port?.rawValue else { return finish(.failure(.network("port local inconnu"))) }
                let redirect = "http://127.0.0.1:\(port)"
                var c = URLComponents(string: Self.authURL)!
                c.queryItems = [
                    .init(name: "client_id", value: client.id),
                    .init(name: "redirect_uri", value: redirect),
                    .init(name: "response_type", value: "code"),
                    .init(name: "scope", value: Self.scopes),
                    .init(name: "code_challenge", value: challenge),
                    .init(name: "code_challenge_method", value: "S256"),
                    .init(name: "access_type", value: "offline"),
                    .init(name: "prompt", value: "consent select_account"),
                    .init(name: "state", value: state),
                ]
                NSWorkspace.shared.open(c.url!)
                self.redirectURI = redirect
            case .failed(let e): finish(.failure(.network(e.localizedDescription)))
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            guard let self = self else { return }
            self.openConnections.append(conn)
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let params = Self.queryParams(fromRequestLine: request)
                let ok = params["code"] != nil && params["state"] == state
                let body = ok ? "<h2>Connecté. Tu peux fermer cette fenêtre.</h2>" : "<h2>Connexion refusée ou invalide.</h2>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body
                conn.send(content: Data(resp.utf8), completion: .contentProcessed { _ in conn.cancel() })
                guard let code = params["code"], params["state"] == state else {
                    if params["error"] != nil || params["code"] == nil && !request.isEmpty && request.hasPrefix("GET /?") {
                        finish(.failure(.cancelled))
                    }
                    return
                }
                self.exchange(code: code, verifier: verifier, client: client, completion: finish)
            }
        }
        listener.start(queue: .main)
    }

    private var redirectURI = ""

    private func exchange(code: String, verifier: String, client: OAuthClient, completion: @escaping (Result<GoogleAccount, AuthError>) -> Void) {
        Self.post(Self.tokenURL, form: [
            "client_id": client.id, "client_secret": client.secret, "code": code,
            "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirectURI,
        ]) { [weak self] r in
            switch r {
            case .failure(let e): completion(.failure(e))
            case .success(let obj):
                guard let access = obj["access_token"] as? String else { return completion(.failure(.invalidResponse("pas d'access_token"))) }
                guard let refresh = obj["refresh_token"] as? String else { return completion(.failure(.noRefreshToken)) }
                var req = URLRequest(url: Self.userinfoURL)
                req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: req) { data, _, err in
                    if let err = err { return completion(.failure(.network(err.localizedDescription))) }
                    guard let d = data, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let email = o["email"] as? String else { return completion(.failure(.invalidResponse("userinfo"))) }
                    let exp = Date().addingTimeInterval((obj["expires_in"] as? Double) ?? 3600)
                    self?.cache[email] = (access, exp)
                    completion(.success(GoogleAccount(email: email, refreshToken: refresh)))
                }.resume()
            }
        }
    }

    private func cancelListener() {
        listener?.cancel(); listener = nil
        openConnections.forEach { $0.cancel() }; openConnections = []
    }

    // MARK: - Helpers

    static func post(_ url: URL, form: [String: String], completion: @escaping (Result<[String: Any], AuthError>) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(form.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").utf8)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { return completion(.failure(.network(err.localizedDescription))) }
            guard let http = resp as? HTTPURLResponse, let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return completion(.failure(.invalidResponse("réponse vide")))
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = (obj["error_description"] as? String) ?? (obj["error"] as? String) ?? ""
                return completion(.failure(.http(http.statusCode, msg)))
            }
            completion(.success(obj))
        }.resume()
    }

    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// "GET /?code=abc&state=xyz HTTP/1.1 …" → ["code": "abc", "state": "xyz"]
    static func queryParams(fromRequestLine request: String) -> [String: String] {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first ?? request.split(separator: "\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://x" + path) else { return [:] }
        var out: [String: String] = [:]
        for q in comps.queryItems ?? [] { out[q.name] = q.value ?? "" }
        return out
    }

    static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

extension Data {
    func base64URL() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
