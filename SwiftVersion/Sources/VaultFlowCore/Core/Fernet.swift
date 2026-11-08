// Fernet.swift
// VaultFlow · Fernet (spec 1) decryption
//
// The Python version encrypts with `cryptography.fernet.Fernet`:
//   key      = urlsafe_b64(pbkdf2_sha256(master, salt, 480000))  → 32 raw bytes
//   signing  = key[0..<16]   (HMAC-SHA256)
//   encryption = key[16..<32] (AES-128-CBC, PKCS7)
//   token    = b64url( version(1)=0x80 ‖ timestamp(8, big endian) ‖ iv(16) ‖ ciphertext ‖ hmac(32) )
//
// We implement verify-then-decrypt using CryptoKit's HMAC + CommonCrypto's
// AES-CBC (Security/CommonCrypto) so imported Python vaults open natively.

import Foundation
import CommonCrypto

public enum FernetError: LocalizedError {
    case invalidToken
    case badVersion
    case badHMAC
    case decryptionFailed
    case invalidKey

    public var errorDescription: String? {
        switch self {
        case .invalidToken: return "The Fernet token is malformed."
        case .badVersion: return "Unsupported Fernet version."
        case .badHMAC: return "Fernet token signature mismatch (wrong password or corrupted file)."
        case .decryptionFailed: return "Fernet decryption failed."
        case .invalidKey: return "Fernet key must be 32 bytes."
        }
    }
}

public enum Fernet {
    public static func decrypt(token: String, key: Data) throws -> Data {
        guard key.count == 32 else { throw FernetError.invalidKey }
        guard let raw = VaultBase64.decode(token) else {
            // Python's Fernet tokens are urlsafe base64 *with* padding.
            throw FernetError.invalidToken
        }
        guard raw.count > 1 + 8 + 16 + 16 + 32 - 1, raw.count >= 1 + 8 + 16 + 16 + 32 else {
            throw FernetError.invalidToken
        }
        let version = raw[raw.startIndex]
        guard version == 0x80 else { throw FernetError.badVersion }

        let signingKey = key.prefix(16)
        let encryptionKey = key.suffix(16)
        let message = raw.dropLast(32)
        let mac = Data(raw.suffix(32))
        let expected = Hashes.hmacSHA256(key: Data(signingKey), message: Data(message))
        guard Hashes.constantTimeEquals(expected, mac) else { throw FernetError.badHMAC }

        let body = message.dropFirst(1 + 8) // version + timestamp
        let iv = Data(body.prefix(16))
        let ciphertext = Data(body.dropFirst(16))
        return try AES128CBC.decrypt(Data(ciphertext), key: Data(encryptionKey), iv: iv)
    }
}

enum AES128CBC {
    static func decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == 16, iv.count == 16 else { throw FernetError.invalidKey }
        let outLength = ciphertext.count + kCCBlockSizeAES128
        var out = Data(count: outLength)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBuf in
            ciphertext.withUnsafeBytes { dataBuf in
                key.withUnsafeBytes { keyBuf in
                    iv.withUnsafeBytes { ivBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress, key.count,
                            ivBuf.baseAddress,
                            dataBuf.baseAddress, ciphertext.count,
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
