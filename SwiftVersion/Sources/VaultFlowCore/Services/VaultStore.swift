// VaultStore.swift
// VaultFlow · The in-memory vault session
//
// Owns the master key for the lifetime of an unlocked session, exposes the
// decrypted document, and persists changes atomically. The master key is kept
// in memory only (never written to disk) and is zeroed on lock.

import Foundation

public enum VaultStoreError: LocalizedError {
    case locked
    case noMasterKey
    case serviceNameRequired
    case duplicateEntry
    case entryNotFound
    case alreadyExists(URL)
    case wrongPassword

    public var errorDescription: String? {
        switch self {
        case .locked: return "The vault is locked."
        case .wrongPassword: return "That master password didn't work."
        case .noMasterKey: return "Unlock the vault first."
        case .serviceNameRequired: return "Enter a service name (e.g. gmail.com)."
        case .duplicateEntry: return "An account with that username already exists for this service."
        case .entryNotFound: return "That entry no longer exists."
        case .alreadyExists(let url): return "“\(url.lastPathComponent)” already exists."
        }
    }
}

public struct UnlockedSession: Sendable {
    public var key: Data
    public var salt: Data
    public var cipher: CipherKind
    public var parameters: EncryptionParameters
    public var extensions: [String: JSONValue]

    public init(key: Data, salt: Data, cipher: CipherKind,
                parameters: EncryptionParameters, extensions: [String: JSONValue]) {
        self.key = key
        self.salt = salt
        self.cipher = cipher
        self.parameters = parameters
        self.extensions = extensions
    }
}

/// Result of attempting to create a fresh vault.
public struct VaultCreationResult: Sendable {
    public var session: UnlockedSession
    public var recoveryKey: String
}

