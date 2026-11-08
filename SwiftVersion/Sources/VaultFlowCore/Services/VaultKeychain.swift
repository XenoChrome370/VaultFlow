// Keychain.swift
// VaultFlow · Keychain storage for the (optional) master key cache
//
// By default nothing is stored: you type the master password each launch.
// With Touch ID quick-unlock enabled, the *derived 32-byte master key* (never
// the password itself) is stored as a Keychain generic password guarded by
// `SecAccessControlCreateWithFlags(.userPresence)`, so reading it requires a
// biometric/password gesture every time.

import Foundation
import Security
import LocalAuthentication

public enum KeychainError: LocalizedError {
    case unexpected(OSStatus)
    case userCanceled
    case notAvailable
    case missing

    public var errorDescription: String? {
        switch self {
        case .unexpected(let code):
            let message = SecCopyErrorMessageString(code, nil) as String? ?? "OSStatus \(code)"
            return "Keychain error: \(message)"
        case .userCanceled: return "Authentication was canceled."
        case .notAvailable: return "Touch ID isn't available on this Mac."
        case .missing: return "No stored unlock key was found."
        }
    }
}

public enum VaultKeychain {
    public static let service = "com.vaultflow.macos"
    public static let account = "master-key"

    /// Whether the Mac supports and has enrolled biometrics.
    public static var biometryAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return true
    }

    public static var biometryLabel: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .faceID: return "Face ID"
        case .none: return "Password"
        @unknown default: return "Biometrics"
        }
    }

    /// Stores the raw master key protected by user presence.
    public static func storeMasterKey(_ key: Data, label: String) throws {
        try delete()
        var accessError: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.userPresence],
            &accessError
        )
        guard let access else {
            throw accessError?.takeRetainedValue() as Error? ?? KeychainError.notAvailable
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "VaultFlow — \(label)",
            kSecValueData as String: key,
            kSecAttrAccessControl as String: access,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpected(status) }
    }

    /// Reads the master key. Triggers Touch ID via `context`.
    public static func loadMasterKey(reason: String = "Unlock VaultFlow") async throws -> Data {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = "Use Master Password"
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        if #available(macOS 10.15, *) {
            query[kSecUseAuthenticationContext as String] = context
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.missing }
            return data
        case errSecItemNotFound:
            throw KeychainError.missing
        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.userCanceled
        default:
            throw KeychainError.unexpected(status)
        }
    }

    public static func hasStoredMasterKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpected(status)
        }
    }

    /// Explicit local authentication prompt (used before revealing secrets).
    @discardableResult
    public static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

public enum BiometricPreference {
    public static let quickUnlockKey = "vf.quickUnlock"
    public static let clipboardHistoryKey = "vf.clipboardHistory"
    public static let autoLockKey = "vf.autoLockMinutes"
    public static let showMenuBarKey = "vf.showMenuBar"
    public static let retentionHoursKey = "vf.historyRetentionHours"
}
