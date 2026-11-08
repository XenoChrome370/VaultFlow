// VaultFormatTests.swift
// VaultFlow · Envelope, Fernet/GCM cross-compatibility with the Python and Java versions

import XCTest
@testable import VaultFlowCore

final class VaultFormatTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        guard let url = fixtureURL(name) else {
            throw XCTSkip("missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }

    /// `Bundle.module` only exists when SwiftPM generates it; Xcode copies the
    /// fixtures loose into the test bundle instead, hence the two lookups.
    private func fixtureURL(_ name: String) -> URL? {
        #if SWIFT_PACKAGE
        let candidates = [
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            Bundle.module.url(forResource: name, withExtension: "json"),
        ]
        #else
        let candidates = [
            Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            Bundle(for: Self.self).url(forResource: name, withExtension: "json"),
        ]
        #endif
        return candidates.compactMap { $0 }.first
    }

    func testOpensPythonFernetVault() throws {
        let data = try fixture("python_fixture")
        let unlocked = try VaultMigration.open(data, password: "python master", rawFernetKey: nil)
        XCTAssertEqual(unlocked.kind, .pythonEnvelope)
        XCTAssertEqual(unlocked.document.count, 2)
        let example = try XCTUnwrap(unlocked.document.services["Example"]?.first)
        XCTAssertEqual(example.username, "alice@example.com")
        XCTAssertEqual(example.password, "S3cret!pass")
        XCTAssertEqual(example.notes, "Carrier: a:b \"quoted\"")
        XCTAssertEqual(example.folder, VaultFolder.personal)
    }

    func testRejectsWrongPasswordForPythonVault() throws {
        let data = try fixture("python_fixture")
        XCTAssertThrowsError(try VaultMigration.open(data, password: "not it", rawFernetKey: nil))
    }

    func testOpensJavaGCMVault() throws {
        let data = try fixture("java_fixture")
        let unlocked = try VaultMigration.open(data, password: "java master", rawFernetKey: nil)
        XCTAssertEqual(unlocked.document.count, 2)
        let github = try XCTUnwrap(unlocked.document.services["GitHub"]?.first)
        XCTAssertEqual(github.username, "octocat")
        XCTAssertEqual(github.password, "Tr0ub4dor&3")
        // Java writes camelCase `createdDate`; we parse it into a real date.
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!,
                                                                          from: github.createdAt)
        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 14)
    }

    func testDetectsVaultKinds() throws {
        XCTAssertEqual(VaultMigration.detect(try fixture("python_fixture")), .pythonEnvelope)
        XCTAssertEqual(VaultMigration.detect(try fixture("java_fixture")), .javaEnvelope)
        XCTAssertEqual(VaultMigration.detect(Data("{}".utf8)), nil)
        XCTAssertEqual(VaultMigration.detect(Data(#"{"Mail":{"accounts":[{"username":"a"}]}}"#.utf8)), .plaintext)
    }

    func testEnvelopeRoundTrip() throws {
        let salt = SecureRandom.bytes(EncryptionParameters().saltLength)
        let key = try VaultFormat.deriveKey(password: "master", salt: salt, parameters: .init())
        let payload = try VaultFormat.encrypt(plaintext: Data("hello".utf8), key: key, cipher: .aes256gcm)
        let envelope = try VaultFormat.makeEnvelope(salt: salt, payload: payload, cipher: .aes256gcm,
                                                    parameters: .init()).encodedData(pretty: true)
        let parsed = try VaultFormat.parseEnvelope(envelope)
        XCTAssertEqual(parsed.cipher, .aes256gcm)
        XCTAssertEqual(parsed.salt, salt)
        XCTAssertEqual(parsed.parameters.iterations, VaultFormat.defaultIterations)
        let recoveredKey = try VaultFormat.deriveKey(password: "master", salt: parsed.salt,
                                                     parameters: parsed.parameters)
        XCTAssertEqual(try VaultFormat.decrypt(payload: parsed.payload, key: recoveredKey,
                                               cipher: parsed.cipher),
                       Data("hello".utf8))
    }

    func testSerializerIsLosslessForForeignFields() throws {
        // Mirrors the Java `parseSimpleJson` corruption bug: values with colons,
        // quotes and braces must survive a full round-trip.
        let raw = #"""
        {"Zeta":{"accounts":[{"id":"1699999999999","username":"a:b \"c\"","password":"}{:\\","notes":"line1\nline2","createdDate":"2024-02-03 04:05:06","length":5,"extra":true}],"custom_service_key":3}}
        """#
        let document = try VaultSerializer.decode(Data(raw.utf8))
        let entry = try XCTUnwrap(document.services["Zeta"]?.first)
        XCTAssertEqual(entry.username, "a:b \"c\"")
        XCTAssertEqual(entry.password, "}{:\\")
        XCTAssertEqual(entry.notes, "line1\nline2")
        XCTAssertEqual(entry.unknownAccountFields["id"]?.stringValue, "1699999999999")

        let encoded = try VaultSerializer.encode(document)
        let reencoded = try JSONValue.decode(encoded)
        let account = try XCTUnwrap(reencoded["Zeta"]?["accounts"]?.arrayValue?.first)
        XCTAssertEqual(account["username"]?.stringValue, "a:b \"c\"")
        XCTAssertEqual(account["id"]?.stringValue, "1699999999999")
        XCTAssertEqual(account["length"]?.intValue, entry.password.count)
        XCTAssertEqual(account["extra"]?.boolValue, true)
        XCTAssertEqual(reencoded["Zeta"]?["custom_service_key"]?.intValue, 3)
    }

    func testSerializerUpdatesLengthWhenPasswordChanges() throws {
        var document = VaultDocument()
        document.services["Site"] = [Entry(service: "Site", username: "u", password: "short")]
        let encoded = try VaultSerializer.encode(document)
        var account = try XCTUnwrap(JSONValue.decode(encoded)["Site"]?["accounts"]?.arrayValue?.first)
        XCTAssertEqual(account["length"]?.intValue, 5)
        account["password"] = .string("a longer password")
        let updated = try VaultSerializer.decode(Data(#"{"Site":{"accounts":[\#(account.encodedString(pretty: false))]}}"#.utf8))
        XCTAssertEqual(updated.services["Site"]?.first?.password, "a longer password")
    }

    func testPlaintextVaultDetection() throws {
        let data = Data(#"{"Mail":{"accounts":[{"username":"me","password":"p"}]}}"#.utf8)
        let unlocked = try VaultMigration.open(data, password: "", rawFernetKey: nil)
        XCTAssertEqual(unlocked.kind, .plaintext)
        XCTAssertEqual(unlocked.document.services["Mail"]?.first?.username, "me")
    }
}