public actor VaultSession {
    public private(set) var document: VaultDocument = VaultDocument()
    public private(set) var isUnlocked = false

    private var key: Data?
    private var salt: Data = Data()
    private var cipher: CipherKind = VaultFormat.defaultCipher
    private var parameters = EncryptionParameters()
    private var extensions: [String: JSONValue] = [:]
    private var documentURL: URL
    private var revision: Int = 0

    public init(url: URL) {
        self.documentURL = url
    }

    public var url: URL { documentURL }

    public static func defaultVaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base
            .appendingPathComponent("VaultFlow", isDirectory: true)
            .appendingPathComponent("vault.json")
    }

    // MARK: Files

    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: documentURL.path)
    }

    /// Moves the session to a different file (used by Settings → Change Location).
    public func setURL(_ url: URL) {
        documentURL = url
    }

    // MARK: Create

    public static func createVault(
        at url: URL,
        password: String,
        iterations: Int = VaultFormat.defaultIterations
    ) throws -> (session: UnlockedSession, recoveryKey: String) {
        let salt = SecureRandom.bytes(16)
        let params = EncryptionParameters(iterations: iterations)
        let key = try VaultFormat.deriveKey(password: password, salt: salt, parameters: params)
        let recoveryKey = RecoveryKey.generate()

        var empty = VaultDocument()
        empty.modifiedAt = Date()
        var meta: [String: JSONValue] = [
            "createdAt": .string(ISO8601DateFormatter().string(from: Date())),
            "app": .string("VaultFlow for macOS")
        ]
        if let store = try? SecBackup.wrapRecoveryKey(recoveryKey, for: password) {
            meta["recovery"] = store
        }
        empty.rootUnknownKeys["x-vaultflow"] = .object(meta)

        let plaintext = try VaultSerializer.encode(empty)
        let payload = try VaultFormat.encrypt(plaintext: plaintext, key: key, cipher: .aes256gcm)
        let envelope = VaultFormat.makeEnvelope(salt: salt, payload: payload,
                                                cipher: .aes256gcm, parameters: params)
        try AtomicFileStore.write(try envelope.encodedData(pretty: true), to: url)

        let session = UnlockedSession(key: key, salt: salt, cipher: .aes256gcm,
                                      parameters: params, extensions: [:])
        return (session, recoveryKey)
    }

    // MARK: Unlock

    public func loadFromDisk() throws {
        guard fileExists else { throw VaultStoreError.noMasterKey }
        _ = try AtomicFileStore.read(from: documentURL)
    }

    /// Verifies a password against the on-disk vault without keeping the key.
    public func verify(_ password: String) throws -> (session: UnlockedSession, document: VaultDocument) {
        let data = try AtomicFileStore.read(from: documentURL)
        let parsed = try VaultFormat.parseEnvelope(data)
        let derivedKey = try VaultFormat.deriveKey(password: password, salt: parsed.salt,
                                                  parameters: parsed.parameters)
        let plaintext: Data
        do {
            plaintext = try VaultFormat.decrypt(payload: parsed.payload, key: derivedKey, cipher: parsed.cipher)
        } catch {
            throw VaultStoreError.wrongPassword
        }
        let document = try VaultSerializer.decode(plaintext)
        let session = UnlockedSession(key: derivedKey, salt: parsed.salt, cipher: parsed.cipher,
                                      parameters: parsed.parameters, extensions: parsed.extensions)
        return (session, document)
    }

    public func unlock(with session: UnlockedSession, document: VaultDocument) {
        self.key = session.key
        self.salt = session.salt
        self.cipher = session.cipher
        self.parameters = session.parameters
        self.extensions = session.extensions
        self.document = mergeWithDisk(document)
        self.isUnlocked = true
    }

    /// Combines a caller-supplied document with what is already on disk, keeping
    /// the richer of the two. Reopening a saved vault therefore preserves the
    /// wrapped recovery key and any unknown metadata.
    private func mergeWithDisk(_ incoming: VaultDocument) -> VaultDocument {
        guard let vaultKey = key,
              let onDisk = try? AtomicFileStore.read(from: documentURL),
              let stored = try? VaultFormat.parseEnvelope(onDisk),
              let plaintext = try? VaultFormat.decrypt(payload: stored.payload, key: vaultKey,
                                                       cipher: stored.cipher),
              var decoded = try? VaultSerializer.decode(plaintext)
        else { return incoming }

        // Values supplied by the caller win; anything only the file knows about
        // (the wrapped recovery key, foreign fields) is kept.
        for (name, value) in incoming.rootUnknownKeys where decoded.rootUnknownKeys[name] == nil {
            decoded.rootUnknownKeys[name] = value
        }
        for (service, values) in incoming.serviceUnknownKeys {
            var existing = decoded.serviceUnknownKeys[service] ?? [:]
            for (name, value) in values where existing[name] == nil { existing[name] = value }
            decoded.serviceUnknownKeys[service] = existing
        }
        if !incoming.services.isEmpty { decoded.services = incoming.services }
        return decoded
    }

    /// The recovery key, unwrapped with the master password (only while unlocked).
    public func recoveryKey(password: String) -> String? {
        guard isUnlocked else { return nil }
        let stored = document.rootUnknownKeys["x-vaultflow"]?["recovery"]
        if let key = stored.flatMap({ SecBackup.unwrap($0, password: password) }) {
            return key
        }
        // Older vaults may only carry a hint — fall back to it.
        return stored?["hint"]?.stringValue
    }

    /// Replaces the stored recovery key with a freshly generated one.
    @discardableResult
    public func regenerateRecoveryKey(password: String) throws -> String {
        guard isUnlocked else { throw VaultStoreError.locked }
        let key = RecoveryKey.generate()
        guard let wrapped = try? SecBackup.wrapRecoveryKey(key, for: password) else {
            throw CryptoError.malformedKeyMaterial
        }
        if document.rootUnknownKeys["x-vaultflow"] == nil {
            document.rootUnknownKeys["x-vaultflow"] = .object(["app": .string("VaultFlow for macOS")])
        }
        document.rootUnknownKeys["x-vaultflow"]?["recovery"] = wrapped
        try save()
        return key
    }

    /// Merges another document (an imported legacy vault) into this one.
    @discardableResult
    public func merge(_ other: VaultDocument, suffixDuplicates: Bool = true) throws -> Int {
        guard isUnlocked else { throw VaultStoreError.locked }
        var added = 0
        for (service, incoming) in other.services {
            var bucket = document.services[service] ?? []
            for var entry in incoming {
                if suffixDuplicates, bucket.contains(where: { $0.username == entry.username && !entry.username.isEmpty }) {
                    entry.username += " (imported)"
                }
                bucket.append(entry)
                added += 1
            }
            document.services[service] = bucket
        }
        try save()
        return added
    }

    /// Swaps the backing file, e.g. after choosing another vault in onboarding.
    public func openFile(at url: URL, session: UnlockedSession, document: VaultDocument) {
        documentURL = url
        unlock(with: session, document: document)
    }

    public func lock() {
        if var secret = key {
            for i in 0..<secret.count { secret[i] = 0 }
        }
        self.key = nil
        self.document = VaultDocument()
        self.isUnlocked = false
    }

    // MARK: Persistence

    /// Re-encrypts and writes the document atomically.
    @discardableResult
    public func save(forceNewSalt: Bool = false) throws -> Int {
        guard let key else { throw VaultStoreError.locked }
        if forceNewSalt {
            salt = SecureRandom.bytes(16)
        }
        document.modifiedAt = Date()
        let plaintext = try VaultSerializer.encode(document)
        let payload = try VaultFormat.encrypt(plaintext: plaintext, key: key, cipher: cipher)
        let envelope = VaultFormat.makeEnvelope(salt: salt, payload: payload, cipher: cipher,
                                                parameters: parameters, extensions: extensions)
        try AtomicFileStore.write(try envelope.encodedData(pretty: true), to: documentURL)
        revision += 1
        return revision
    }

    // MARK: Mutations

    public func entries() -> [Entry] { document.allEntries }

    public func entries(service: String) -> [Entry] { document.services[service] ?? [] }

    public func allServices() -> [String] { document.services.keys.sorted() }

    @discardableResult
    public func add(_ entry: Entry) throws -> Entry {
        guard isUnlocked else { throw VaultStoreError.locked }
        let trimmed = entry.service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultStoreError.serviceNameRequired }
        var newEntry = entry
        newEntry.service = trimmed
        var list = document.services[trimmed, default: []]
        list.append(newEntry)
        document.services[trimmed] = list
        return newEntry
    }

    @discardableResult
    public func update(_ entry: Entry) throws -> Entry {
        guard isUnlocked else { throw VaultStoreError.locked }
        guard let oldService = document.services.first(where: { $0.value.contains(where: { $0.id == entry.id }) })?.key
        else { throw VaultStoreError.entryNotFound }

        // Remove from the old service bucket.
        if var list = document.services[oldService] {
            list.removeAll { $0.id == entry.id }
            document.services[oldService] = list.isEmpty ? nil : list
        }
        var updated = entry
        updated.service = entry.service.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        var list = document.services[updated.service, default: []]
        list.append(updated)
        document.services[updated.service] = list
        return updated
    }

    public func delete(id: UUID) throws {
        guard isUnlocked else { throw VaultStoreError.locked }
        for (service, entries) in document.services {
            if let index = entries.firstIndex(where: { $0.id == id }) {
                var list = entries
                list.remove(at: index)
                document.services[service] = list.isEmpty ? nil : list
                return
            }
        }
        throw VaultStoreError.entryNotFound
    }

    public func replaceAll(_ document: VaultDocument) {
        self.document = document
    }

    public func snapshot() -> VaultDocument { document }

    // MARK: Password change

    /// Re-encrypts the whole vault under a new password with a fresh salt.
    public func changePassword(to newPassword: String, iterations: Int? = nil) throws {
        guard isUnlocked else { throw VaultStoreError.locked }
        let newSalt = SecureRandom.bytes(16)
        var params = parameters
        if let iterations { params.iterations = iterations }
        let newKey = try VaultFormat.deriveKey(password: newPassword, salt: newSalt, parameters: params)
        key = newKey
        salt = newSalt
        parameters = params
        if var meta = document.rootUnknownKeys["x-vaultflow"]?.objectValue {
            if let recovery = try? SecBackup.wrapRecoveryKey(RecoveryKey.regenerate(for: document), for: newPassword) {
                meta["recovery"] = recovery
            }
            document.rootUnknownKeys["x-vaultflow"] = .object(meta)
        }
        try save()
    }
}

