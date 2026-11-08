// Crypto.swift
// VaultFlow · Cryptographic primitives
//
// Every primitive here is backed by Apple's own implementations:
//   • AES-256-GCM, HKDF  → CryptoKit
//   • PBKDF2-HMAC-SHA256 → CommonCrypto (via Security.framework)
//   • Randomness         → SecRandomCopyBytes (CSPRNG)
//
// No third-party crypto is used.

import Foundation
import CryptoKit
import Security
import CommonCrypto

public enum CryptoError: LocalizedError, Equatable {
    case randomFailed(Int32)
    case keyDerivationFailed
    case authenticationFailed
    case malformedCiphertext
    case malformedKeyMaterial

    public var errorDescription: String? {
        switch self {
        case .randomFailed(let status): return "Secure random generation failed (OSStatus \(status))."
        case .keyDerivationFailed: return "Key derivation failed."
        case .authenticationFailed: return "Incorrect password or the vault has been tampered with."
        case .malformedCiphertext: return "The encrypted payload is malformed."
        case .malformedKeyMaterial: return "The encryption key is malformed."
        }
    }
}

public enum SecureRandom {
    /// Cryptographically secure random bytes from the system CSPRNG.
    public static func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }

    /// Uniformly random integer in `0..<upperBound` using rejection sampling.
    ///
    /// Rejection sampling (instead of `Int.random`) keeps us independent of
    /// the generator's internals and 100% unbiased.
    public static func int(_ upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        if upperBound == 1 { return 0 }
        // Number of random bytes needed so 2^(8n) >= upperBound.
        var byteCount = 1
        while (1 << (8 * byteCount)) < upperBound && byteCount < 8 { byteCount += 1 }
        let limit = UInt64(upperBound)
        let threshold = (UInt64.max - limit + 1) % limit // drop values below this
        while true {
            var value: UInt64 = 0
            let raw = bytes(byteCount)
            for i in 0..<byteCount { value = (value << 8) | UInt64(raw[raw.startIndex + i]) }
            value &= (byteCount == 8) ? UInt64.max : ((1 << (8 * byteCount)) - 1)
            if value >= threshold { return Int(value % limit) }
        }
    }

    /// Random `Double` in `[0, 1)`.
    public static func unitDouble() -> Double {
        Double(int(1 << 30)) / Double(1 << 30)
    }
}

public enum PasswordKeyDerivation {
    /// PBKDF2-HMAC-SHA256. Matches the parameters used by the Python
    /// (cryptography/PBKDF2HMAC via OpenSSL) and Java (SecretKeyFactory
    /// "PBKDF2WithHmacSHA256") implementations, so a vault created by any
    /// version can be unlocked by any other.
    public static func pbkdf2SHA256(
        password: String,
        salt: Data,
        iterations: Int,
        keyLengthBytes: Int = 32
    ) throws -> Data {
        try pbkdf2SHA256(passwordBytes: Data(password.utf8), salt: salt,
                        iterations: iterations, keyLengthBytes: keyLengthBytes)
    }

    /// PBKDF2-HMAC-SHA256 over arbitrary password bytes (used by scrypt, whose
    /// input is a byte string rather than text).
    public static func pbkdf2SHA256(
        passwordBytes: Data,
        salt: Data,
        iterations: Int,
        keyLengthBytes: Int = 32
    ) throws -> Data {
        precondition(iterations > 0 && keyLengthBytes > 0)
        var derived = Data(count: keyLengthBytes)
        let status: Int32 = derived.withUnsafeMutableBytes { outBuf in
            salt.withUnsafeBytes { saltBuf in
                let pwd = [UInt8](passwordBytes)
                return pwd.withUnsafeBytes { pwdBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwdBuf.baseAddress?.assumingMemoryBound(to: Int8.self), pwd.count,
                        saltBuf.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outBuf.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLengthBytes
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return derived
    }
}

/// AES-256-GCM authenticated encryption (`"AES/GCM/NoPadding"`, 128-bit tag).
public enum AESGCM {
    /// - Parameter sealingKey: 32 bytes.
    /// - Returns: `nonce ‖ ciphertext ‖ tag`.
    public static func seal(_ plaintext: Data, key sealingKey: Data, nonce: Data) throws -> Data {
        guard sealingKey.count == 32 else { throw CryptoError.malformedKeyMaterial }
        let symmetricKey = SymmetricKey(data: sealingKey)
        guard let nonceValue = try? AES.GCM.Nonce(data: nonce) else { throw CryptoError.malformedCiphertext }
        let sealed = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonceValue)
        return sealed.nonce.withUnsafeBytes { Data($0) } + sealed.ciphertext + sealed.tag
    }

    /// Opens `nonce ‖ ciphertext ‖ tag`. Throws `authenticationFailed` when the
    /// key is wrong or any byte has been tampered with.
    ///
    /// - Parameter nonceLength: 12 for VaultFlow's own vaults, 16 for vaults
    ///   written by the Java version (which uses a 128-bit IV).
    public static func open(_ combined: Data, key sealingKey: Data, nonceLength: Int = 12) throws -> Data {
        guard sealingKey.count == 32 else { throw CryptoError.malformedKeyMaterial }
        guard combined.count > nonceLength + 16 else { throw CryptoError.malformedCiphertext }
        let nonceData = combined.prefix(nonceLength)
        let body = combined.dropFirst(nonceLength)
        let ciphertext = body.prefix(body.count - 16)
        let tag = body.suffix(16)
        let symmetricKey = SymmetricKey(data: sealingKey)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: symmetricKey)
        } catch {
            throw CryptoError.authenticationFailed
        }
    }
}

public enum Derive {
    /// HKDF-SHA256. Used to split the master key into independent
    /// sealing / verification / keychain sub-keys.
    public static func hkdf(key: Data, salt: Data, info: String, outputLength: Int = 32) -> Data {
        let hk = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: key),
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: outputLength
        )
        return hk.withUnsafeBytes { Data($0) }
    }
}

public enum Hashes {
    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func sha256Hex(_ data: Data) -> String {
        sha256(data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha1(_ data: Data) -> Data {
        Data(Insecure.SHA1.hash(data: data))
    }

    public static func sha512(_ data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }

    public static func sha1Hex(_ data: Data) -> String {
        sha1(data).map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time equality, so verification can't be timing-probed.
    public static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return diff == 0
    }

    public static func hmacSHA256(key: Data, message: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac)
    }
}

// MARK: - JSON-compatible base64
//
// The credential vault is a JSON file whose `vault` field is the raw binary
// ciphertext encoded as base64. `JSONEncoder`'s `.base64` strategy emits the
// same alphabet (with padding), which is accepted by Python's
// `base64.urlsafe_b64decode` and Java's `Base64.getUrlDecoder()`.

public enum VaultBase64 {
    public static func urlSafeEncode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    /// Accepts standard, URL-safe, padded or unpadded input.
    public static func decode(_ string: String) -> Data? {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: "-", with: "+")
             .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s, options: .ignoreUnknownCharacters)
    }
}
