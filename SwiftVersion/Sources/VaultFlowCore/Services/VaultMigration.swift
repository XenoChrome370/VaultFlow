// VaultMigration.swift
// VaultFlow · Opening and upgrading vaults from the Python and Java versions
//
// Detection order for an arbitrary file:
//   1. VaultFlow envelope (`salt` + `vault` + optional `meta`)  → parse metadata
//   2. Python-style envelope (`salt` + `vault`, Fernet token)   → Fernet key from
//      PBKDF2 password, or from the user-supplied 44-char Fernet key
//   3. Java-style envelope (same keys, GCM payload)             → auto-detected
//   4. Plaintext vault (bare `{service:{accounts:[…]}}`)        → needs re-encryption
//
// Probing both ciphers is cheap: one AES-GCM open or one Fernet HMAC check.

import Foundation
import CommonCrypto

public enum LegacyVaultKind: String, Sendable {
    case vaultFlowEnvelope = "VaultFlow"
    case pythonEnvelope = "Python (Fernet)"
    case javaEnvelope = "Java (AES-GCM)"
    case plaintext = "Legacy plaintext"

    public var title: String { rawValue }
}

public struct LegacyVaultInfo: Sendable {
    public var kind: LegacyVaultKind
    public var salt: Data
    public var iterationCount: Int
    public var entryCount: Int?
}

public enum VaultMigration {
    /// Sniffs the kind of a file without requiring a password.
    public static func detect(_ data: Data) -> LegacyVaultKind? {
        guard let root = try? JSONValue.decode(data), let object = root.objectValue else { return nil }
        if object["salt"] != nil, object["vault"] != nil {
            if object["meta"]?["app"]?.stringValue == "VaultFlow" { return .vaultFlowEnvelope }
            if let declared = object["meta"]?["cipher"]?.stringValue {
                return declared.lowercased().contains("fernet") ? .pythonEnvelope : .javaEnvelope
            }
            // No metadata: sniff the payload. A Fernet token is a versioned
            // binary blob (leading 0x80, length = 1 + 8 + 16 + 16n + 32); an
            // AES-GCM payload is iv(16) ‖ ciphertext(16n) ‖ tag(16).
            if let token = object["vault"]?.stringValue, let payload = VaultBase64.decode(token),
               !payload.isEmpty {
                if payload[payload.startIndex] == 0x80 { return .pythonEnvelope }
                if payload.count > 32, (payload.count - 32) % 16 == 0 { return .javaEnvelope }
            }
            return .pythonEnvelope
        }
        if object.contains(where: { $0.value.objectValue?["accounts"] != nil }) { return .plaintext }
        return nil
    }

    public struct Unlocked: Sendable {
        public var document: VaultDocument
        public var kind: LegacyVaultKind
        public var session: UnlockedSession
    }

    /// Opens a vault file with a master password.
    ///
    /// - Parameters:
    ///   - rawFernetKey: optional base64 Fernet key, for vaults encrypted with
    ///     a raw key rather than a password (e.g. SomeKeychain exports).
    public static func open(
        _ data: Data,
        password: String,
        iterations: Int = VaultFormat.defaultIterations,
        rawFernetKey: String? = nil
    ) throws -> Unlocked {
        guard let kind = detect(data) else { throw VaultFormatError.notAVaultFile }

        if kind == .plaintext {
            let document = try VaultSerializer.decode(data)
            let session = UnlockedSession(key: Data(), salt: Data(), cipher: .aes256gcm,
                                          parameters: EncryptionParameters(), extensions: [:])
            return Unlocked(document: document, kind: .plaintext, session: session)
        }

        let parsed = try VaultFormat.parseEnvelope(data)

        // Option A: the user has the raw Fernet key (44-char urlsafe base64).
        if let rawFernetKey, let rawData = VaultBase64.decode(rawFernetKey), rawData.count == 32 {
            for cipher in [CipherKind.fernet, .aes256gcm] {
                if let plaintext = try? VaultFormat.decrypt(payload: parsed.payload, key: rawData, cipher: cipher),
                   let document = try? VaultSerializer.decode(plaintext) {
                    let session = UnlockedSession(key: rawData, salt: parsed.salt, cipher: cipher,
                                                  parameters: parsed.parameters, extensions: parsed.extensions)
                    return Unlocked(document: document, kind: .pythonEnvelope, session: session)
                }
            }
            throw VaultFormatError.wrongPassword
        }

        let derivedKey = try VaultFormat.deriveKey(password: password, salt: parsed.salt,
                                                   parameters: parsed.parameters)

        // Option B: try the declared cipher first, then the other one.
        let order: [CipherKind] = parsed.cipher == .fernet ? [.fernet, .aes256gcm] : [.aes256gcm, .fernet]
        for cipher in order {
            if let plaintext = try? VaultFormat.decrypt(payload: parsed.payload, key: derivedKey, cipher: cipher),
               let document = try? VaultSerializer.decode(plaintext) {
                let resolvedKind: LegacyVaultKind = cipher == .fernet ? .pythonEnvelope : .javaEnvelope
                let session = UnlockedSession(key: derivedKey, salt: parsed.salt, cipher: cipher,
                                              parameters: parsed.parameters, extensions: parsed.extensions)
                return Unlocked(document: document, kind: resolvedKind, session: session)
            }
        }
        throw VaultFormatError.wrongPassword
    }

    /// Tries the default per-platform vault locations from the Python and Java
    /// projects (current directory and their folders).
    public static func discoverLegacyVaults(projectRoot: URL?) -> [URL] {
        var candidates: [URL] = []
        let candidatesRelative = [
            "PythonVersion/passwords.json",
            "JavaVersion/javaStorage.json",
            "passwords.json",
            "javaStorage.json"
        ]
        let bases: [URL] = [
            projectRoot,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            URL(fileURLWithPath: NSHomeDirectory())
        ].compactMap { $0 }
        for base in bases {
            for relative in candidatesRelative {
                let url = base.appendingPathComponent(relative)
                if FileManager.default.fileExists(atPath: url.path),
                   !candidates.contains(url) {
                    candidates.append(url)
                }
            }
        }
        return candidates
    }
}

/// A Fernet key string helper for the "enter key instead of password" path.
public enum FernetKeyUtility {
    public static func isValid(_ text: String) -> Bool {
        VaultBase64.decode(text)?.count == 32
    }
}
