// MainMenu.swift
// VaultFlow · AppKit main menu (the SwiftUI `Commands` scene modifier is not
// available without an `App` scene, so the menu is built by hand).
//
// Every key equivalent comes from `ShortcutStore`, so the menu always matches
// the shortcuts configured in Settings. Menu validation disables the vault
// items while the vault is locked.

import AppKit
import SwiftUI
import VaultFlowCore

@MainActor
enum MainMenuBuilder {

    static func build(model: AppModel, delegate: AppDelegate) -> NSMenu {
        let actions = MainMenuActions(delegate: delegate, model: model)
        // Menu items hold their target weakly; keep the responder alive.
        delegate.mainMenuActions = actions
        let shortcuts = ShortcutStore.shared
        let main = NSMenu()
        main.autoenablesItems = true

        // MARK: App menu

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "VaultFlow")
        appItem.submenu = appMenu
        appMenu.addItem(item("About VaultFlow", #selector(MainMenuActions.showAbout), actions, key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(MainMenuActions.openSettings), actions, key: ","))
        appMenu.addItem(item("Show Menu Bar Icon", #selector(MainMenuActions.toggleMenuBarIcon), actions, key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(shortcutItem("Lock Vault", #selector(MainMenuActions.lockVault),
                                     shortcuts.effectiveBinding(for: .lockVault), actions))
        appMenu.addItem(item("Hide VaultFlow", #selector(NSApplication.hide(_:)), nil, key: "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), nil, key: "h", modifiers: [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), nil, key: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit VaultFlow", #selector(NSApplication.terminate(_:)), nil, key: "q"))

        // MARK: File menu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(shortcutItem("New Password…", #selector(MainMenuActions.newEntry),
                                      shortcuts.effectiveBinding(for: .newEntry), actions))
        fileMenu.addItem(.separator())
        fileMenu.addItem(shortcutItem("Import…", #selector(MainMenuActions.importData),
                                      shortcuts.effectiveBinding(for: .importData), actions))
        fileMenu.addItem(shortcutItem("Export…", #selector(MainMenuActions.exportData),
                                      shortcuts.effectiveBinding(for: .exportData), actions))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), nil, key: "w"))

        // MARK: Edit menu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(item("Undo", Selector(("undo:")), nil, key: "z"))
        editMenu.addItem(item("Redo", Selector(("redo:")), nil, key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Cut", #selector(NSText.cut(_:)), nil, key: "x"))
        editMenu.addItem(item("Copy", #selector(NSText.copy(_:)), nil, key: "c"))
        editMenu.addItem(item("Paste", #selector(NSText.paste(_:)), nil, key: "v"))
        editMenu.addItem(item("Select All", #selector(NSText.selectAll(_:)), nil, key: "a"))
        editMenu.addItem(.separator())
        editMenu.addItem(shortcutItem("Search Vault", #selector(MainMenuActions.focusSearch),
                                      shortcuts.effectiveBinding(for: .focusSearch), actions))
        editMenu.addItem(shortcutItem("Quick Search…", #selector(MainMenuActions.quickSearch),
                                      shortcuts.effectiveBinding(for: .quickSearch), actions))

        // MARK: Vault menu

        let vaultItem = NSMenuItem()
        main.addItem(vaultItem)
        let vaultMenu = NSMenu(title: "Vault")
        vaultItem.submenu = vaultMenu
        vaultMenu.addItem(shortcutItem("All Items", #selector(MainMenuActions.showAll),
                                       shortcuts.effectiveBinding(for: .showAll), actions))
        vaultMenu.addItem(shortcutItem("Favorites", #selector(MainMenuActions.showFavorites),
                                       shortcuts.effectiveBinding(for: .showFavorites), actions))
        vaultMenu.addItem(shortcutItem("Watchtower", #selector(MainMenuActions.showWatchtower),
                                       shortcuts.effectiveBinding(for: .showWatchtower), actions))
        vaultMenu.addItem(shortcutItem("Generator", #selector(MainMenuActions.showGenerator),
                                       shortcuts.effectiveBinding(for: .showGenerator), actions))
        vaultMenu.addItem(shortcutItem("Clipboard History", #selector(MainMenuActions.showClipboardHistory),
                                       shortcuts.effectiveBinding(for: .showClipboardHistory), actions))
        vaultMenu.addItem(.separator())
        vaultMenu.addItem(shortcutItem("Copy Password of Selected Item", #selector(MainMenuActions.copySelectedPassword),
                                       shortcuts.effectiveBinding(for: .copyPassword), actions))
        vaultMenu.addItem(shortcutItem("Copy Username of Selected Item", #selector(MainMenuActions.copySelectedUsername),
                                       shortcuts.effectiveBinding(for: .copyUsername), actions))
        vaultMenu.addItem(shortcutItem("Copy One-Time Code of Selected Item", #selector(MainMenuActions.copySelectedTOTP),
                                       shortcuts.effectiveBinding(for: .copyTOTP), actions))
        vaultMenu.addItem(.separator())
        vaultMenu.addItem(shortcutItem("Toggle Favorite of Selected Item", #selector(MainMenuActions.toggleSelectedFavorite),
                                       shortcuts.effectiveBinding(for: .toggleFavorite), actions))
        vaultMenu.addItem(shortcutItem("Duplicate Selected Item", #selector(MainMenuActions.duplicateSelected),
                                       shortcuts.effectiveBinding(for: .duplicate), actions))
        vaultMenu.addItem(.separator())
        vaultMenu.addItem(item("Security Report…", #selector(MainMenuActions.securityReport), actions, key: ""))
        vaultMenu.addItem(item("Show Recovery Key…", #selector(MainMenuActions.showRecoveryKey), actions, key: ""))
        vaultMenu.addItem(item("Change Master Password…", #selector(MainMenuActions.changePassword), actions, key: ""))
        vaultMenu.addItem(.separator())
        vaultMenu.addItem(item("Open Another Vault…", #selector(MainMenuActions.openOtherVault), actions, key: ""))

        // MARK: View menu

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(shortcutItem("Toggle Sidebar", #selector(MainMenuActions.toggleSidebar),
                                      shortcuts.effectiveBinding(for: .toggleSidebar), actions))
        viewMenu.addItem(.separator())
        viewMenu.addItem(shortcutItem("Previous Item", #selector(MainMenuActions.previousItem),
                                      shortcuts.effectiveBinding(for: .previousItem), actions))
        viewMenu.addItem(shortcutItem("Next Item", #selector(MainMenuActions.nextItem),
                                      shortcuts.effectiveBinding(for: .nextItem), actions))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Toggle Full Screen", #selector(NSWindow.toggleFullScreen(_:)), nil, key: "f", modifiers: [.command, .control]))
        viewMenu.addItem(.separator())
        viewMenu.addItem(shortcutItem("Zoom In", #selector(MainMenuActions.zoomIn),
                                      shortcuts.effectiveBinding(for: .zoomIn), actions))
        viewMenu.addItem(shortcutItem("Zoom Out", #selector(MainMenuActions.zoomOut),
                                      shortcuts.effectiveBinding(for: .zoomOut), actions))
        viewMenu.addItem(shortcutItem("Actual Size", #selector(MainMenuActions.actualSize),
                                      shortcuts.effectiveBinding(for: .actualSize), actions))

        // MARK: Window menu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), nil, key: "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), nil, key: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), nil, key: ""))
        NSApp.windowsMenu = windowMenu

        // MARK: Help menu

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpItem.submenu = helpMenu
        helpMenu.addItem(shortcutItem("VaultFlow Help", #selector(MainMenuActions.showHelp),
                                      shortcuts.effectiveBinding(for: .help), actions))
        NSApp.helpMenu = helpMenu

        return main
    }

    private static func item(_ title: String, _ selector: Selector, _ target: AnyObject?, key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        return menuItem
    }

    private static func shortcutItem(_ title: String, _ selector: Selector, _ combo: KeyCombo, _ target: AnyObject?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: combo.key)
        menuItem.keyEquivalentModifierMask = combo.modifiers
        menuItem.target = target
        return menuItem
    }
}

/// Target for every menu item; keeps validation rules in one place.
@MainActor
final class MainMenuActions: NSObject, NSMenuItemValidation {
    private weak var delegate: AppDelegate?
    private let model: AppModel

    init(delegate: AppDelegate, model: AppModel) {
        self.delegate = delegate
        self.model = model
    }

    private var isUnlocked: Bool { model.lockState == .unlocked }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(newEntry), #selector(importData), #selector(exportData),
             #selector(focusSearch), #selector(quickSearch), #selector(showAll),
             #selector(showFavorites), #selector(showWatchtower), #selector(showGenerator),
             #selector(showClipboardHistory), #selector(securityReport),
             #selector(showRecoveryKey), #selector(changePassword),
             #selector(openOtherVault), #selector(lockVault), #selector(toggleSidebar):
            return isUnlocked
        case #selector(copySelectedPassword), #selector(copySelectedUsername):
            return isUnlocked && model.selectedEntry != nil
        case #selector(copySelectedTOTP):
            return isUnlocked && (model.selectedEntry?.hasTOTP ?? false)
        case #selector(toggleSelectedFavorite), #selector(duplicateSelected):
            return isUnlocked && model.selectedEntry != nil
        case #selector(previousItem), #selector(nextItem):
            return isUnlocked && !model.entries.isEmpty
        case #selector(toggleMenuBarIcon):
            menuItem.state = model.showMenuBarExtra ? .on : .off
            return true
        default:
            return true
        }
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "VaultFlow",
            .applicationVersion: AppInfo.version,
            .version: AppInfo.build,
            .credits: NSAttributedString(
                string: "Encrypted password manager for macOS 26 & 27.\nAES-256-GCM · PBKDF2-SHA256 · Touch ID quick unlock",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            )
        ])
    }

    @objc func openSettings() { delegate?.openSettingsSheet() }
    @objc func lockVault() { model.lock(reason: "menu") }
    @objc func toggleMenuBarIcon() { model.showMenuBarExtra.toggle() }

    @objc func newEntry() { model.activeSheet = .addEntry(service: "") }
    @objc func importData() { model.activeSheet = .importVault }
    @objc func exportData() { model.activeSheet = .exportVault }

    @objc func focusSearch() { model.focusSearch() }
    @objc func quickSearch() { model.openQuickSearch() }

    @objc func showAll() { model.destination = .all }
    @objc func showFavorites() { model.destination = .favorites }
    @objc func showWatchtower() { model.destination = .watchtower }
    @objc func showGenerator() { model.destination = .generator }
    @objc func showClipboardHistory() { model.destination = .history }

    @objc func copySelectedPassword() {
        guard let entry = model.selectedEntry else { return }
        model.copyTemporarily(entry.password, label: "\(entry.service) password")
    }

    @objc func copySelectedUsername() {
        guard let entry = model.selectedEntry else { return }
        model.copyTemporarily(entry.username, label: "\(entry.service) username")
    }

    @objc func copySelectedTOTP() {
        guard let entry = model.selectedEntry else { return }
        model.copyTOTP(for: entry)
    }

    @objc func toggleSelectedFavorite() {
        guard let entry = model.selectedEntry else { return }
        model.toggleFavorite(entry)
    }

    @objc func duplicateSelected() {
        guard let entry = model.selectedEntry else { return }
        model.duplicate(entry)
    }

    @objc func previousItem() { model.selectAdjacent(offset: -1) }
    @objc func nextItem() { model.selectAdjacent(offset: 1) }
    @objc func toggleSidebar() { model.toggleSidebar() }

    @objc func securityReport() { model.activeSheet = .securityReport }
    @objc func showRecoveryKey() { model.activeSheet = .recoveryKey }
    @objc func changePassword() { model.activeSheet = .changePassword }
    @objc func openOtherVault() { model.activeSheet = .migrate }
    @objc func showHelp() { model.activeSheet = .changelog }

    @objc func zoomIn() { ZoomLevel.shared.step(+1) }
    @objc func zoomOut() { ZoomLevel.shared.step(-1) }
    @objc func actualSize() { ZoomLevel.shared.reset() }
}
