// CSV.swift
// VaultFlow · RFC 4180 CSV reading and writing with header mapping

import Foundation

public enum CSVError: LocalizedError {
    case empty
    case missingColumns([String])

    public var errorDescription: String? {
        switch self {
        case .empty: return "The CSV file is empty."
        case .missingColumns(let columns): return "Missing required column(s): \(columns.joined(separator: ", "))."
        }
    }
}

public enum CSV {
    /// Parses CSV text into rows of fields, honouring quoted fields with
    /// embedded commas, quotes and newlines.
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        // Swift folds "\r\n" into a single Character (grapheme cluster), which
        // would hide line breaks — so scan unicode scalars instead.
        let scalars = Array(text.unicodeScalars)
        var index = 0
        var pending: Unicode.Scalar?
        func nextScalar() -> Unicode.Scalar? {
            guard index < scalars.count else { return nil }
            defer { index += 1 }
            return scalars[index]
        }

        func appendField() {
            row.append(field)
            field = ""
        }
        func appendRow() {
            appendField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let raw = pending ?? nextScalar() {
            pending = nil
            let character = Character(raw)
            if inQuotes {
                if character == "\"" {
                    if let next = nextScalar() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case ",":
                appendField()
            case "\n":
                appendRow()
            case "\r":
                // Swallow the "\n" of a CRLF pair; a lone CR still ends the row.
                if let next = nextScalar(), next != "\n" { pending = next }
                appendRow()
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { appendRow() }
        return rows
    }

    public static func escape(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    public static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// Normalises a header for matching (`Created Date` → `createddate`).
    public static func normalize(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// One row of an imported file before it becomes an Entry.
public struct ImportedRecord: Sendable, Equatable {
    public var service: String
    public var username: String
    public var password: String
    public var notes: String
    public var url: String
    public var folder: String
    public var tags: [String]
    public var totpSecret: String

    public init(service: String = "", username: String = "", password: String = "",
                notes: String = "", url: String = "", folder: String = VaultFolder.personal,
                tags: [String] = [], totpSecret: String = "") {
        self.service = service
        self.username = username
        self.password = password
        self.notes = notes
        self.url = url
        self.folder = folder
        self.tags = tags
        self.totpSecret = totpSecret
    }

    public var isValid: Bool {
        !service.trimmingCharacters(in: .whitespaces).isEmpty
            || !username.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum PasswordImporter {

    public static let supportedColumns = [
        "name/service/title", "username/login/email", "password",
        "url/website", "notes", "folder", "tags", "otp"
    ]

    /// Parses a CSV with flexible headers (Chrome, Safari, 1Password, Bitwarden,
    /// KeePass exports all work).
    public static func parseCSV(_ text: String) throws -> [ImportedRecord] {
        let rows = CSV.parse(text)
        guard let header = rows.first, rows.count > 1 else { throw CSVError.empty }
        let normalized = header.map(CSV.normalize)

        func column(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let index = normalized.firstIndex(of: candidate) { return index }
            }
            return nil
        }
        let serviceColumn = column(["name", "service", "title", "loginuri", "entryname", "account"])
        let usernameColumn = column(["username", "login", "email", "user", "loginusername", "userid"])
        let passwordColumn = column(["password", "pass", "secret"])
        let urlColumn = column(["url", "website", "uri", "loginurl", "webaddress"])
        let notesColumn = column(["notes", "note", "comments", "comment", "extra"])
        let folderColumn = column(["folder", "group", "category", "grouping"])
        let tagsColumn = column(["tags", "labels"])
        let otpColumn = column(["otp", "totp", "otpauth", "otpsecret"])

        guard passwordColumn != nil else {
            throw CSVError.missingColumns(["password"])
        }

        var records: [ImportedRecord] = []
        for row in rows.dropFirst() {
            func value(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index]
            }
            var service = value(serviceColumn)
            let url = value(urlColumn)
            if service.isEmpty, let host = PasswordImporter.host(of: url) {
                service = host
            }
            if service.isEmpty { service = value(usernameColumn) }
            let folder = value(folderColumn).trimmingCharacters(in: .whitespaces)
            let record = ImportedRecord(
                service: service,
                username: value(usernameColumn),
                password: value(passwordColumn),
                notes: value(notesColumn),
                url: url,
                folder: folder.isEmpty ? VaultFolder.personal : folder,
                tags: PasswordImporter.splitTags(value(tagsColumn)),
                totpSecret: value(otpColumn)
            )
            if record.isValid { records.append(record) }
        }
        return records
    }

    /// Extracts the display host from a URL, tolerating values without a scheme
    /// or with surrounding whitespace (as found in 1Password/Bitwarden CSVs).
    public static func host(of rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URL(string: candidate)?.host, host.contains(".") else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// Splits a tag list written with any of ";", "," or "|".
    public static func splitTags(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == ";" || $0 == "," || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses a generic JSON array/object export.
    public static func parseJSON(_ data: Data) throws -> [ImportedRecord] {
        let root = try JSONValue.decode(data)
        var array: [JSONValue] = []
        if let items = root.arrayValue {
            array = items
        } else if let object = root.objectValue {
            if let items = object["items"]?.arrayValue ?? object["entries"]?.arrayValue
                ?? object["logins"]?.arrayValue {
                array = items
            } else if let serviceObject = root.objectValue,
                      serviceObject.values.contains(where: { $0.objectValue?["accounts"]?.arrayValue != nil }) {
                // Plaintext vault export.
                for (service, value) in serviceObject {
                    for account in value.objectValue?["accounts"]?.arrayValue ?? [] {
                        guard var object = account.objectValue else { continue }
                        object["service"] = .string(service)
                        array.append(.object(object))
                    }
                }
            } else {
                array = [root]
            }
        }

        return array.compactMap { value in
            guard let object = value.objectValue else { return nil }
            var notes = object["notes"]?.stringValue ?? object["note"]?.stringValue ?? ""
            if let extra = object["fields"]?.arrayValue {
                let extraText = extra.compactMap { field -> String? in
                    guard let f = field.objectValue,
                          let label = f["label"]?.stringValue ?? f["name"]?.stringValue,
                          let val = f["value"]?.stringValue else { return nil }
                    return "\(label): \(val)"
                }.joined(separator: "\n")
                if !extraText.isEmpty { notes = notes.isEmpty ? extraText : notes + "\n" + extraText }
            }
            let record = ImportedRecord(
                service: object["service"]?.stringValue ?? object["name"]?.stringValue
                    ?? object["title"]?.stringValue ?? "",
                username: object["username"]?.stringValue ?? object["login"]?.stringValue
                    ?? object["user"]?.stringValue ?? object["email"]?.stringValue ?? "",
                password: object["password"]?.stringValue ?? object["pass"]?.stringValue ?? "",
                notes: notes,
                url: object["url"]?.stringValue ?? object["website"]?.stringValue ?? "",
                folder: object["folder"]?.stringValue ?? VaultFolder.personal,
                tags: object["tags"]?.arrayValue?.compactMap(\.stringValue)
                    ?? splitTags(object["tags"]?.stringValue ?? ""),
                totpSecret: object["otp"]?.stringValue ?? object["totp"]?.stringValue
                    ?? object["totpSecret"]?.stringValue ?? ""
            )
            return record.isValid ? record : nil
        }
    }

    /// Parses Apple Passwords / Chrome style "keychain" JSON if present.
    public static func recordsToDocument(_ records: [ImportedRecord], folders: inout Set<String>) -> VaultDocument {
        var services: [String: [Entry]] = [:]
        for record in records {
            let service = record.service.trimmingCharacters(in: .whitespaces)
            let folder = record.folder.isEmpty ? VaultFolder.personal : record.folder
            folders.insert(folder)
            let entry = Entry(
                service: service,
                username: record.username,
                password: record.password,
                notes: record.notes,
                url: record.url,
                folder: folder,
                tags: record.tags,
                totpSecret: record.totpSecret
            )
            services[service, default: []].append(entry)
        }
        return VaultDocument(services: services)
    }
}

public enum VaultExporter {

    /// Plaintext JSON export (optionally including VaultFlow extras).
    public static func json(_ document: VaultDocument, services: [String]? = nil) throws -> Data {
        var copy = document
        if let services {
            copy.services = copy.services.filter { services.contains($0.key) }
        }
        return try VaultSerializer.encode(copy)
    }

    /// CSV export with every column VaultFlow understands.
    public static func csv(_ entries: [Entry], includeNotes: Bool = true) -> String {
        var lines = [CSV.row(["name", "username", "password", "url", "notes", "folder", "tags", "otp", "favorite"])]
        for entry in entries.sorted(by: { $0.service.localizedCaseInsensitiveCompare($1.service) == .orderedAscending }) {
            lines.append(CSV.row([
                entry.service,
                entry.username,
                entry.password,
                entry.url,
                includeNotes ? entry.notes : "",
                entry.folder,
                entry.tags.joined(separator: ";"),
                entry.totpSecret,
                entry.favorite ? "true" : "false"
            ]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Human-readable table of plaintext credentials (the Python "Export All"
    /// behaviour), intended for printing or pasting into a secure note.
    public static func plaintextReport(_ document: VaultDocument) -> String {
        var lines: [String] = []
        lines.append("VaultFlow Export — \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
        lines.append(String(repeating: "=", count: 60))
        for service in document.services.keys.sorted() {
            lines.append("")
            lines.append("[\(service)]")
            for entry in document.services[service] ?? [] {
                lines.append("  Username: \(entry.username)")
                lines.append("  Password: \(entry.password)")
                if !entry.url.isEmpty { lines.append("  URL:      \(entry.url)") }
                if !entry.notes.isEmpty { lines.append("  Notes:    \(entry.notes)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}
