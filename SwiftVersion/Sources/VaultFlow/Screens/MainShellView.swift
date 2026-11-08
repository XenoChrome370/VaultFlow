// MainShellView.swift
// VaultFlow · Three-column vault window
//
// Sidebar (folders / tools / tags) · item list · inspector-style detail.
// Uses the native translucent sidebar materials of macOS 26 so it blends with
// the system Liquid Glass chrome instead of drawing its own title bar.

import SwiftUI
import VaultFlowCore

struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(
                title: title,
                toggleSidebar: { withAnimation(.easeInOut(duration: 0.2)) { model.toggleSidebar() } }
            )
            StatusStrip()
            Divider().opacity(0.35)
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    SidebarView()
                        .frame(width: 236)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().opacity(0.45)
                }
                ItemListView()
                    .frame(width: 380)
                Divider().opacity(0.45)
                DetailRouter()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var title: String {
        switch model.destination {
        case .all: return "All Items"
        case .favorites: return "Favorites"
        case .folder(let folder): return folder
        case .tag(let tag): return "#\(tag)"
        case .watchtower: return "Watchtower"
        case .generator: return "Password Generator"
        case .history: return "Clipboard History"
        case .settings: return "Settings"
        }
    }
}

/// Window title row with the sidebar toggle and the primary actions.
struct TitleBar: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var shortcuts = ShortcutStore.shared
    let title: String
    let toggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaultTheme.subtle)
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar (\(shortcuts.binding(for: .toggleSidebar).displayString))")

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VaultTheme.electric)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VaultTheme.ink)
            Spacer()
            Button {
                model.activeSheet = .quickSearch
            } label: {
                Label("Quick Search", systemImage: "magnifyingglass")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(VaultButtonStyle(kind: .ghost))
            .help("Quick search (\(shortcuts.binding(for: .quickSearch).displayString))")

            Button {
                model.activeSheet = .addEntry(service: "")
            } label: {
                Label("New Item", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(VaultButtonStyle(kind: .primary))
            .help("New password (\(shortcuts.binding(for: .newEntry).displayString))")

            Menu {
                Picker("Sort by", selection: $model.sortOrder) {
                    ForEach(AppModel.SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                Divider()
                Button("Import…") { model.activeSheet = .importVault }
                Button("Export…") { model.activeSheet = .exportVault }
                Divider()
                Button("Settings…") { model.activeSheet = .settings }
                Button("Lock Vault") { model.lock(reason: "toolbar") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(VaultTheme.subtle)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("More actions")
        }
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.035))
    }
}

/// Thin status strip: item count, save state, clipboard countdown, lock state.
struct StatusStrip: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var clipboard = ClipboardService.shared

    var body: some View {
        HStack(spacing: 12) {
            Label("\(model.entries.count) item\(model.entries.count == 1 ? "" : "s")", systemImage: "key.horizontal")
            if let tags = Optional(model.tagIndex.count), tags > 0 {
                Text("·").foregroundStyle(VaultTheme.faint)
                Label("\(tags) tag\(tags == 1 ? "" : "s")", systemImage: "number")
            }
            Spacer()
            if let seconds = clipboard.secondsRemaining {
                Label("Clipboard clears in \(seconds)s", systemImage: "timer")
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
            if case .saving = model.saveState {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(VaultTheme.subtle)
            } else if case .failed(let message) = model.saveState {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Label("Encrypted", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green.opacity(0.85))
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(VaultTheme.subtle)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.4) }
        .animation(.easeInOut(duration: 0.2), value: clipboard.secondsRemaining)
    }
}

/// Draws the selection pill behind a sidebar row. A dedicated ButtonStyle is used
/// because a `.background` inside a plain-button label does not render on this
/// toolchain.
struct SidebarRowStyle: ButtonStyle {
    var isSelected: Bool
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [VaultTheme.electric.opacity(0.9), VaultTheme.flow.opacity(0.85)],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.white.opacity(isHovered || configuration.isPressed ? 0.08 : 0)))
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovered: AppModel.Destination?

    /// Folders declared by the vault schema only; custom folders appear under
    /// "Tags"/custom sections to avoid duplicates.
    private var displayedFolders: [String] {
        let known = VaultFolder.defaultFolders
        return model.folders.filter { known.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    group("Vault") {
                        row(.all, title: "All Items", icon: "square.stack.3d.up.fill", count: model.entries.count)
                        row(.favorites, title: "Favorites", icon: "star.fill",
                            count: model.entries.filter(\.favorite).count, tint: .yellow)
                        ForEach(displayedFolders, id: \.self) { folder in
                            row(.folder(folder), title: folder,
                                icon: icon(for: folder),
                                count: model.entries.filter { $0.folder == folder }.count,
                                tint: color(for: folder))
                        }
                    }
                    group("Tools") {
                        row(.watchtower, title: "Watchtower", icon: "shield.lefthalf.filled",
                            count: model.stats.weak, tint: .orange)
                        row(.generator, title: "Generator", icon: "wand.and.stars", count: nil,
                            tint: VaultTheme.ribbon)
                        row(.history, title: "Clipboard", icon: "doc.on.clipboard", count: nil)
                    }
                    if !model.tagIndex.isEmpty {
                        group("Tags") {
                            ForEach(model.tagIndex.keys.sorted(), id: \.self) { tag in
                                row(.tag(tag), title: tag, icon: "number", count: model.tagIndex[tag])
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            VStack(spacing: 8) {
                Divider().opacity(0.35)
                HStack(spacing: 8) {
                    sidebarIconButton("gearshape", help: "Settings") { model.destination = .settings }
                    sidebarIconButton("magnifyingglass.circle", help: "Quick search") { model.activeSheet = .quickSearch }
                    Spacer()
                    Button {
                        model.lock(reason: "sidebar")
                    } label: {
                        Label("Lock", systemImage: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(VaultTheme.ink.opacity(0.42))
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
        content()
    }

    private func sidebarIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(VaultTheme.subtle)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func row(_ destination: AppModel.Destination, title: String, icon: String,
                     count: Int?, tint: Color = VaultTheme.electric) -> some View {
        let isSelected = model.destination == destination
        let isHovered = hovered == destination
        return Button {
            model.destination = destination
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(VaultTheme.ink))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(VaultTheme.ink.opacity(0.55)))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarRowStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { inside in
            if inside { hovered = destination } else if hovered == destination { hovered = nil }
        }
    }

    private func icon(for folder: String) -> String {
        switch folder {
        case VaultFolder.personal: return "person.fill"
        case VaultFolder.work: return "briefcase.fill"
        case VaultFolder.finance: return "creditcard.fill"
        case VaultFolder.social: return "person.2.fill"
        case VaultFolder.development: return "chevron.left.forwardslash.chevron.right"
        default: return "folder.fill"
        }
    }

    private func color(for folder: String) -> Color {
        switch folder {
        case VaultFolder.personal: return .blue
        case VaultFolder.work: return .indigo
        case VaultFolder.finance: return .green
        case VaultFolder.social: return .pink
        case VaultFolder.development: return .purple
        default: return VaultTheme.electric
        }
    }
}

// MARK: - Detail router

struct DetailRouter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.destination {
            case .watchtower:
                WatchtowerView()
            case .generator:
                GeneratorView()
            case .history:
                ClipboardHistoryView(embedded: true)
            case .settings:
                SettingsView(embedded: true)
            default:
                if let entry = model.selectedEntry {
                    EntryDetailView(entry: entry)
                } else {
                    EmptyDetailView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyDetailView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: model.entries.isEmpty ? "sparkles.rectangle.stack" : "hand.point.up.left")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(VaultTheme.ringGradient)
            if model.entries.isEmpty {
                Text("Your vault is empty").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Create your first password, or import from Chrome, Safari, 1Password, Bitwarden or an older VaultFlow vault.")
                    .font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                HStack {
                    Button {
                        model.activeSheet = .addEntry(service: "")
                    } label: { Label("New Item", systemImage: "plus") }
                        .buttonStyle(VaultButtonStyle(kind: .primary))
                    Button {
                        model.activeSheet = .importVault
                    } label: { Label("Import", systemImage: "square.and.arrow.down") }
                        .buttonStyle(VaultButtonStyle(kind: .secondary))
                }
                .padding(.top, 4)
            } else {
                Text("Select an item").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Pick a password in the list to see its details, or press ⌘N to add a new one.")
                    .font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
