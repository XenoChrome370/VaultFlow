// Shortcuts.swift
// VaultFlow · User-configurable in-app keyboard shortcuts
//
// Every menu action that has a key equivalent is described by `ShortcutAction`.
// The current bindings live in `ShortcutStore` and are persisted to
// UserDefaults, so the main menu (and the Settings recorder) always agree.

import AppKit
import Combine

// MARK: - Key combination

/// A key equivalent plus modifiers, stored in a form AppKit can consume.
struct KeyCombo: Codable, Hashable {
    /// Lowercased `charactersIgnoringModifiers`, e.g. "n", "[", "\u{F700}".
    var key: String
    /// Raw `NSEvent.ModifierFlags` restricted to the device-independent mask.
    var modifiersRaw: UInt

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        self.modifiersRaw = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    static let none = KeyCombo(key: "", modifiers: [])

    var isEmpty: Bool { key.isEmpty }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRaw)
    }

    /// Text shown in menus and recorders, e.g. "⇧⌘K".
    var displayString: String {
        guard !key.isEmpty else { return "None" }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += Self.label(for: key)
        return text
    }

    private static func label(for key: String) -> String {
        switch key {
        case "\u{1b}": return "⎋"
        case "\r", "\u{3}": return "↩"
        case "\u{7f}": return "⌫"
        case "\u{9}": return "⇥"
        case " ": return "Space"
        case "\u{F700}": return "↑"
        case "\u{F701}": return "↓"
        case "\u{F702}": return "←"
        case "\u{F703}": return "→"
        case "\u{F704}": return "Home"
        case "\u{F705}": return "End"
        case "\u{F706}": return "PgUp"
        case "\u{F707}": return "PgDn"
        default: return key.uppercased()
        }
    }
}

// MARK: - Actions

enum ShortcutCategory: String, CaseIterable, Identifiable {
    case file = "File"
    case navigation = "Navigation"
    case vault = "Vault"
    case view = "View"

    var id: String { rawValue }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case newEntry
    case importData
    case exportData
    case focusSearch
    case quickSearch
    case showAll
    case showFavorites
    case showWatchtower
    case showGenerator
    case showClipboardHistory
    case copyPassword
    case copyUsername
    case copyTOTP
    case toggleFavorite
    case duplicate
    case previousItem
    case nextItem
    case toggleSidebar
    case zoomIn
    case zoomOut
    case actualSize
    case lockVault
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newEntry: return "New Password"
        case .importData: return "Import…"
        case .exportData: return "Export…"
        case .focusSearch: return "Search Vault"
        case .quickSearch: return "Quick Search"
        case .showAll: return "All Items"
        case .showFavorites: return "Favorites"
        case .showWatchtower: return "Watchtower"
        case .showGenerator: return "Generator"
        case .showClipboardHistory: return "Clipboard History"
        case .copyPassword: return "Copy Password of Selected Item"
        case .copyUsername: return "Copy Username of Selected Item"
        case .copyTOTP: return "Copy One-Time Code of Selected Item"
        case .toggleFavorite: return "Toggle Favorite of Selected Item"
        case .duplicate: return "Duplicate Selected Item"
        case .previousItem: return "Previous Item"
        case .nextItem: return "Next Item"
        case .toggleSidebar: return "Toggle Sidebar"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .actualSize: return "Actual Size"
        case .lockVault: return "Lock Vault"
        case .help: return "VaultFlow Help"
        }
    }

    /// Short title used by the compact Settings recorder list.
    var shortTitle: String {
        switch self {
        case .newEntry: return "New password"
        case .importData: return "Import"
        case .exportData: return "Export"
        case .focusSearch: return "Search vault"
        case .quickSearch: return "Quick search"
        case .showAll: return "All items"
        case .showFavorites: return "Favorites"
        case .showWatchtower: return "Watchtower"
        case .showGenerator: return "Generator"
        case .showClipboardHistory: return "Clipboard history"
        case .copyPassword: return "Copy password"
        case .copyUsername: return "Copy username"
        case .copyTOTP: return "Copy one-time code"
        case .toggleFavorite: return "Toggle favorite"
        case .duplicate: return "Duplicate item"
        case .previousItem: return "Previous item"
        case .nextItem: return "Next item"
        case .toggleSidebar: return "Toggle sidebar"
        case .zoomIn: return "Zoom in"
        case .zoomOut: return "Zoom out"
        case .actualSize: return "Actual size"
        case .lockVault: return "Lock vault"
        case .help: return "Help"
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .newEntry, .importData, .exportData:
            return .file
        case .focusSearch, .quickSearch, .showAll, .showFavorites,
             .showWatchtower, .showGenerator, .showClipboardHistory,
             .previousItem, .nextItem:
            return .navigation
        case .copyPassword, .copyUsername, .copyTOTP, .toggleFavorite,
             .duplicate, .lockVault:
            return .vault
        case .toggleSidebar, .zoomIn, .zoomOut, .actualSize, .help:
            return .view
        }
    }

    /// Defaults mirror the app's shipping shortcuts (and the old Settings list).
    var defaultCombo: KeyCombo {
        switch self {
        case .newEntry: return KeyCombo(key: "n", modifiers: [.command])
        case .importData: return KeyCombo(key: "i", modifiers: [.command, .shift])
        case .exportData: return KeyCombo(key: "e", modifiers: [.command, .shift])
        case .focusSearch: return KeyCombo(key: "f", modifiers: [.command])
        case .quickSearch: return KeyCombo(key: "k", modifiers: [.command, .shift])
        case .showAll: return KeyCombo(key: "1", modifiers: [.command])
        case .showFavorites: return KeyCombo(key: "5", modifiers: [.command])
        case .showWatchtower: return KeyCombo(key: "2", modifiers: [.command])
        case .showGenerator: return KeyCombo(key: "3", modifiers: [.command])
        case .showClipboardHistory: return KeyCombo(key: "4", modifiers: [.command])
        case .copyPassword: return KeyCombo(key: "c", modifiers: [.command, .shift])
        case .copyUsername: return KeyCombo(key: "b", modifiers: [.command, .shift])
        case .copyTOTP: return KeyCombo(key: "t", modifiers: [.command, .shift])
        case .toggleFavorite: return KeyCombo(key: "f", modifiers: [.command, .shift])
        case .duplicate: return KeyCombo(key: "d", modifiers: [.command, .shift])
        case .previousItem: return KeyCombo(key: "[", modifiers: [.command, .option])
        case .nextItem: return KeyCombo(key: "]", modifiers: [.command, .option])
        case .toggleSidebar: return KeyCombo(key: "s", modifiers: [.command, .control])
        case .zoomIn: return KeyCombo(key: "+", modifiers: [.command])
        case .zoomOut: return KeyCombo(key: "-", modifiers: [.command])
        case .actualSize: return KeyCombo(key: "0", modifiers: [.command])
        case .lockVault: return KeyCombo(key: "l", modifiers: [.command, .control])
        case .help: return KeyCombo(key: "?", modifiers: [.command])
        }
    }
}