// MARK: - Recovery key

public enum RecoveryKey {
    /// 256-bit key rendered as BIP-39 words for human transcription.
    public static func generate() -> String {
        var words: [String] = []
        for _ in 0..<8 {
            words.append(Wordlist.words[SecureRandom.int(Wordlist.words.count)])
        }
        return words.joined(separator: " ")
    }

    public static func regenerate(for document: VaultDocument) -> String {
        generate()
    }

    public static func normalize(_ input: String) -> [String] {
        input.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "\n" })
            .map(String.init)
    }

    public static func isValid(_ input: String) -> Bool {
        let words = normalize(input)
        guard words.count == 8 else { return false }
        let dictionary = Set(Wordlist.words)
        return words.allSatisfy { dictionary.contains($0) }
    }
}

/// Wraps the recovery key with the master password so it can be shown again.
public enum SecBackup {
    public static func wrapRecoveryKey(_ recoveryKey: String, for password: String) throws -> JSONValue {
        let salt = SecureRandom.bytes(16)
        let wrappingKey = try PasswordKeyDerivation.pbkdf2SHA256(
            password: password, salt: salt, iterations: 200_000, keyLengthBytes: 32)
        let payload = try AESGCM.seal(Data(recoveryKey.utf8), key: wrappingKey,
                                      nonce: SecureRandom.bytes(12))
        return .object([
            "salt": .string(VaultBase64.urlSafeEncode(salt)),
            "payload": .string(VaultBase64.urlSafeEncode(payload)),
            "style": .string("bip39-8")
        ])
    }

    public static func unwrap(_ value: JSONValue, password: String) -> String? {
        guard let saltString = value["salt"]?.stringValue,
              let payloadString = value["payload"]?.stringValue,
              let salt = VaultBase64.decode(saltString),
              let payload = VaultBase64.decode(payloadString),
              let wrappingKey = try? PasswordKeyDerivation.pbkdf2SHA256(
                password: password, salt: salt, iterations: 200_000, keyLengthBytes: 32),
              let plain = try? AESGCM.open(payload, key: wrappingKey)
        else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }
}
