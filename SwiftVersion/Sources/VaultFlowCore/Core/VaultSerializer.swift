// VaultSerializer.swift
// VaultFlow · VaultDocument ⇄ JSON
//
// Reads and writes the *same* plaintext JSON as the Python and Java versions:
//
//   {
//     "gmail.com": {
//       "accounts": [
//         {"id": "...", "username": "...", "password": "...", "notes": "...",
//          "created_date": "2026-11-08 10:51:46", "length": 20},
//         ...
//       ]
//     }
//   }
//
// Compatibility rules:
//   • Both `created_date` (Python) and `createdDate` (Java) are written, so a
//     file can be opened by either implementation.
//   • Parsing accepts either, plus ISO-8601 and `Date` encoders, and falls back
//     to the current time when neither parses.
//   • Unknown fields on accounts, services and at the root are preserved.
//   • VaultFlow-specific data lives in an extra `vf` object per account, which
//     the other implementations simply ignore.

import Foundation

public enum VaultSerializer {

    // MARK: Date helpers

    private static let legacyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let legacyFormatterUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    public static func formatLegacyDate(_ date: Date) -> String {
        legacyFormatter.string(from: date)
    }

    public static func parseLegacyDate(_ string: String) -> Date? {
        if let date = legacyFormatter.date(from: string) { return date }
        if let date = legacyFormatterUTC.date(from: string) { return date }
        if let date = isoFormatter.date(from: string) { return date }
        // Some writers emit fractional seconds or a 'T' separator.
        let relaxed = ISO8601DateFormatter()
        relaxed.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = relaxed.date(from: string) { return date }
        return nil
    }

    // MARK: Decode

    public static func decode(_ plaintext: Data) throws -> VaultDocument {
        let root = try JSONValue.decode(plaintext)
        guard let rootObject = root.objectValue else { throw JSONError.notAnObject }
        return decode(rootObject)
    }

    public static func decode(_ rootObject: [String: JSONValue]) -> VaultDocument {
        var services: [String: [Entry]] = [:]
        var serviceUnknown: [String: [String: JSONValue]] = [:]
        var rootUnknown: [String: JSONValue] = rootObject

        for (service, value) in rootObject {
            guard let serviceObject = value.objectValue,
                  let accounts = serviceObject["accounts"]?.arrayValue
            else { continue }

            var entries: [Entry] = []
            for accountValue in accounts {
                guard let account = accountValue.objectValue else { continue }
                entries.append(decodeEntry(service: service, account: account))
            }
            services[service] = entries
            var remainder = serviceObject
            remainder.removeValue(forKey: "accounts")
            if !remainder.isEmpty { serviceUnknown[service] = remainder }
            rootUnknown.removeValue(forKey: service)
        }

        return VaultDocument(services: services,
                             rootUnknownKeys: rootUnknown,
                             serviceUnknownKeys: serviceUnknown)
    }

