// MainShellView.swift
// VaultFlow · Three-column vault window
//
// The window is built as a set of floating Liquid Glass panes: a chrome bar,
// a sidebar, an item list and an inspector. Nothing is edge-to-edge; every
// surface is inset, rounded and refracts the living backdrop behind it.

import SwiftUI
import VaultFlowCore

struct MainShellView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        VStack(spacing: 10) {
            TitleBar(
                title: title,
                toggleSidebar: { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { model.toggleSidebar() } }
            )

            HStack(spacing: 12) {
                if model.sidebarVisible {
                    SidebarView()
                        .frame(width: 230)
                        .glassPanel()
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                ItemListView()
                    .frame(width: 372)
                    .glassPanel()
                DetailRouter()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 14)
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

/// Floating chrome capsule: identity, live vault status, and the primary actions.
/// The glass bar starts behind the traffic lights, with an inset so they stay clear.
struct TitleBar: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var shortcuts = ShortcutStore.shared
    @ObservedObject private var clipboard = ClipboardService.shared
    let title: String
    let toggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(VaultTheme.subtle)
                    .background {
                        GlassBackdrop(glass: .clear.interactive(), shape: Circle())
                    }
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar (\(shortcuts.binding(for: .toggleSidebar).displayString))")

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(VaultTheme.ringGradient)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VaultTheme.ink)
                .lineLimit(1)

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 2)

            statusItems

            Spacer(minLength: 8)

            Button {
                model.activeSheet = .quickSearch
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(VaultTheme.subtle)
                    .background {
                        GlassBackdrop(glass: .clear.interactive(), shape: Circle())
                    }
            }
            .buttonStyle(.plain)
            .help("Quick search (\(shortcuts.binding(for: .quickSearch).displayString))")

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
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(VaultTheme.subtle)
                    .background {
                        GlassBackdrop(glass: .clear.interactive(), shape: Circle())
                    }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
            .help("More actions")

            Button {
                model.activeSheet = .addEntry(service: "")
            } label: {
                Label("New Item", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(VaultButtonStyle(kind: .primary))
            .help("New password (\(shortcuts.binding(for: .newEntry).displayString))")
        }
        .padding(.leading, 74)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .glass(cornerRadius: 20, strokeOpacity: 0.26)
    }

    @ViewBuilder
    private var statusItems: some View {
        HStack(spacing: 9) {
            Label("\(model.entries.count) item\(model.entries.count == 1 ? "" : "s")", systemImage: "key.horizontal")
                .foregroundStyle(VaultTheme.subtle)
            if model.tagIndex.count > 0 {
                Label("\(model.tagIndex.count)", systemImage: "number")
                    .foregroundStyle(VaultTheme.subtle)
            }
            if let seconds = clipboard.secondsRemaining {
                Label("\(seconds)s", systemImage: "timer")
                    .foregroundStyle(VaultTheme.amber)
                    .transition(.opacity.combined(with: .scale))
            }
            if case .saving = model.saveState {
                Label("Saving", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(VaultTheme.subtle)
            } else if case .failed = model.saveState {
                Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(VaultTheme.amber)
            }
            VaultBadge(text: "Encrypted", systemImage: "checkmark.seal.fill", tint: VaultTheme.mint)
        }
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
        .animation(.easeInOut(duration: 0.2), value: clipboard.secondsRemaining)
    }
}

/// Draws the selection pill behind a sidebar row. A dedicated ButtonStyle is used
/// because a `.background` inside a plain-button label does not render on this
/// toolchain. Selected and hovered rows use real interactive glass.
struct SidebarRowStyle: ButtonStyle {
    var isSelected: Bool
    var isHovered: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isSelected || isHovered {
                    GlassBackdrop(glass: .regular.interactive(), shape: shape,
                                  tint: isSelected ? VaultTheme.royal : nil,
                                  tintOpacity: 0.42)
                }
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
                }
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
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
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 12)

            HStack(spacing: 4) {
                sidebarIconButton("gearshape", help: "Settings") { model.destination = .settings }
                sidebarIconButton("magnifyingglass", help: "Quick search") { model.activeSheet = .quickSearch }
                Spacer()
                Button {
                    model.lock(reason: "sidebar")
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(VaultButtonStyle(kind: .secondary))
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .kerning(0.9)
            .foregroundStyle(VaultTheme.ink.opacity(0.38))
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
        content()
    }

    private func sidebarIconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5))
                .foregroundStyle(VaultTheme.subtle)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
                .background {
                    GlassBackdrop(glass: .clear.interactive(), shape: Circle())
                }
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
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.82)) : AnyShapeStyle(VaultTheme.ink.opacity(0.5)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
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
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [VaultTheme.electric.opacity(0.22), .clear],
                                         center: .center, startRadius: 0, endRadius: 54))
                    .frame(width: 108, height: 108)
                Image(systemName: model.entries.isEmpty ? "sparkles.rectangle.stack" : "hand.point.up.left")
                    .font(.system(size: 38, weight: .thin))
                    .foregroundStyle(VaultTheme.ringGradient)
            }
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
        .padding(.horizontal, 40)
        .padding(.vertical, 44)
        .frame(maxWidth: 430)
        .glassPanel(cornerRadius: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
