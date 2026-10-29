import Foundation
import Security

/// The device admin password, stored in the user's login Keychain as a generic
/// password: service `BandPassFilterController`, account = the device hostname
/// exactly as the firmware reports it (`/discover` / `/config` `hostname`,
/// e.g. `BPF-SO2R`). Matches an item created with
/// `security add-generic-password -s BandPassFilterController -a <hostname> -w`.
enum DeviceKeychain {
    static let service = "BandPassFilterController"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)."
        }
    }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Whether an item exists. Asks for attributes only, so it never decrypts
    /// the secret and never triggers a Keychain access prompt.
    static func hasPassword(for account: String) -> Bool {
        var q = query(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    /// The stored password, or nil if there is none or access was denied.
    static func password(for account: String) -> String? {
        var q = query(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Create or replace the password for `account`.
    static func setPassword(_ password: String, for account: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(account)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = service
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    /// Remove the password for `account`; succeeds if there was none.
    static func deletePassword(for account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
