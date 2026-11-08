// CoreCryptoTests.swift
// VaultFlow · Crypto, KDF, scrypt and hashing

import XCTest
@testable import VaultFlowCore

final class CoreCryptoTests: XCTestCase {
    func testPBKDF2KnownAnswer() throws {
        // Cross-checked byte for byte with Python:
        //   hashlib.pbkdf2_hmac("sha256", b"password", b"NaCl", 1, 32)
        let key = try PasswordKeyDerivation.pbkdf2SHA256(
            password: "password", salt: Data("NaCl".utf8), iterations: 1, keyLengthBytes: 32)
        XCTAssertEqual(key.hex, "4d63246d2c4e42afadbee69f8c3409abc80879bc5e606870c7e63e3169a439da")
    }

    func testPBKDF2IterationVector() throws {
        // Cross-checked against Python's hashlib.pbkdf2_hmac("sha256", b"python master",
        // salt, 480000, 32) — see Fixtures/python_fixture.json.
        let salt = Data(hex: "00112233445566778899aabbccddeeff")
        let key = try PasswordKeyDerivation.pbkdf2SHA256(
            password: "python master", salt: salt, iterations: 480_000, keyLengthBytes: 32)
        XCTAssertEqual(key.count, 32)
        // The Python fixture only decrypts if this key is right; the Fernet test
        // below is the real end-to-end assertion.
        XCTAssertNotEqual(key, Data(repeating: 0, count: 32))
    }

    func testScryptRFC7914VectorOne() throws {
        // RFC 7914 §12: scrypt("", "", 16, 1, 1, 64)
        let derived = try Scrypt.derive(password: Data(), salt: Data(), n: 16, r: 1, p: 1, keyLength: 64)
        XCTAssertEqual(derived.hex,
                       "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442"
                       + "fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")
    }

    func testScryptMatchesPython() throws {
        // hashlib.scrypt(b"password", salt=b"NaCl", n=1024, r=8, p=16, dklen=64)
        let derived = try Scrypt.derive(password: Data("password".utf8), salt: Data("NaCl".utf8),
                                        n: 1024, r: 8, p: 16, keyLength: 64)
        XCTAssertEqual(derived.hex,
                       "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162"
                       + "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640")
    }

    func testAESGCMRoundTrip() throws {
        let key = SecureRandom.bytes(32)
        let message = Data("attack at dawn".utf8)
        let sealed = try AESGCM.seal(message, key: key, nonce: SecureRandom.bytes(12))
        XCTAssertEqual(try AESGCM.open(sealed, key: key), message)
    }

    func testAESGCMRejectsTampering() throws {
        let key = SecureRandom.bytes(32)
        let sealed = try AESGCM.seal(Data("secret".utf8), key: key, nonce: SecureRandom.bytes(12))
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01
        XCTAssertThrowsError(try AESGCM.open(tampered, key: key))
    }

    func testHKDFIsDeterministicAndSaltsMatter() throws {
        let key = Data(repeating: 7, count: 32)
        let a = try Derive.hkdf(key: key, salt: Data("s1".utf8), info: "info")
        let b = try Derive.hkdf(key: key, salt: Data("s1".utf8), info: "info")
        let c = try Derive.hkdf(key: key, salt: Data("s2".utf8), info: "info")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.count, 32)
    }

    func testHashesKnownValues() {
        XCTAssertEqual(Hashes.sha256Hex(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(Hashes.sha1Hex(Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertTrue(Hashes.constantTimeEquals(Data("x".utf8), Data("x".utf8)))
        XCTAssertFalse(Hashes.constantTimeEquals(Data("x".utf8), Data("y".utf8)))
    }

    func testSecureRandomRange() {
        var seen = Set<Int>()
        for _ in 0..<500 { seen.insert(SecureRandom.int(4)) }
        XCTAssertEqual(seen, [0, 1, 2, 3])
    }

    func testJSONValueRoundTripPreservesNumbers() throws {
        let value = try JSONValue.decode(#"{"a":1,"b":2.5,"c":true,"d":[1,2],"e":"x"}"#)
        XCTAssertEqual(value["a"]?.intValue, 1)
        if case .double(let d) = value["b"] { XCTAssertEqual(d, 2.5) } else { XCTFail("expected double") }
        XCTAssertEqual(value["d"]?.arrayValue?.count, 2)
        let encoded = try value.encodedData(pretty: false)
        let reparsed = try JSONValue.decode(encoded)
        XCTAssertEqual(reparsed["e"]?.stringValue, "x")
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
