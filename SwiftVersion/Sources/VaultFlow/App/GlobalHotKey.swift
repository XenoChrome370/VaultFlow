// GlobalHotKey.swift
// VaultFlow · System-wide hotkeys via Carbon's RegisterEventHotKey
//
// Two global shortcuts are supported: the Spotlight-style quick search and a
// show/hide toggle for the main window. Both are configurable in Settings and
// persisted independently.

import AppKit
import Carbon.HIToolbox

/// A modifier set plus key code, persisted as `"⌃⌥⌘ Space"`-style text.
struct HotKeyDefinition: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var displayString: String

    static let defaultQuickSearch = HotKeyDefinition(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        displayString: "⌃⌥⌘L"
    )

    static let defaultToggleWindow = HotKeyDefinition(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        displayString: "⌃⌥⌘V"
    )

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    static func display(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += keyName(for: keyCode)
        return text
    }

    static func keyName(for keyCode: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
            kVK_ANSI_9: "9", kVK_ANSI_0: "0",
            kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_KeypadPlus: "+",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12"
        ]
        return map[Int(keyCode)] ?? "Key\(keyCode)"
    }
}

// MARK: - Actions

enum GlobalHotKeyAction: String, CaseIterable, Identifiable {
    case quickSearch
    case toggleWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickSearch: return "Quick Search"
        case .toggleWindow: return "Show / Hide VaultFlow"
        }
    }

    var subtitle: String {
        switch self {
        case .quickSearch: return "Opens the search palette from any app. Copies a password without leaving what you're doing."
        case .toggleWindow: return "Brings the main window forward, or hides it when VaultFlow is already in front."
        }
    }

    var defaultDefinition: HotKeyDefinition {
        switch self {
        case .quickSearch: return .defaultQuickSearch
        case .toggleWindow: return .defaultToggleWindow
        }
    }

    var storageKey: String { "vf.hotKey.\(rawValue)" }

    /// Quick search used to live under this key; keep users' existing choice.
    var legacyStorageKey: String? {
        self == .quickSearch ? "vf.quickSearchHotKey" : nil
    }

    var hotKeyID: UInt32 {
        UInt32((Self.allCases.firstIndex(of: self) ?? 0) + 1)
    }

    static func action(forID id: UInt32) -> GlobalHotKeyAction? {
        allCases.first { $0.hotKeyID == id }
    }
}

// MARK: - Manager

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    static let shared = GlobalHotKeyManager()

    @Published private(set) var definitions: [GlobalHotKeyAction: HotKeyDefinition]
    @Published private(set) var registeredActions: Set<GlobalHotKeyAction> = []

    /// Invoked on the main actor when a hotkey fires.
    var handlers: [GlobalHotKeyAction: (() -> Void)] = [:]

    private var hotKeyRefs: [GlobalHotKeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x56464C57 // 'VFLW'

    private init() {
        var loaded: [GlobalHotKeyAction: HotKeyDefinition] = [:]
        for action in GlobalHotKeyAction.allCases {
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: action.storageKey),
               let decoded = try? JSONDecoder().decode(HotKeyDefinition.self, from: data) {
                loaded[action] = decoded
            } else if let legacyKey = action.legacyStorageKey,
                       let data = defaults.data(forKey: legacyKey),
                       let decoded = try? JSONDecoder().decode(HotKeyDefinition.self, from: data) {
                loaded[action] = decoded
            } else {
                loaded[action] = action.defaultDefinition
            }
        }
        definitions = loaded
    }

    func definition(for action: GlobalHotKeyAction) -> HotKeyDefinition {
        definitions[action] ?? action.defaultDefinition
    }

    func isRegistered(_ action: GlobalHotKeyAction) -> Bool {
        registeredActions.contains(action)
    }

    // MARK: Lifecycle

    func install() {
        guard eventHandler == nil else {
            refreshRegistrations()
            return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if hotKeyID.signature == GlobalHotKeyManager.signature {
                let id = hotKeyID.id
                Task { @MainActor in manager.dispatch(id: id) }
            }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)

        refreshRegistrations()
    }

    func uninstall() {
        for (_, ref) in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        registeredActions = []
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func dispatch(id: UInt32) {
        guard let action = GlobalHotKeyAction.action(forID: id) else { return }
        handlers[action]?()
    }

    // MARK: Registration

    private func refreshRegistrations() {
        for action in GlobalHotKeyAction.allCases {
            register(action)
        }
    }

    private func register(_ action: GlobalHotKeyAction) {
        if let existing = hotKeyRefs[action] {
            UnregisterEventHotKey(existing)
            hotKeyRefs[action] = nil
        }
        registeredActions.remove(action)

        let definition = definition(for: action)
        let hotKeyID = EventHotKeyID(signature: GlobalHotKeyManager.signature, id: action.hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(definition.keyCode, definition.carbonModifiers,
                                         hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRefs[action] = ref
            registeredActions.insert(action)
        }
    }

    // MARK: Editing

    func setDefinition(_ new: HotKeyDefinition, for action: GlobalHotKeyAction) {
        var updated = new
        if updated.displayString.isEmpty {
            updated.displayString = HotKeyDefinition.display(keyCode: new.keyCode,
                                                             modifiers: new.modifierFlags)
        }
        definitions[action] = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: action.storageKey)
        }
        if eventHandler != nil {
            register(action)
            // Editing one hotkey can free or consume another's combination.
            for other in GlobalHotKeyAction.allCases where other != action {
                if !isRegistered(other) { register(other) }
            }
        }
    }

    func resetToDefault(_ action: GlobalHotKeyAction) {
        setDefinition(action.defaultDefinition, for: action)
    }
}
