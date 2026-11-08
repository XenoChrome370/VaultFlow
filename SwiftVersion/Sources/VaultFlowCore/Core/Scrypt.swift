// Scrypt.swift
// VaultFlow · RFC 7914 scrypt key derivation
//
// Used only for importing vaults hardened with scrypt (e.g. optional
// `kdf: "scrypt"` headers written by other tools). CryptoKit ships PBKDF2,
// HKDF and SHA-256 but not scrypt, so the standard implementation lives here.
//
// Layout follows the reference:
//   B  = PBKDF2-HMAC-SHA256(P, S, 1, p·128·r)
//   B' = ROMix_N,r(B) for each of the p blocks
//   DK = PBKDF2-HMAC-SHA256(P, B', 1, dkLen)

import Foundation

public enum Scrypt {
    public static func derive(
        password: Data,
        salt: Data,
        n: Int,
        r: Int,
        p: Int,
        keyLength: Int = 32
    ) throws -> Data {
        guard n > 1, n & (n - 1) == 0, r > 0, p > 0, keyLength > 0 else {
            throw CryptoError.keyDerivationFailed
        }
        // Guard against absurd memory/CPU requests from untrusted headers.
        guard r <= 64, p <= 16, n <= 1 << 20, (n * r) <= 1 << 22 else {
            throw CryptoError.keyDerivationFailed
        }

        let first = try pbkdf2(password: password, salt: salt, iterations: 1, length: p * 128 * r)
        var b = [UInt32](repeating: 0, count: first.count / 4)
        let raw = [UInt8](first)
        for i in 0..<b.count {
            // Little-endian words, as in the reference implementation.
            b[i] = UInt32(raw[i * 4])
                | (UInt32(raw[i * 4 + 1]) << 8)
                | (UInt32(raw[i * 4 + 2]) << 16)
                | (UInt32(raw[i * 4 + 3]) << 24)
        }

        let wordsPerBlock = 32 * r
        for i in 0..<p {
            let block = Array(b[(i * wordsPerBlock)..<((i + 1) * wordsPerBlock)])
            let mixed = romix(block, n: n, r: r)
            for k in 0..<wordsPerBlock { b[i * wordsPerBlock + k] = mixed[k] }
        }

        var out = [UInt8](repeating: 0, count: b.count * 4)
        for i in 0..<b.count {
            out[i * 4] = UInt8(b[i] & 0xff)
            out[i * 4 + 1] = UInt8((b[i] >> 8) & 0xff)
            out[i * 4 + 2] = UInt8((b[i] >> 16) & 0xff)
            out[i * 4 + 3] = UInt8((b[i] >> 24) & 0xff)
        }
        return try pbkdf2(password: password, salt: Data(out), iterations: 1, length: keyLength)
    }

    // MARK: Core

    private static func pbkdf2(password: Data, salt: Data, iterations: Int, length: Int) throws -> Data {
        try PasswordKeyDerivation.pbkdf2SHA256(
            passwordBytes: password,
            salt: salt,
            iterations: iterations,
            keyLengthBytes: length
        )
    }

    private static func romix(_ block: [UInt32], n: Int, r: Int) -> [UInt32] {
        let wordsPerBlock = 32 * r
        var x = block
        var v = [UInt32](repeating: 0, count: n * wordsPerBlock)

        for i in 0..<n {
            let base = i * wordsPerBlock
            for k in 0..<wordsPerBlock { v[base + k] = x[k] }
            x = blockMix(x, r: r)
        }
        for _ in 0..<n {
            let j = Int(x[(2 * r - 1) * 16] & 0x7fff_ffff) % n
            let base = j * wordsPerBlock
            for k in 0..<wordsPerBlock { x[k] ^= v[base + k] }
            x = blockMix(x, r: r)
        }
        return x
    }

    /// Salsa20/8 core, in place, operating on 16 words.
    /// Follows the reference `salsa208()` layout: column round, row round, 4 times.
    private static func salsa20_8(_ words: inout [UInt32]) {
        var x = words
        for _ in 0..<4 {
            // Column round
            x[4] ^= rotl(x[0] &+ x[12], 7)
            x[8] ^= rotl(x[4] &+ x[0], 9)
            x[12] ^= rotl(x[8] &+ x[4], 13)
            x[0] ^= rotl(x[12] &+ x[8], 18)

            x[9] ^= rotl(x[5] &+ x[1], 7)
            x[13] ^= rotl(x[9] &+ x[5], 9)
            x[1] ^= rotl(x[13] &+ x[9], 13)
            x[5] ^= rotl(x[1] &+ x[13], 18)

            x[14] ^= rotl(x[10] &+ x[6], 7)
            x[2] ^= rotl(x[14] &+ x[10], 9)
            x[6] ^= rotl(x[2] &+ x[14], 13)
            x[10] ^= rotl(x[6] &+ x[2], 18)

            x[3] ^= rotl(x[15] &+ x[11], 7)
            x[7] ^= rotl(x[3] &+ x[15], 9)
            x[11] ^= rotl(x[7] &+ x[3], 13)
            x[15] ^= rotl(x[11] &+ x[7], 18)

            // Row round
            x[1] ^= rotl(x[0] &+ x[3], 7)
            x[2] ^= rotl(x[1] &+ x[0], 9)
            x[3] ^= rotl(x[2] &+ x[1], 13)
            x[0] ^= rotl(x[3] &+ x[2], 18)

            x[6] ^= rotl(x[5] &+ x[4], 7)
            x[7] ^= rotl(x[6] &+ x[5], 9)
            x[4] ^= rotl(x[7] &+ x[6], 13)
            x[5] ^= rotl(x[4] &+ x[7], 18)

            x[11] ^= rotl(x[10] &+ x[9], 7)
            x[8] ^= rotl(x[11] &+ x[10], 9)
            x[9] ^= rotl(x[8] &+ x[11], 13)
            x[10] ^= rotl(x[9] &+ x[8], 18)

            x[12] ^= rotl(x[15] &+ x[14], 7)
            x[13] ^= rotl(x[12] &+ x[15], 9)
            x[14] ^= rotl(x[13] &+ x[12], 13)
            x[15] ^= rotl(x[14] &+ x[13], 18)
        }
        for i in 0..<16 { words[i] = words[i] &+ x[i] }
    }

    private static func blockMix(_ block: [UInt32], r: Int) -> [UInt32] {
        var x = Array(block[(2 * r - 1) * 16..<(2 * r) * 16])
        var y = [UInt32](repeating: 0, count: 32 * r)
        for i in 0..<(2 * r) {
            for k in 0..<16 { x[k] ^= block[i * 16 + k] }
            salsa20_8(&x)
            // Even blocks land in the first half, odd blocks in the second.
            let destination = (i % 2 == 0) ? (i / 2) : (r + i / 2)
            for k in 0..<16 { y[destination * 16 + k] = x[k] }
        }
        return y
    }

    @inline(__always)
    private static func rotl(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }
}
