// VaultFormat.swift
// VaultFlow · On-disk vault format and versioned file envelopes
//
// Same *family* of format as the Python (Fernet) and Java (AES-256-GCM)
// versions so the three implementations can read each other's files:
//
//   { "salt": "<urlsafe-base64 16 bytes>", "vault": "<urlsafe-base64 payload>" }
//
// VaultFlow adds a small, optional `meta` object for forward-compatibility and
// automatic format detection. Keys unknown to us are preserved verbatim.

import Foundation
import CommonCrypto

/// Which cipher produced a given envelope.
public enum CipherKind: String, Sendable {
    /// AES-256-GCM, payload = nonce(12) ‖ ciphertext ‖ tag(16). Matches Java.
    case aes256gcm
    /// AES-128-CBC + HMAC-SHA256 (Fernet). Matches Python.
    case fernet
}

public struct EncryptionParameters: Sendable {
    public var iterations: Int
    public var saltLength: Int
    /// KDF identifier from `meta.kdf` (`pbkdf2-sha256`, `scrypt`).
    public var kdf: String
    public var scryptN: Int
    public var scryptR: Int
    public var scryptP: Int

    public init(iterations: Int = VaultFormat.defaultIterations,
                saltLength: Int = 16,
                kdf: String = "pbkdf2-sha256",
                scryptN: Int = 1 << 14, scryptR: Int = 8, scryptP: Int = 1) {
        self.iterations = iterations
        self.saltLength = saltLength
        self.kdf = kdf
        self.scryptN = scryptN
        self.scryptR = scryptR
        self.scryptP = scryptP
    }
}

public enum VaultFormatError: LocalizedError {
    case notAVaultFile
    case missingSalt
    case missingVaultPayload
    case unsupportedVersion(Int)
    case unknownKDF(String)
    case wrongPassword
    case corruptPayload

    public var errorDescription: String? {
        switch self {
        case .notAVaultFile: return "This isn't a VaultFlow vault file."
        case .missingSalt: return "The vault file is missing its salt."
        case .missingVaultPayload: return "The vault file is missing its encrypted payload."
        case .unsupportedVersion(let v): return "This vault was created by a newer version (format v\(v)). Update VaultFlow to open it."
        case .unknownKDF(let k): return "Unsupported key derivation function: “\(k)”."
        case .wrongPassword: return "Incorrect master password."
        case .corruptPayload: return "The vault data is corrupted."
        }
    }
}

public enum VaultFormat {
    /// Matches the Python and Java versions (480 000 iterations).
    public static let defaultIterations = 480_000
    public static let currentVersion = 2
    public static let defaultCipher: CipherKind = .aes256gcm

    // MARK: Key derivation

    /// Derives the 32-byte sealing key for a password and salt.
    public static func deriveKey(
        password: String,
        salt: Data,
        parameters: EncryptionParameters
    ) throws -> Data {
        switch parameters.kdf {
        case "pbkdf2-sha256", "pbkdf2", "":
            return try PasswordKeyDerivation.pbkdf2SHA256(
                password: password,
                salt: salt,
                iterations: parameters.iterations,
                keyLengthBytes: 32
            )
        case "scrypt":
            return try Scrypt.derive(
                password: Data(password.utf8),
                salt: salt,
                n: parameters.scryptN,
                r: parameters.scryptR,
                p: parameters.scryptP,
                keyLength: 32
            )
        default:
            throw VaultFormatError.unknownKDF(parameters.kdf)
        }
    }

    // MARK: Payload encryption

    /// Encrypts the plaintext vault JSON with a fresh nonce/IV per save.
    public static func encrypt(
        plaintext: Data,
        key: Data,
        cipher: CipherKind = .aes256gcm
    ) throws -> Data {
        switch cipher {
        case .aes256gcm:
            return try AESGCM.seal(plaintext, key: key, nonce: SecureRandom.bytes(12))
        case .fernet:
            return try FernetCompat.encrypt(plaintext, key: key)
        }
    }

    public static func decrypt(
        payload: Data,
        key: Data,
        cipher: CipherKind
    ) throws -> Data {
        switch cipher {
        case .aes256gcm:
            // Our own vaults are nonce(12) ‖ ct ‖ tag; the Java version writes
            // iv(16) ‖ ct ‖ tag. Accept both so old vaults open transparently.
            if let plain = try? AESGCM.open(payload, key: key) { return plain }
            if payload.count > 32, (payload.count - 32) % 16 == 0 {
                return try AESGCM.open(payload.dropFirst(16), key: key, nonceLength: 16)
            }
            throw CryptoError.authenticationFailed
        case .fernet:
            return try FernetCompat.decrypt(payload, key: key)
        }
    }

    // MARK: Envelope