    private static func decodeEntry(service: String, account: [String: JSONValue]) -> Entry {
        // Keep the original textual id (Python uses timestamps, Java uses
        // millisecond counters). If it isn't a UUID we hash it to a stable
        // UUID for in-memory identity and write the *original* string back.
        let originalID = account["id"]?.stringValue ?? ""
        let id = UUID(uuidString: originalID) ?? UUID()

        let createdRaw = account["created_date"]?.stringValue
            ?? account["createdDate"]?.stringValue
            ?? ""
        let createdAt = parseLegacyDate(createdRaw) ?? Date()

        let vf = account["vf"]?.objectValue ?? [:]

        let updatedAt: Date = {
            switch vf["updatedAt"] {
            case .int(let seconds)? where seconds > 0:
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            case .double(let seconds)? where seconds > 0:
                return Date(timeIntervalSince1970: seconds)
            default:
                return createdAt
            }
        }()

        let tags = vf["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []

        var fields: [CustomField] = []
        if let rawFields = vf["customFields"]?.arrayValue {
            for raw in rawFields {
                guard let object = raw.objectValue else { continue }
                fields.append(CustomField(
                    id: UUID(uuidString: object["id"]?.stringValue ?? "") ?? UUID(),
                    label: object["label"]?.stringValue ?? "",
                    value: object["value"]?.stringValue ?? "",
                    sensitive: object["sensitive"]?.boolValue ?? false
                ))
            }
        }

        // Fields this build doesn't know about are carried through untouched.
        var unknown = account
        for known in ["username", "password", "notes", "created_date",
                      "createdDate", "length", "vf"] {
            unknown.removeValue(forKey: known)
        }
        if !originalID.isEmpty, UUID(uuidString: originalID) == nil {
            // Foreign id format: round-trip the exact original string.
            unknown["id"] = .string(originalID)
        }

        return Entry(
            id: id,
            service: service,
            username: account["username"]?.stringValue ?? "",
            password: account["password"]?.stringValue ?? "",
            notes: account["notes"]?.stringValue ?? "",
            createdAt: createdAt,
            updatedAt: updatedAt,
            url: vf["url"]?.stringValue ?? (account["url"]?.stringValue ?? ""),
            folder: vf["folder"]?.stringValue ?? VaultFolder.personal,
            tags: tags,
            favorite: vf["favorite"]?.boolValue ?? false,
            totpSecret: vf["totpSecret"]?.stringValue ?? "",
            customFields: fields
        ).withUnknown(unknown)
    }

    // MARK: Encode

    public static func encode(_ document: VaultDocument, pretty: Bool = true) throws -> Data {
        let root = encodeRoot(document)
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: toFoundation(root), options: options)
    }

    public static func encodeRoot(_ document: VaultDocument) -> JSONValue {
        var root = document.rootUnknownKeys

        // Services are written in sorted order for stable diffs (same as Python).
        for service in document.services.keys.sorted() {
            let entries = document.services[service] ?? []
            var serviceObject = document.serviceUnknownKeys[service] ?? [:]
            serviceObject["accounts"] = .array(entries.map { encodeEntry($0) })
            root[service] = .object(serviceObject)
        }
        return .object(root)
    }

    private static func encodeEntry(_ entry: Entry) -> JSONValue {
        var account = entry.unknownAccountFields

        // `id` is written as a string in every implementation. UUIDs that came
        // from Python/Java keep their original textual form via unknown-to-known
        // round-tripping; new entries use the UUID string.
        if account["id"]?.stringValue?.isEmpty ?? true {
            account["id"] = .string(entry.id.uuidString)
        }
        account["username"] = .string(entry.username)
        account["password"] = .string(entry.password)
        account["notes"] = .string(entry.notes)
        let stamp = formatLegacyDate(entry.createdAt)
        account["created_date"] = .string(stamp)
        account["createdDate"] = .string(stamp)
        account["length"] = .int(entry.password.count)

        var vf: [String: JSONValue] = [
            "updatedAt": .int(Int(entry.updatedAt.timeIntervalSince1970)),
            "folder": .string(entry.folder),
            "tags": .array(entry.tags.map { .string($0) }),
            "favorite": .bool(entry.favorite),
            "url": .string(entry.url),
            "totpSecret": .string(entry.totpSecret),
            "customFields": .array(entry.customFields.map { field in
                .object([
                    "id": .string(field.id.uuidString),
                    "label": .string(field.label),
                    "value": .string(field.value),
                    "sensitive": .bool(field.sensitive)
                ])
            })
        ]
        // Omit empty values so files stay readable when synced with other apps.
        if vf["totpSecret"]?.stringValue?.isEmpty == true { vf.removeValue(forKey: "totpSecret") }
        if vf["url"]?.stringValue?.isEmpty == true { vf.removeValue(forKey: "url") }
        if vf["tags"]?.arrayValue?.isEmpty == true { vf.removeValue(forKey: "tags") }
        if vf["customFields"]?.arrayValue?.isEmpty == true { vf.removeValue(forKey: "customFields") }
        if vf["favorite"]?.boolValue == false { vf.removeValue(forKey: "favorite") }
        account["vf"] = .object(vf)

        return .object(account)
    }

    private static func toFoundation(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { toFoundation($0) }
        case .object(let o): return o.mapValues { toFoundation($0) }
        }
    }
}

extension Entry {
    func withUnknown(_ fields: [String: JSONValue]) -> Entry {
        var copy = self
        copy.unknownAccountFields = fields
        return copy
    }
}
