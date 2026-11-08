// Entry.swift
// VaultFlow · Core vault data model
//
// On-disk layout (shared with the Python and Java versions):
//
//   {
//     "gmail.com": {
//       "accounts": [
//         { "id": "…", "username": "…", "password": "…", "notes": "…",
//           "created_date": "2026-11-08 10:51:46",        // Python
//           "createdDate":  "2026-11-08 10:51:46",        // Java
//           "length": 20,
//           // VaultFlow-for-macOS extensions:
//           "vf": { "updatedAt": 1712345678, "folder": "Work", "tags": ["work"],
//                   "favorite": true, "url": "https://…", "totpSecret": "…",
//                   "customFields": [ {"id": "…", "label": "PIN", "value": "…", "sensitive": true} ] } }
//       ]
//     }
//   }

import Foundation

public struct CustomField: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String
    public var sensitive: Bool

    public init(id: UUID = UUID(), label: String, value: String, sensitive: Bool = false) {
        self.id = id
        self.label = label
        self.value = value
        self.sensitive = sensitive
    }
}

public struct Entry: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var service: String
    public var username: String
    public var password: String
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date
    public var url: String
    public var folder: String
    public var tags: [String]
    public var favorite: Bool
    public var totpSecret: String
    public var customFields: [CustomField]

    /// Unknown fields preserved from foreign vault files and from future
    /// versions of this app, so a round-trip never loses data.
    public var unknownAccountFields: [String: JSONValue] = [:]
    public var hasTOTP: Bool { !totpSecret.isEmpty }

    public init(
        id: UUID = UUID(),
        service: String,
        username: String,
        password: String,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        url: String = "",
        folder: String = VaultFolder.personal,
        tags: [String] = [],
        favorite: Bool = false,
        totpSecret: String = "",
        customFields: [CustomField] = []
    ) {
        self.id = id
        self.service = service
        self.username = username
        self.password = password
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
        self.folder = folder
        self.tags = tags
        self.favorite = favorite
        self.totpSecret = totpSecret
        self.customFields = customFields
    }

    public var displayHost: String {
        if !url.isEmpty, let host = URL(string: url.hasPrefix("http") ? url : "https://\(url)")?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return service
    }

    /// Lowercased text used for search.
    public var searchIndex: String {
        let custom = customFields.map { "\($0.label) \($0.value)" }.joined(separator: " ")
        return ([service, username, notes, url, folder, tags.joined(separator: " "), custom]
            .joined(separator: "\n")).lowercased()
    }

    public var ageInDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: updatedAt, to: Date()).day ?? 0)
    }
}

public enum VaultFolder {
    public static let all = "All Items"
    public static let favorites = "Favorites"
    public static let personal = "Personal"
    public static let work = "Work"
    public static let finance = "Finance"
    public static let social = "Social"
    public static let development = "Development"
    public static let defaultFolders = [personal, work, finance, social, development]
}

public struct VaultDocument: Sendable {
    public var services: [String: [Entry]]
    public var rootUnknownKeys: [String: JSONValue]
    public var serviceUnknownKeys: [String: [String: JSONValue]]
    public var modifiedAt: Date

    public init(
        services: [String: [Entry]] = [:],
        rootUnknownKeys: [String: JSONValue] = [:],
        serviceUnknownKeys: [String: [String: JSONValue]] = [:],
        modifiedAt: Date = Date()
    ) {
        self.services = services
        self.rootUnknownKeys = rootUnknownKeys
        self.serviceUnknownKeys = serviceUnknownKeys
        self.modifiedAt = modifiedAt
    }

    public var allEntries: [Entry] {
        services.values.flatMap { $0 }
    }

    public var isEmpty: Bool {
        allEntries.isEmpty
    }

    public var count: Int { allEntries.count }
}