    /// Builds the JSON envelope written to disk.
    public static func makeEnvelope(
        salt: Data,
        payload: Data,
        cipher: CipherKind,
        parameters: EncryptionParameters,
        extensions: [String: JSONValue] = [:]
    ) -> JSONValue {
        var meta: [String: JSONValue] = [
            "app": .string("VaultFlow"),
            "platform": .string("macOS"),
            "version": .int(currentVersion),
            "cipher": .string(cipher.rawValue),
            "kdf": .string(parameters.kdf),
            "iterations": .int(parameters.iterations)
        ]
        if parameters.kdf == "scrypt" {
            meta["scryptN"] = .int(parameters.scryptN)
            meta["scryptR"] = .int(parameters.scryptR)
            meta["scryptP"] = .int(parameters.scryptP)
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
        meta["updatedAt"] = .string(stamp)

        var root: [String: JSONValue] = [
            "salt": .string(VaultBase64.urlSafeEncode(salt)),
            "vault": .string(VaultBase64.urlSafeEncode(payload)),
            "meta": .object(meta)
        ]
        for (key, value) in extensions { root[key] = value }
        return .object(root)
    }

    // MARK: Parsing

    public struct ParsedEnvelope: Sendable {
        public var salt: Data
        public var payload: Data
        public var cipher: CipherKind
        public var parameters: EncryptionParameters
        public var extensions: [String: JSONValue]
        public var createdAt: Date?
    }

    /// Parses any vault file from any version of VaultFlow.
    public static func parseEnvelope(_ data: Data) throws -> ParsedEnvelope {
        let root: JSONValue
        do {
            root = try JSONValue.decode(data)
        } catch {
            throw VaultFormatError.notAVaultFile
        }
        guard let object = root.objectValue else { throw VaultFormatError.notAVaultFile }

        guard let saltString = object["salt"]?.stringValue,
              let salt = VaultBase64.decode(saltString), !salt.isEmpty
        else { throw VaultFormatError.missingSalt }

        guard let vaultString = object["vault"]?.stringValue,
              let payload = VaultBase64.decode(vaultString), !payload.isEmpty
        else { throw VaultFormatError.missingVaultPayload }

        let meta = object["meta"]?.objectValue
        let version = meta?["version"]?.intValue ?? 1
        guard version <= currentVersion else { throw VaultFormatError.unsupportedVersion(version) }

        var cipher: CipherKind = .aes256gcm
        if let cipherName = meta?["cipher"]?.stringValue, let parsed = CipherKind(rawValue: cipherName) {
            cipher = parsed
        } else {
            // No metadata: guess from payload shape. Fernet payloads start with
            // 0x80 and are at least 57 bytes; GCM output is typically longer and
            // never legitimately starts with 0x80 followed by a 15-byte gap.
            if payload.count >= 57, payload.first == 0x80 { cipher = .fernet }
        }

        var parameters = EncryptionParameters()
        if let meta {
            parameters.kdf = meta["kdf"]?.stringValue ?? "pbkdf2-sha256"
            parameters.iterations = meta["iterations"]?.intValue ?? defaultIterations
            if let n = meta["scryptN"]?.intValue { parameters.scryptN = n }
            if let r = meta["scryptR"]?.intValue { parameters.scryptR = r }
            if let p = meta["scryptP"]?.intValue { parameters.scryptP = p }
        }

        var extensions = object
        extensions.removeValue(forKey: "salt")
        extensions.removeValue(forKey: "vault")
        extensions.removeValue(forKey: "meta")

        let createdAt = object["createdAt"]?.stringValue
            .flatMap { ISO8601DateFormatter().date(from: $0) }

        return ParsedEnvelope(salt: salt, payload: payload, cipher: cipher,
                              parameters: parameters, extensions: extensions,
                              createdAt: createdAt)
    }

    /// True when `data` looks like a *plaintext* legacy vault (a bare
    /// `{service: {accounts: [...]}}` object with no salt/vault keys).
    public static func looksLikePlaintextVault(_ data: Data) -> Bool {
        guard let root = try? JSONValue.decode(data), let object = root.objectValue else { return false }
        if object["salt"] != nil || object["vault"] != nil { return false }
        for (_, value) in object {
            if value.objectValue?["accounts"] != nil { return true }
        }
        return false
    }
}

// MARK: - Fernet compatibility (writing Python-compatible tokens)

enum FernetCompat {
    static func encrypt(_ plaintext: Data, key: Data) throws -> Data {
        guard key.count == 32 else { throw FernetError.invalidKey }
        let signingKey = key.prefix(16)
        let encryptionKey = key.suffix(16)
        let iv = SecureRandom.bytes(16)
        var timestamp = UInt64(Date().timeIntervalSince1970).bigEndian
        let timestampBytes = Data(bytes: &timestamp, count: 8)

        let header = Data([0x80]) + timestampBytes + iv
        let ciphertext = try AES128CBC.encrypt(plaintext, key: Data(encryptionKey), iv: iv)
        let message = header + ciphertext
        let mac = Hashes.hmacSHA256(key: Data(signingKey), message: message)
        return message + mac
    }

    static func decrypt(_ token: Data, key: Data) throws -> Data {
        guard key.count == 32 else { throw FernetError.invalidKey }
        guard token.count >= 1 + 8 + 16 + 16 + 32, token.first == 0x80 else { throw FernetError.invalidToken }
        let signingKey = key.prefix(16)
        let encryptionKey = key.suffix(16)
        let message = token.dropLast(32)
        let mac = token.suffix(32)
        let expected = Hashes.hmacSHA256(key: Data(signingKey), message: Data(message))
        guard Hashes.constantTimeEquals(expected, Data(mac)) else { throw CryptoError.authenticationFailed }
        let body = message.dropFirst(9)
        let iv = Data(body.prefix(16))
        let ciphertext = Data(body.dropFirst(16))
        return try AES128CBC.decrypt(ciphertext, key: Data(encryptionKey), iv: iv)
    }
}

extension AES128CBC {
    static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16, iv.count == 16 else { throw FernetError.invalidKey }
        let outLength = plaintext.count + kCCBlockSizeAES128
        var out = Data(count: outLength)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBuf in
            plaintext.withUnsafeBytes { dataBuf in
                key.withUnsafeBytes { keyBuf in
                    iv.withUnsafeBytes { ivBuf in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, key.count,
                            ivBuf.baseAddress,
                            dataBuf.baseAddress, plaintext.count,
                            outBuf.baseAddress, outLength,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw FernetError.decryptionFailed }
        out.removeSubrange(moved..<out.count)
        return out
    }
}