// MARK: - Store

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var bindings: [ShortcutAction: KeyCombo]

    /// Called whenever a binding changes so the AppKit main menu can be rebuilt.
    var onChange: (() -> Void)?

    private let storageKey = "vf.shortcuts.v2"

    private struct Payload: Codable {
        var combos: [String: KeyCombo]
    }

    private init() {
        var defaults: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            defaults[action] = action.defaultCombo
        }
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            for (raw, combo) in payload.combos {
                if let action = ShortcutAction(rawValue: raw) {
                    defaults[action] = combo
                }
            }
        }
        bindings = defaults
    }

    func binding(for action: ShortcutAction) -> KeyCombo {
        bindings[action] ?? action.defaultCombo
    }

    /// Binding actually used by the menu: the first action claiming a combo wins,
    /// so two actions can never silently share one shortcut.
    func effectiveBinding(for action: ShortcutAction) -> KeyCombo {
        let combo = binding(for: action)
        guard !combo.isEmpty else { return .none }
        let owner = ShortcutAction.allCases.first { candidate in
            let candidateCombo = binding(for: candidate)
            return !candidateCombo.isEmpty && candidateCombo == combo
        }
        return owner == action ? combo : .none
    }

    /// Actions whose shortcut is also claimed by an earlier action.
    var conflictingActions: Set<ShortcutAction> {
        var seen: Set<KeyCombo> = []
        var conflicts: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            let combo = binding(for: action)
            guard !combo.isEmpty else { continue }
            if !seen.insert(combo).inserted {
                conflicts.insert(action)
            }
        }
        return conflicts
    }

    func setBinding(_ combo: KeyCombo, for action: ShortcutAction) {
        bindings[action] = combo
        persist()
        onChange?()
    }

    func reset(_ action: ShortcutAction) {
        bindings[action] = action.defaultCombo
        persist()
        onChange?()
    }

    func resetAll() {
        for action in ShortcutAction.allCases {
            bindings[action] = action.defaultCombo
        }
        persist()
        onChange?()
    }

    private func persist() {
        var combos: [String: KeyCombo] = [:]
        for (action, combo) in bindings {
            combos[action.rawValue] = combo
        }
        if let data = try? JSONEncoder().encode(Payload(combos: combos)) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
