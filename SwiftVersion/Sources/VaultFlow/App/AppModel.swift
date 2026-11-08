// AppModel.swift
// VaultFlow · Observable application state (@MainActor)
//
// Owns the `VaultSession` actor, the current selection and every user
// preference. Views never touch the actor directly; they call methods here and
// read published properties.

import SwiftUI
import AppKit
import Observation
import VaultFlowCore

@MainActor
final class AppModel: ObservableObject {

    // MARK: Vault state

    enum LockState: Equatable {
        case needsVault
        case locked
        case unlocking
        case unlocked
        case error(String)
    }

    @Published private(set) var lockState: LockState = .locked
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var folders: [String] = VaultFolder.defaultFolders
    @Published private(set) var tagIndex: [String: Int] = [:]
    @Published private(set) var vaultURL: URL = VaultSession.defaultVaultURL()
    @Published private(set) var vaultExists = false
    @Published private(set) var saveState: SaveState = .saved
    @Published private(set) var lastUnlockError: String?

    enum SaveState: Equatable {
        case saved
        case saving
        case failed(String)
    }

    // MARK: Selection & navigation

    enum Destination: Hashable {
        case all
        case favorites
        case folder(String)
        case tag(String)
        case watchtower
        case generator
        case history
        case settings
    }

    @Published var destination: Destination = .all
    @Published var selectedEntryID: UUID?
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .name
    @Published var activeSheet: Sheet?
    @Published var sidebarVisible: Bool =
        (UserDefaults.standard.object(forKey: "vf.showSidebar") as? Bool) ?? true

    func toggleSidebar() {
        sidebarVisible.toggle()
        UserDefaults.standard.set(sidebarVisible, forKey: "vf.showSidebar")
    }

    /// Moves the selection up or down within the currently filtered list.
    func selectAdjacent(offset: Int) {
        let list = filteredEntries
        guard !list.isEmpty else { return }
        let index: Int
        if let selectedEntryID, let current = list.firstIndex(where: { $0.id == selectedEntryID }) {
            index = min(max(0, current + offset), list.count - 1)
        } else {
            index = offset >= 0 ? 0 : list.count - 1
        }
        selectedEntryID = list[index].id
        registerActivity()
    }

    /// Bumped when Cmd-F is pressed so the search field can take focus.
    @Published var searchFocusRequests = 0

    func focusSearch() {
        destination = .all
        searchFocusRequests += 1
    }

    func openQuickSearch() {
        guard lockState == .unlocked else {
            activateWindow()
            return
        }
        activeSheet = .quickSearch
    }

    func openQuickSearchFromHotKey() {
        if lockState == .unlocked {
            activeSheet = .quickSearch
            activateWindow()
        } else {
            activateWindow()
        }
    }

    func activateWindow() {
        WindowRegistry.presentMainWindow()
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name"
        case recent = "Recently Updated"
        case created = "Recently Added"
        case strength = "Weakest First"
        var id: String { rawValue }
    }

    enum Sheet: Identifiable {
        case addEntry(service: String)
        case editEntry(Entry)
        case importVault
        case exportVault
        case clipboardHistory
        case recoveryKey
        case changePassword
        case securityReport
        case quickSearch
        case changelog
        case totpSetup(UUID)
        case deleteConfirmation(Entry)
        case migrate
        case settings

        var id: String {
            switch self {
            case .addEntry(let s): return "add-\(s)"
            case .editEntry(let e): return "edit-\(e.id)"
            case .totpSetup(let id): return "totp-\(id)"
            case .deleteConfirmation(let e): return "delete-\(e.id)"
            default: return String(describing: self)
            }
        }
    }

    // MARK: Preferences

