import Foundation
import Security

/// Generic-password items owned by this app.
enum Keychain {
    static let accountsService = "ClaudeCalendarBar"          // account = Google email, data = refresh token
    static let clientService = "ClaudeCalendarBar-client"     // account = "client", data = JSON {id, secret}

    static func read(service: String, account: String) -> Data? {
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

    @discardableResult
    static func write(service: String, account: String, data: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let st = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecSuccess { return true }
        guard st == errSecItemNotFound else { return false }
        var add = base
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(service: String, account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
    }

    /// All account names stored under a service (no secrets returned).
    static func accounts(service: String) -> [String] {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess,
              let items = r as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }
}

struct OAuthClient: Equatable {
    let id: String
    let secret: String

    static func load() -> OAuthClient? {
        guard let d = Keychain.read(service: Keychain.clientService, account: "client"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String],
              let id = o["id"], let secret = o["secret"], !id.isEmpty else { return nil }
        return OAuthClient(id: id, secret: secret)
    }

    func save() -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: ["id": id, "secret": secret]) else { return false }
        return Keychain.write(service: Keychain.clientService, account: "client", data: d)
    }
}

struct GoogleAccount: Equatable {
    let email: String
    let refreshToken: String

    static func all() -> [GoogleAccount] {
        Keychain.accounts(service: Keychain.accountsService).compactMap { email in
            guard let d = Keychain.read(service: Keychain.accountsService, account: email),
                  let t = String(data: d, encoding: .utf8), !t.isEmpty else { return nil }
            return GoogleAccount(email: email, refreshToken: t)
        }
    }

    func save() -> Bool { Keychain.write(service: Keychain.accountsService, account: email, data: Data(refreshToken.utf8)) }
    static func remove(email: String) { Keychain.delete(service: Keychain.accountsService, account: email) }
}
