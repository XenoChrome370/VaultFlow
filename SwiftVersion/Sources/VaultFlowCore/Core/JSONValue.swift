// JSONValue.swift
// VaultFlow · Lossless, type-safe JSON value
//
// The vault is a JSON document shared between three implementations. Instead
// of ad-hoc parsing (the Java version's line-based parser corrupts any value
// containing ':' or quotes), we decode into this typed container and re-encode
// it faithfully, so fields written by newer/older versions survive a
// round-trip untouched.

import Foundation

public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        // NSNumber is handled before Bool/Int/Double: `as Bool` would otherwise
        // capture every number that JSONSerialization produces.
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                self = .bool(v.boolValue)
            } else if String(cString: v.objCType) == "d" {
                let d = v.doubleValue
                if d == d.rounded(), abs(d) < 9e15 { self = .int(Int(d)) } else { self = .double(d) }
            } else {
                self = .int(v.intValue)
            }
        case let v as String:
            self = .string(v)
        case let v as [Any]:
            self = .array(v.map { JSONValue(any: $0) })
        case let v as [String: Any]:
            self = .object(v.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    // MARK: Accessors

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        default: return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        get { objectValue?[key] }
        set {
            guard case .object(var dict) = self else { return }
            if let newValue { dict[key] = newValue } else { dict.removeValue(forKey: key) }
            self = .object(dict)
        }
    }

    /// Convenience for optional lookups with a default.
    public func string(_ key: String, default def: String = "") -> String {
        self[key]?.stringValue ?? def
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: Coding

    /// Finds the string value for `key`, searching nested objects/arrays as a
    /// fallback (used when importing foreign vault files).
    public func firstString(forKey key: String) -> String? {
        if let direct = self[key]?.stringValue { return direct }
        switch self {
        case .object(let o):
            for (_, v) in o {
                if let found = v.firstString(forKey: key) { return found }
            }
        case .array(let a):
            for v in a {
                if let found = v.firstString(forKey: key) { return found }
            }
        default:
            break
        }
        return nil
    }

    public static func object(_ pairs: [(String, JSONValue)]) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: pairs))
    }
}

extension JSONValue {
    public static func decode(_ data: Data) throws -> JSONValue {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSONValue(any: raw)
    }

    public static func decode(_ string: String) throws -> JSONValue {
        guard let data = string.data(using: .utf8) else { throw JSONError.notUTF8 }
        return try decode(data)
    }

    public func encodedData(pretty: Bool = true) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        let object = JSONValue.toFoundation(self)
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    public func encodedString(pretty: Bool = false) throws -> String {
        String(decoding: try encodedData(pretty: pretty), as: UTF8.self)
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

public enum JSONError: LocalizedError {
    case notUTF8
    case notAnObject

    public var errorDescription: String? {
        switch self {
        case .notUTF8: return "The vault file is not valid UTF-8."
        case .notAnObject: return "The vault document is not a JSON object."
        }
    }
}
