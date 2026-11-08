// ImportExportTests.swift
// VaultFlow · CSV/JSON import and export round-trips

import XCTest
@testable import VaultFlowCore

final class ImportExportTests: XCTestCase {
    func testCSVParsesQuotedFieldsWithCommasAndNewlines() {
        // Five columns so the multi-line notes field is actually mapped.
        let text = "name,username,password,url,notes\n"
            + "\"Bank, Inc.\",alice,\"p,w\"\"x\",https://bank.example.com,\"first line\nsecond line\"\n"
            + "Mail,bob,\"line1\nline2\",https://mail.example.com,\"multi\nline notes\"\n"
        guard let records = try? PasswordImporter.parseCSV(text) else {
            return XCTFail("expected CSV to parse")
        }
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.service, "Bank, Inc.")
        XCTAssertEqual(records.first?.password, "p,w\"x")
        XCTAssertEqual(records.first?.folder, VaultFolder.personal)
        XCTAssertEqual(records.last?.service, "Mail")
        XCTAssertEqual(records.last?.password, "line1\nline2")
        XCTAssertEqual(records.last?.notes, "multi\nline notes")
        XCTAssertEqual(records.first?.notes, "first line\nsecond line")
    }

    func testCSVSupportsPasswordManagerHeaders() throws {
        let text = """
        url,login,password,otp
        https://github.com,octocat,s3cret,otpauth://totp/x?secret=JBSWY3DPEHPK3PXP
        """
        let records = try PasswordImporter.parseCSV(text)
        XCTAssertEqual(records.first?.service, "github.com")
        XCTAssertEqual(records.first?.username, "octocat")
        XCTAssertEqual(records.first?.url, "https://github.com")
        XCTAssertEqual(records.first?.totpSecret, "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP")
    }

    func testCSVRejectsGarbage() {
        XCTAssertThrowsError(try PasswordImporter.parseCSV(""))
        XCTAssertThrowsError(try PasswordImporter.parseCSV("foo,bar\n1,2"))
    }

    func testJSONImportOfLooseArray() throws {
        let json = #"""
        [{"name":"Site","username":"u","password":"p","notes":"n","folder":"Work","tags":"a;b"}]
        """#
        let records = try PasswordImporter.parseJSON(Data(json.utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.folder, "Work")
        XCTAssertEqual(records.first?.tags, ["a", "b"])
    }

    func testCSVExportRoundTripsThroughImport() throws {
        let entries = [
            Entry(service: "Zeta, Inc.", username: "a\"b", password: "p,w\nx", notes: "multi\nline", folder: "Work"),
            Entry(service: "Alpha", username: "u", password: "p")
        ]
        let csv = VaultExporter.csv(entries)
        let records = try PasswordImporter.parseCSV(csv)
        XCTAssertEqual(records.count, 2)
        // Export sorts by service name, so "Alpha" comes first.
        XCTAssertEqual(records.first?.service, "Alpha")
        let zeta = try XCTUnwrap(records.last)
        XCTAssertEqual(zeta.service, "Zeta, Inc.")
        XCTAssertEqual(zeta.username, "a\"b")
        XCTAssertEqual(zeta.password, "p,w\nx")
        XCTAssertEqual(zeta.notes, "multi\nline")
        XCTAssertEqual(zeta.folder, "Work")
    }

    func testJSONExportIncludesAllAccounts() throws {
        let document = VaultDocument(services: [
            "A": [Entry(service: "A", username: "1", password: "x")],
            "B": [Entry(service: "B", username: "2", password: "y")]
        ])
        let data = try VaultExporter.json(document)
        let decoded = try JSONValue.decode(data)
        XCTAssertEqual(decoded["A"]?["accounts"]?.arrayValue?.count, 1)
        XCTAssertEqual(decoded["B"]?["accounts"]?.arrayValue?.first?["username"]?.stringValue, "2")
    }

    func testRecordsToDocumentCreatesFolders() {
        var folders: Set<String> = []
        let records = [
            ImportedRecord(service: "S", username: "u", password: "p", notes: "", url: "", folder: "Custom",
                           tags: [], totpSecret: "")
        ]
        let document = PasswordImporter.recordsToDocument(records, folders: &folders)
        XCTAssertEqual(document.services["S"]?.count, 1)
        XCTAssertTrue(folders.contains("Custom"))
    }

    func testCSVFormatsAreSameForAllVersions() {
        // Both original apps store plaintext exports; the Swift app must be able
        // to read a file the others would have produced.
        let legacy = "name,username,password,url,notes,otp,favorite\nSite,u,p,,,\n"
        XCTAssertNoThrow(try PasswordImporter.parseCSV(legacy))
    }
}