    @AppStorage(BiometricPreference.quickUnlockKey) var quickUnlockEnabled = false { didSet { objectWillChange.send() } }
    @AppStorage("vf.autoLockPolicy") var autoLockPolicyRaw = 5
    @AppStorage("vf.lockOnScreenLock") var lockOnScreenLock = true
    @AppStorage("vf.lockOnSleep") var lockOnSleep = true
    @AppStorage("vf.lockOnHide") var lockOnHide = false
    @AppStorage("vf.hideOnDeactivate") var hideOnDeactivate = false
    @AppStorage(BiometricPreference.clipboardHistoryKey) var clipboardHistoryEnabled = false
    @AppStorage(BiometricPreference.retentionHoursKey) var historyRetentionHours = 24
    @AppStorage("vf.clipboardClearSeconds") var clipboardClearSeconds = 30
    @AppStorage("vf.requireAuthToReveal") var requireAuthToReveal = false
    @AppStorage("vf.breachCheckEnabled") var breachCheckEnabled = true
    @AppStorage(BiometricPreference.showMenuBarKey) var showMenuBarExtra = true
    // The liquid-glass design is built for dark; default to Dark.
    @AppStorage("vf.appearance") var appearanceRaw = Appearance.dark.rawValue
    @AppStorage("vf.generatorOptions") var generatorOptionsJSON = ""
    @AppStorage("vf.failedAttempts") var failedAttempts = 0
    @AppStorage("vf.hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("vf.firstRunDate") var firstRunDate = ""
    @AppStorage("vf.totpCopyToClipboard") var totpCopyToClipboard = true

    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System", dark = "Dark", light = "Light"
        var id: String { rawValue }
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .dark: return NSAppearance(named: .darkAqua)
            case .light: return NSAppearance(named: .aqua)
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .dark: return .dark
            case .light: return .light
            }
        }
    }

    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    // MARK: Dependencies

    let session: VaultSession
    private let autoLock = AutoLockController.shared
    private let clipboard = ClipboardService.shared

    @Published var toast: Toast?


    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    init(url: URL = VaultSession.defaultVaultURL()) {
        self.session = VaultSession(url: url)
        self.vaultURL = url
        self.vaultExists = FileManager.default.fileExists(atPath: url.path)
        wireAutoLock()
        applyAppearance()
        refreshVaultPresence()
    }

    // MARK: Lifecycle

    func refreshVaultPresence() {
        vaultExists = FileManager.default.fileExists(atPath: vaultURL.path)
        lockState = vaultExists ? (lockState == .unlocked ? .unlocked : .locked) : .needsVault
    }

    private func wireAutoLock() {
        autoLock.onLock = { [weak self] in
            Task { @MainActor in self?.lock(reason: "auto") }
        }
        autoLock.policy = AutoLockController.Policy(rawValue: autoLockPolicyRaw) ?? .fiveMinutes
        autoLock.lockOnScreenLock = lockOnScreenLock
        autoLock.lockOnSleep = lockOnSleep
        autoLock.lockOnHide = lockOnHide
    }

    func syncAutoLockSettings() {
        autoLock.policy = AutoLockController.Policy(rawValue: autoLockPolicyRaw) ?? .fiveMinutes
        autoLock.lockOnScreenLock = lockOnScreenLock
        autoLock.lockOnSleep = lockOnSleep
        autoLock.lockOnHide = lockOnHide
    }

    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    func registerActivity() {
        guard lockState == .unlocked else { return }
        autoLock.registerActivity()
    }

    // MARK: Unlock / lock

    func unlock(with password: String) async {
        lockState = .unlocking
        lastUnlockError = nil
        do {
            let (sessionValue, document) = try await session.verify(password)
            await session.unlock(with: sessionValue, document: document)
            // Legacy (Python/Java) vault: keep working, but offer an upgrade.
            let cipher = sessionValue.cipher
            if cipher != .aes256gcm {
                toast = Toast(message: "Opened a \(cipher == .fernet ? "Python (Fernet)" : "Java") vault. Save to upgrade to AES-256-GCM.", isError: false)
            }
            finishUnlock()
            if quickUnlockEnabled, VaultKeychain.biometryAvailable {
                try? VaultKeychain.storeMasterKey(sessionValue.key, label: hostName)
            }
            failedAttempts = 0
            if breachCheckEnabled {
                Task { await BreachChecker.shared.setEnabled(true) }
            }
        } catch {
            failedAttempts += 1
            let message = failedMessages(error: error)
            lastUnlockError = message
            lockState = .locked
            toast = Toast(message: message, isError: true)
        }
    }

    private func failedMessages(error: Error) -> String {
        if let formatError = error as? VaultFormatError {
            switch formatError {
            case .wrongPassword:
                let remaining = max(0, 5 - failedAttempts)
                if remaining > 0 {
                    return "Incorrect master password. \(remaining) attempt\(remaining == 1 ? "" : "s") left before a cooling-off pause."
                }
                return "Too many failed attempts. Wait a moment before trying again."
            default:
                return formatError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    func unlockWithKeychain() async {
        lockState = .unlocking
        do {
            let key = try await VaultKeychain.loadMasterKey(reason: "Unlock VaultFlow")
            let data = try AtomicFileStore.read(from: vaultURL)
            let parsed = try VaultFormat.parseEnvelope(data)
            let plaintext = try VaultFormat.decrypt(payload: parsed.payload, key: key, cipher: parsed.cipher)
            let document = try VaultSerializer.decode(plaintext)
            let sessionValue = UnlockedSession(key: key, salt: parsed.salt, cipher: parsed.cipher,
                                               parameters: parsed.parameters, extensions: parsed.extensions)
            await session.unlock(with: sessionValue, document: document)
            finishUnlock()
        } catch {
            lockState = .locked
            toast = Toast(message: error.localizedDescription, isError: true)
        }
    }

    /// Creates a brand-new vault; returns the recovery key for onboarding.
    func createVault(password: String) async -> String? {
        do {
            let (sessionValue, recoveryKey) = try VaultSession.createVault(at: vaultURL, password: password)
            let document = VaultDocument()
            await session.unlock(with: sessionValue, document: document)
            vaultExists = true
            hasCompletedOnboarding = true
            firstRunDate = ISO8601DateFormatter().string(from: Date())
            finishUnlock()
            if quickUnlockEnabled, VaultKeychain.biometryAvailable {
                try? VaultKeychain.storeMasterKey(sessionValue.key, label: hostName)
            }
            return recoveryKey
        } catch {
            toast = Toast(message: "Could not create the vault: \(error.localizedDescription)", isError: true)
            return nil
        }
    }

    private func finishUnlock() {
        lockState = .unlocked
        lastUnlockError = nil
        Task {
            await reloadEntries()
            clipboard.historyEnabled = clipboardHistoryEnabled
            clipboard.clearAfterSeconds = clipboardClearSeconds
            clipboard.expireHistory(retentionHours: historyRetentionHours)
        }
        autoLock.registerActivity()
    }

    func lock(reason: String = "manual") {
        guard lockState == .unlocked else { return }
        if reason == "auto" {
            toast = Toast(message: "Vault locked automatically.", isError: false)
        }
        lockState = .locked
        entries = []
        selectedEntryID = nil
        searchText = ""
        clipboard.historyEnabled = false
        clipboard.wipe()
        activeSheet = nil
        Task { await session.lock() }
    }

    // MARK: Data operations

    func reloadEntries() async {
        let document = await session.snapshot()
        apply(document: document)
    }

    private func apply(document: VaultDocument) {
        let all = document.allEntries
        entries = all
        var foundFolders = Set(VaultFolder.defaultFolders)
        var tags: [String: Int] = [:]
        for entry in all {
            if !entry.folder.isEmpty { foundFolders.insert(entry.folder) }
            for tag in entry.tags { tags[tag, default: 0] += 1 }
        }
        folders = foundFolders.sorted { lhs, rhs in
            let li = VaultFolder.defaultFolders.firstIndex(of: lhs) ?? 99
            let ri = VaultFolder.defaultFolders.firstIndex(of: rhs) ?? 99
            return li == ri ? lhs.localizedStandardCompare(rhs) == .orderedAscending : li < ri
        }
        tagIndex = tags
        saveState = .saved
        if let selectedEntryID, !all.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = nil
        }
    }

    private func persist() async {
        saveState = .saving
        do {
            try await session.save()
            await reloadEntries()
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
            toast = Toast(message: "Could not save: \(error.localizedDescription)", isError: true)
        }
    }

    func addEntry(_ entry: Entry) {
        Task {
            do {
                let stored = try await session.add(entry)
                await persist()
                selectedEntryID = stored.id
                toast = Toast(message: "Saved “\(stored.service)”", isError: false)
            } catch {
                toast = Toast(message: error.localizedDescription, isError: true)
            }
        }
    }

    func updateEntry(_ entry: Entry) {
        Task {
            do {
                _ = try await session.update(entry)
                await persist()
                toast = Toast(message: "Updated “\(entry.service)”", isError: false)
            } catch {
                toast = Toast(message: error.localizedDescription, isError: true)
            }
        }
    }

    func deleteEntry(_ entry: Entry) {
        Task {
            do {
                try await session.delete(id: entry.id)
                await persist()
                if selectedEntryID == entry.id { selectedEntryID = nil }
                toast = Toast(message: "Deleted “\(entry.service)”", isError: false)
            } catch {
                toast = Toast(message: error.localizedDescription, isError: true)
            }
        }
    }

    func toggleFavorite(_ entry: Entry) {
        var copy = entry
        copy.favorite.toggle()
        updateEntry(copy)
    }

    func duplicate(_ entry: Entry) {
        // Keep every field — including favourites, TOTP secrets and custom
        // fields — and only give the copy a fresh identity and timestamps.
        var copy = entry
        copy.id = UUID()
        copy.createdAt = Date()
        copy.updatedAt = Date()
        addEntry(copy)
    }

    func renameFolder(_ old: String, to new: String) {
        let affected = entries.filter { $0.folder == old }
        guard !affected.isEmpty else { return }
        Task {
            for var entry in affected {
                entry.folder = new
                _ = try? await session.update(entry)
            }
            await persist()
            if case .folder(old) = destination { destination = .folder(new) }
        }
    }

    func moveEntry(_ entry: Entry, to folder: String) {
        var copy = entry
        copy.folder = folder
        updateEntry(copy)
    }

    func setTOTP(secret: String, for id: UUID, issuer: String? = nil) {
        guard var entry = entries.first(where: { $0.id == id }) else { return }
        entry.totpSecret = secret
        if let issuer, entry.notes.isEmpty { entry.notes = issuer }
        updateEntry(entry)
    }

    // MARK: Import / export

    func importRecords(_ records: [ImportedRecord]) async -> Int {
        var folderSet = Set(folders)
        let document = PasswordImporter.recordsToDocument(records, folders: &folderSet)
        let existing = await session.snapshot()
        var merged = existing
        for (service, newEntries) in document.services {
            var bucket = merged.services[service] ?? []
            for var entry in newEntries {
                if bucket.contains(where: { $0.username == entry.username && $0.username != "" }) {
                    entry.username += " (imported)"
                }
                bucket.append(entry)
            }
            merged.services[service] = bucket
        }
        await session.replaceAll(merged)
        await persist()
        return records.count
    }

    func exportDocument(services: [String]? = nil) async throws -> VaultDocument {
        var document = await session.snapshot()
        if let services {
            document.services = document.services.filter { services.contains($0.key) }
        }
        return document
    }

    func changePassword(current: String, new: String) async throws {
        // Verify first so a typo can't corrupt the vault.
        _ = try await session.verify(current)
        try await session.changePassword(to: new)
        await reloadEntries()
    }

    func recoveryKey(password: String? = nil) async -> String? {
        guard let password else {
            // Without the password we can only show the stored hint.
            let document = await session.snapshot()
            return document.rootUnknownKeys["x-vaultflow"]?["recovery"]?["hint"]?.stringValue
        }
        return await session.recoveryKey(password: password)
    }

    func regenerateRecoveryKey(password: String) async -> String? {
        (try? await session.regenerateRecoveryKey(password: password))
    }

    // MARK: Legacy migration

    /// Opens a vault file written by the Python/Java versions and adopts it.
    func migrateVault(from url: URL, password: String) async throws -> LegacyVaultKind {
        let data = try Data(contentsOf: url)
        let unlocked = try VaultMigration.open(data, password: password)
        await session.openFile(at: url, session: unlocked.session, document: unlocked.document)
        vaultURL = url
        await reloadEntries()
        saveState = .saved
        lockState = .unlocked
        return unlocked.kind
    }

    // MARK: Clipboard

    func copy(_ value: String, label: String, sensitive: Bool = true) {
        clipboard.copy(value, label: label, sensitive: sensitive)
        toast = Toast(message: sensitive ? "Copied “\(label)” — clears in \(clipboardClearSeconds)s" : "Copied “\(label)”",
                      isError: false)
    }

    func copyTemporarily(_ value: String, label: String) {
        clipboard.copyTemporarily(value, label: label)
        toast = Toast(message: "Copied “\(label)”", isError: false)
    }

    func copyTOTP(for entry: Entry) {
        guard let configuration = TOTPConfiguration.parse(entry.totpSecret) else {
            toast = Toast(message: "This entry has no valid one-time-password secret.", isError: true)
            return
        }
        let code = TOTP.code(for: configuration).replacingOccurrences(of: " ", with: "")
        copy(code, label: "\(entry.service) code")
    }

    // MARK: Search & filtering

    var filteredEntries: [Entry] {
        var result = entries
        switch destination {
        case .all: break
        case .favorites: result = result.filter(\.favorite)
        case .folder(let folder): result = result.filter { $0.folder == folder }
        case .tag(let tag): result = result.filter { $0.tags.contains(tag) }
        case .watchtower, .generator, .history, .settings: result = []
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.searchIndex.contains(query) }
        }
        switch sortOrder {
        case .name:
            result.sort { ($0.service.lowercased(), $0.username.lowercased()) < ($1.service.lowercased(), $1.username.lowercased()) }
        case .recent:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .created:
            result.sort { $0.createdAt > $1.createdAt }
        case .strength:
            result.sort { PasswordStrength.evaluate($0.password).bits < PasswordStrength.evaluate($1.password).bits }
        }
        return result
    }

    /// Grouped for the list view (alphabetical sections).
    var groupedEntries: [(String, [Entry])] {
        Dictionary(grouping: filteredEntries) { entry -> String in
            let first = entry.service.first.map { String($0).uppercased() } ?? "#"
            return first.rangeOfCharacter(from: .letters) != nil ? first : "#"
        }
        .map { ($0.key, $0.value) }
        .sorted { $0.0 < $1.0 }
    }

    var selectedEntry: Entry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    var quickSearchResults: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Array(entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)) }
        return entries.filter { $0.searchIndex.contains(query) }.prefix(8).map { $0 }
    }

    // MARK: Stats

    struct Stats {
        var total: Int
        var weak: Int
        var reused: Int
        var aging: Int
        var withTOTP: Int
        var favorites: Int
        var averageAge: Double
        var strongPercent: Double
    }

    var stats: Stats {
        let evaluated = entries.map { ($0, PasswordStrength.evaluate($0.password)) }
        let weak = evaluated.filter { $0.1.isWeak }.count
        var counts: [String: Int] = [:]
        for entry in entries where !entry.password.isEmpty {
            counts[entry.password, default: 0] += 1
        }
        let reused = entries.filter { (counts[$0.password] ?? 0) > 1 }.count
        let aging = entries.filter { $0.ageInDays > 180 }.count
        let strong = evaluated.filter { $0.1.score >= .strong }.count
        let total = entries.count
        return Stats(
            total: total,
            weak: weak,
            reused: reused,
            aging: aging,
            withTOTP: entries.filter(\.hasTOTP).count,
            favorites: entries.filter(\.favorite).count,
            averageAge: total == 0 ? 0 : Double(entries.map(\.ageInDays).reduce(0, +)) / Double(total),
            strongPercent: total == 0 ? 0 : Double(strong) / Double(total)
        )
    }

    var hostName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    func showToast(_ message: String, isError: Bool = false) {
        toast = Toast(message: message, isError: isError)
    }
}
