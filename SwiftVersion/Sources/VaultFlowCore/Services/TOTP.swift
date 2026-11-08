// TOTP.swift
// VaultFlow · RFC 6238 time-based one-time passwords
//
// Accepts the usual otpauth:// URIs (as embedded in QR codes) and bare
// Base32 secrets. Supports SHA-1/SHA-256/SHA-512, 6–8 digits and any period.

import Foundation
import CryptoKit

public struct TOTPConfiguration: Equatable, Sendable {
    public var secret: Data          // raw key bytes
    public var algorithm: Algorithm
    public var digits: Int
    public var period: Int
    public var issuer: String
    public var account: String

    public enum Algorithm: String, Sendable, CaseIterable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"

        public var title: String { rawValue }
    }

    public init(secret: Data, algorithm: Algorithm = .sha1, digits: Int = 6,
                period: Int = 30, issuer: String = "", account: String = "") {
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.issuer = issuer
        self.account = account
    }

    /// Parses `otpauth://totp/Issuer:account?secret=…&digits=6&period=30&algorithm=SHA1`
    /// or a plain Base32 secret.
    public static func parse(_ input: String) -> TOTPConfiguration? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("otpauth://") {
            guard let components = URLComponents(string: trimmed) else { return nil }
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name.lowercased(), $0.value ?? "")
            })
            guard let secretString = query["secret"], let secret = Base32.decode(secretString) else { return nil }
            let digits = Int(query["digits"] ?? "") ?? 6
            let period = Int(query["period"] ?? "") ?? 30
            let algorithm = Algorithm(rawValue: (query["algorithm"] ?? "SHA1").uppercased()) ?? .sha1
            let label = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .removingPercentEncoding ?? ""
            let parts = label.split(separator: ":", maxSplits: 1).map(String.init)
            let issuer = query["issuer"] ?? (parts.count > 1 ? parts[0] : "")
            let account = parts.count > 1 ? parts[1] : label
            return TOTPConfiguration(secret: secret, algorithm: algorithm,
                                     digits: min(8, max(6, digits)),
                                     period: max(10, period),
                                     issuer: issuer, account: account)
        }

        guard let secret = Base32.decode(trimmed) else { return nil }
        return TOTPConfiguration(secret: secret)
    }
}

public enum TOTP {
    public static func code(for configuration: TOTPConfiguration, at date: Date = Date()) -> String {
        let counter = UInt64(date.timeIntervalSince1970) / UInt64(configuration.period)
        return code(for: configuration, counter: counter)
    }

    public static func code(for configuration: TOTPConfiguration, counter: UInt64) -> String {
        var bigEndian = counter.bigEndian
        let message = Data(bytes: &bigEndian, count: 8)
        let mac: Data
        switch configuration.algorithm {
        case .sha1: mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: configuration.secret)))
        case .sha256: mac = Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: configuration.secret)))
        case .sha512: mac = Data(HMAC<SHA512>.authenticationCode(for: message, using: SymmetricKey(data: configuration.secret)))
        }
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let binary = (UInt32(mac[offset] & 0x7f) << 24)
            | (UInt32(mac[offset + 1]) << 16)
            | (UInt32(mac[offset + 2]) << 8)
            | UInt32(mac[offset + 3])
        let modulus = UInt64(pow(10.0, Double(configuration.digits)))
        let value = UInt64(binary) % modulus
        return String(format: "%0\(configuration.digits)llu", value)
    }

    /// Seconds until the current code expires.
    public static func secondsRemaining(for configuration: TOTPConfiguration, at date: Date = Date()) -> Int {
        let period = configuration.period
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    /// Formatted "123 456".
    public static func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<mid]) \(code[mid...])"
    }
}

public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func decode(_ input: String) -> Data? {
        let cleaned = input.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        guard !cleaned.isEmpty else { return nil }
        // Tolerate lowercase / padding already trimmed.
        var bits = 0
        var value = 0
        var output = Data()
        for character in cleaned {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                output.append(UInt8((value >> (bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return output.isEmpty ? nil : output
    }

    public static func encode(_ data: Data) -> String {
        var bits = 0
        var value = 0
        var output = ""
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(value >> (bits - 5)) & 0x1f])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(alphabet[(value << (5 - bits)) & 0x1f])
        }
        return output
    }
}
