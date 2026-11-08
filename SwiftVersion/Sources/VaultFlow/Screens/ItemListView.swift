// ItemListView.swift
// VaultFlow · Searchable, grouped list of vault items

import SwiftUI
import VaultFlowCore

struct ItemListView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if model.filteredEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.groupedEntries, id: \.0) { group in
                            Section {
                                ForEach(group.1) { entry in
                                    ItemRow(entry: entry,
                                            isSelected: model.selectedEntryID == entry.id,
                                            isHovered: hoveredID == entry.id)
                                        .onTapGesture { select(entry) }
                                        .onHover { hoveredID = $0 ? entry.id : nil }
                                        .contextMenu { contextMenu(for: entry) }
                                }
                            } header: {
                                Text(group.0.uppercased())
                                    .font(.system(size: 9.5, weight: .bold))
                                    .kerning(0.8)
                                    .foregroundStyle(VaultTheme.ink.opacity(0.42))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 9)
                                    .padding(.bottom, 3)
                                    .background(VaultTheme.midnight.opacity(0.10))
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .onChange(of: model.searchFocusRequests) { _, _ in searchFocused = true }
        .onChange(of: model.destination) { _, _ in ensureSelection() }
        .onChange(of: model.searchText) { _, _ in ensureSelection() }
        .onAppear { ensureSelection() }
    }

    /// Keeps the detail pane in sync when a filter hides the selected item.
    private func ensureSelection() {
        guard model.destination.isListDestination else { return }
        if let id = model.selectedEntryID,
           model.filteredEntries.contains(where: { $0.id == id }) {
            return
        }
        model.selectedEntryID = model.filteredEntries.first?.id
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VaultTheme.electric.opacity(0.85))
                    .font(.system(size: 11, weight: .semibold))
                TextField("Search \(model.entries.count) items", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($searchFocused)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(VaultTheme.faint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 6.5)
            .background {
                Capsule().fill(Color.white.opacity(0.055))
            }
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8)
            }

            Menu {
                Picker("Sort", selection: $model.sortOrder) {
                    ForEach(AppModel.SortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
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
            .help("Sort order")
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(VaultTheme.faint)
            Text(model.searchText.isEmpty ? "No items here yet" : "No matches")
                .font(.system(size: 13, weight: .semibold))
            if !model.searchText.isEmpty {
                Text("Nothing matches “\(model.searchText)”.")
                    .font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func select(_ entry: Entry) {
        model.selectedEntryID = entry.id
        model.registerActivity()
    }

    @ViewBuilder
    private func contextMenu(for entry: Entry) -> some View {
        Button("Copy Password") { model.copy(entry.password, label: "\(entry.service) password") }
        Button("Copy Username") { model.copy(entry.username, label: "\(entry.service) username", sensitive: false) }
        if entry.hasTOTP {
            Button("Copy One-Time Code") { model.copyTOTP(for: entry) }
        }
        Divider()
        Button("Edit…") { model.activeSheet = .editEntry(entry) }
        Button(entry.favorite ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite(entry) }
        Menu("Move to Folder") {
            ForEach(model.folders, id: \.self) { folder in
                Button(folder) { model.moveEntry(entry, to: folder) }
                    .disabled(entry.folder == folder)
            }
        }
        Button("Duplicate") { model.duplicate(entry) }
        if !entry.url.isEmpty, let url = URL(string: entry.url.hasPrefix("http") ? entry.url : "https://\(entry.url)") {
            Button("Open Website") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Delete…", role: .destructive) { model.activeSheet = .deleteConfirmation(entry) }
    }
}

private extension AppModel.Destination {
    var isListDestination: Bool {
        switch self {
        case .all, .favorites, .folder, .tag: return true
        default: return false
        }
    }
}

struct ItemRow: View {
    var entry: Entry
    var isSelected: Bool
    var isHovered: Bool

    private var strength: StrengthResult { PasswordStrength.evaluate(entry.password) }

    var body: some View {
        HStack(spacing: 10) {
            ServiceAvatar(service: entry.service, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.service)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if entry.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                    if entry.hasTOTP {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 8.5))
                            .foregroundStyle(VaultTheme.ribbon)
                    }
                }
                Text(entry.username.isEmpty ? "No username" : entry.username)
                    .font(.system(size: 11))
                    .foregroundStyle(VaultTheme.subtle)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if strength.isWeak {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(VaultTheme.strengthColor(strength.score))
                    .help(strength.score.label)
            }
            if isHovered {
                Button {
                    ClipboardService.shared.copy(entry.password, label: "\(entry.service) password")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(VaultTheme.electric)
                }
                .buttonStyle(.plain)
                .help("Copy password")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected
                      ? AnyShapeStyle(LinearGradient(colors: [VaultTheme.electric.opacity(0.26), VaultTheme.flow.opacity(0.18)],
                                                     startPoint: .leading, endPoint: .trailing))
                      : AnyShapeStyle(isHovered ? Color.white.opacity(0.055) : Color.clear))
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(VaultTheme.ribbon)
                    .frame(width: 2.5, height: 18)
                    .padding(.leading, 2)
                    .shadow(color: VaultTheme.ribbon.opacity(0.6), radius: 4)
            }
        }
        .padding(.horizontal, 7)
        .contentShape(Rectangle())
    }
}
