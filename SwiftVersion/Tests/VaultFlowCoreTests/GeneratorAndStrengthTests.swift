// GeneratorAndStrengthTests.swift
// VaultFlow · Password generator, strength meter and TOTP (RFC 6238)

import XCTest
@testable import VaultFlowCore

final class GeneratorAndStrengthTests: XCTestCase {
    func testCharacterPasswordHonoursOptions() throws {
        var options = GeneratorOptions()
        options.mode = .characters
        options.characterSets = [.lowercase, .digits]
        options.length = 32
        options.requireEveryClass = true
        let password = try PasswordGenerator.generate(options: options)
        XCTAssertEqual(password.count, 32)
        XCTAssertTrue(password.allSatisfy { $0.isLowercase || $0.isNumber })
        XCTAssertTrue(password.contains(where: \.isNumber))
    }

    func testAmbiguousCharactersAreExcludedOnRequest() throws {
        var options = GeneratorOptions()
        options.mode = .characters
        options.characterSets = [.uppercase, .lowercase, .digits, .symbols]
        options.length = 64
        options.avoidAmbiguous = true
        for _ in 0..<10 {
            let password = try PasswordGenerator.generate(options: options)
            XCTAssertTrue(password.allSatisfy { !PasswordCharacterSet.ambiguousCharacters.contains($0) })
        }
    }

    func testPassphraseUsesWordlist() throws {
        var options = GeneratorOptions()
        options.mode = .passphrase
        options.wordCount = 5
        options.separator = "-"
        options.capitalizeWords = false
        options.includeDigitInPassphrase = false
        options.includeSymbolInPassphrase = false
        let phrase = try PasswordGenerator.generate(options: options)
        let words = phrase.split(separator: "-").map(String.init)
        XCTAssertEqual(words.count, 5)
        XCTAssertTrue(words.allSatisfy { Wordlist.words.contains($0) })
    }

    func testPINLength() throws {
        var options = GeneratorOptions()
        options.mode = .pin
        options.pinLength = 8
        let pin = try PasswordGenerator.generate(options: options)
        XCTAssertEqual(pin.count, 8)
        XCTAssertTrue(pin.allSatisfy(\.isNumber))
    }

    func testEmptyCharacterSetThrows() {
        var options = GeneratorOptions()
        options.mode = .characters
        options.characterSets = []
        XCTAssertThrowsError(try PasswordGenerator.generate(options: options))
    }

    func testGenerationIsRandom() throws {
        var options = GeneratorOptions()
        options.length = 24
        let samples = try (0..<40).map { _ in try PasswordGenerator.generate(options: options) }
        XCTAssertEqual(Set(samples).count, 40)
    }

    func testStrengthRanksCommonPasswordsLowest() {
        XCTAssertEqual(PasswordStrength.evaluate("password").score, .extremelyWeak)
        XCTAssertEqual(PasswordStrength.evaluate("123456").score, .extremelyWeak)
        XCTAssertLessThan(PasswordStrength.evaluate("Summer2024!").bits,
                          PasswordStrength.evaluate("wA7#tR2$kLp9!zQx").bits)
        XCTAssertEqual(PasswordStrength.evaluate("wA7#tR2$kLp9!zQx").score, .excellent)
    }

    func testStrengthFlagsRepeatsAndSequences() {
        let result = PasswordStrength.evaluate("aaaaaaaaaaaa")
        XCTAssertLessThan(result.bits, 30)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testPassphraseEntropyScalesWithWordCount() {
        let short = PasswordStrength.evaluate("amber-cobalt-jungle-orbit")
        let long = PasswordStrength.evaluate("amber-cobalt-jungle-orbit-vector-saddle-mint")
        XCTAssertGreaterThan(long.bits, short.bits)
    }

    // MARK: - TOTP

    func testRFC6238SHA1Vectors() throws {
        let secret = try XCTUnwrap(Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"))
        let configuration = TOTPConfiguration(secret: secret, algorithm: .sha1, digits: 8, period: 30,
                                              issuer: "test", account: "test")
        let vectors: [(TimeInterval, String)] = [
            (59, "94287082"),
            (1111111109, "07081804"),
            (1111111111, "14050471"),
            (1234567890, "89005924"),
            (2000000000, "69279037"),
            (20000000000, "65353130")
        ]
        for (time, expected) in vectors {
            XCTAssertEqual(TOTP.code(for: configuration, at: Date(timeIntervalSince1970: time)), expected)
        }
    }

    func testTOTPParseFromURL() throws {
        let configuration = try XCTUnwrap(TOTPConfiguration.parse(
            "otpauth://totp/GitHub:octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30"))
        XCTAssertEqual(configuration.issuer, "GitHub")
        XCTAssertEqual(configuration.account, "octocat")
        XCTAssertEqual(configuration.digits, 6)
        XCTAssertEqual(TOTP.formatted(TOTP.code(for: configuration)).count, 7) // "123 456"
    }

    func testTOTPCountdown() throws {
        let secret = try XCTUnwrap(Base32.decode("JBSWY3DPEHPK3PXP"))
        let configuration = TOTPConfiguration(secret: secret, algorithm: .sha1, digits: 6, period: 30,
                                              issuer: "", account: "")
        XCTAssertEqual(TOTP.secondsRemaining(for: configuration, at: Date(timeIntervalSince1970: 30)), 30)
        XCTAssertEqual(TOTP.secondsRemaining(for: configuration, at: Date(timeIntervalSince1970: 45)), 15)
    }

    func testBase32RoundTrip() throws {
        let data = Data("VaultFlow".utf8)
        XCTAssertEqual(try XCTUnwrap(Base32.decode(Base32.encode(data))), data)
    }
}
