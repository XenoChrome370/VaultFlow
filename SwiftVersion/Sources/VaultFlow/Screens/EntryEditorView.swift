// EntryEditorView.swift
// VaultFlow · Add / edit an item

import SwiftUI
import VaultFlowCore

struct EntryEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var entry: Entry?
    var presetService: String = ""

    @State private var service = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var url = ""
    @State private var folder = VaultFolder.personal
    @State private var tagsText = ""
    @State private var notes = ""
    @State private var totp = ""
    @State private var fields: [CustomField] = []
    @State private var favorite = false
    @State private var showPassword = false
    @State private var error: String?

    private var isEditing: Bool { entry != nil }

    private var strength: StrengthResult { PasswordStrength.evaluate(password) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledField("Service") {
                        TextField("github.com", text: $service)
                    }
                    LabeledField("Username") {
                        HStack(spacing: 6) {
                            TextField("you@example.com", text: $username)
                            if !username.isEmpty {
                                IconAction(systemImage: "doc.on.doc", help: "Copy username") {
                                    model.copy(username, label: "Username", sensitive: false)
                                }
                            }
                        }
                    }
                    LabeledField("Password") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Group {
                                    if showPassword {
                                        TextField("Password", text: $password)
                                    } else {
                                        SecureField("Password", text: $password)
                                    }
                                }
                                .font(.system(size: 13, design: .monospaced))
                                IconAction(systemImage: showPassword ? "eye.slash" : "eye",
                                           help: showPassword ? "Hide" : "Show") {
                                    showPassword.toggle()
                                }
                                IconAction(systemImage: "wand.and.stars", help: "Generate", tint: VaultTheme.ribbon) {
                                    var options = GeneratorOptions()
                                    options.length = 20
                                    if let fresh = try? PasswordGenerator.generate(options: options) {
                                        password = fresh
                                        confirm = fresh
                                        showPassword = true
                                    }
                                }
                            }
                            if !password.isEmpty {
                                StrengthMeter(result: strength)
                            }
                            if isEditing {
                                SecureField("Confirm new password", text: $confirm)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        LabeledField("Folder") {
                            Picker("", selection: $folder) {
                                ForEach(model.folders, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        LabeledField("Website") {
                            TextField("https://…", text: $url)
                        }
                    }
                    LabeledField("Tags") {
                        TextField("comma separated, e.g. work, shared", text: $tagsText)
                    }
                    LabeledField("One-time password") {
                        TextField("otpauth:// URL or Base32 secret", text: $totp)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    LabeledField("Notes") {
                        TextEditor(text: $notes)
                            .font(.system(size: 12))
                            .frame(minHeight: 70)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                    customFieldsSection
                    Toggle("Mark as favorite", isOn: $favorite)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5)).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 520, height: 660)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isEditing ? "square.and.pencil" : "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(VaultTheme.brandGradient)
            Text(isEditing ? "Edit item" : "New item")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if isEditing, let entry {
                Button("Delete", role: .destructive) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        model.activeSheet = .deleteConfirmation(entry)
                    }
                }
                .buttonStyle(VaultButtonStyle(kind: .destructive))
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Save changes" : "Add to vault") { save() }
                .buttonStyle(VaultButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var customFieldsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Custom fields").font(.system(size: 11, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
                Spacer()
                Button {
                    fields.append(CustomField(label: "", value: "", sensitive: false))
                } label: { Label("Add field", systemImage: "plus") }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            ForEach($fields) { $field in
                HStack(spacing: 6) {
                    TextField("Label", text: $field.label).frame(width: 120)
                    TextField("Value", text: $field.value)
                    Toggle("Secret", isOn: $field.sensitive).toggleStyle(.checkbox).font(.system(size: 10.5))
                    IconAction(systemImage: "minus.circle", help: "Remove", tint: .red) {
                        fields.removeAll { $0.id == field.id }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
            }
        }
    }

    private func load() {
        guard let entry else {
            service = presetService
            folder = model.folders.first ?? VaultFolder.personal
            return
        }
        service = entry.service
        username = entry.username
        password = entry.password
        confirm = entry.password
        url = entry.url
        folder = entry.folder
        tagsText = entry.tags.joined(separator: ", ")
        notes = entry.notes
        totp = entry.totpSecret
        fields = entry.customFields
        favorite = entry.favorite
    }

    private func save() {
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedService.isEmpty else {
            error = "Give the item a name, for example the website or app it belongs to."
            return
        }
        if isEditing && password != confirm {
            error = "The new passwords don't match."
            return
        }
        if !totp.trimmingCharacters(in: .whitespaces).isEmpty, TOTPConfiguration.parse(totp) == nil {
            error = "That one-time-password secret couldn't be parsed. Paste an otpauth:// URL or a Base32 secret."
            return
        }
        let tags = tagsText.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleanedFields = fields.filter { !$0.label.isEmpty }

        var result = entry ?? Entry(service: trimmedService, username: "", password: "")
        result.service = trimmedService
        result.username = username.trimmingCharacters(in: .whitespaces)
        result.password = password
        result.url = url.trimmingCharacters(in: .whitespaces)
        result.folder = folder
        result.tags = tags
        result.notes = notes
        result.totpSecret = totp.trimmingCharacters(in: .whitespaces)
        result.customFields = cleanedFields
        result.favorite = favorite

        let requestedUsername: String = result.username
        let duplicate = model.entries.contains { candidate in
            candidate.id != result.id
                && candidate.service == trimmedService
                && candidate.username == requestedUsername
        }
        if duplicate {
            let alert = NSAlert()
            alert.messageText = "Duplicate account"
            alert.informativeText = "\(trimmedService) already has an account with that username. Add it anyway?"
            alert.addButton(withTitle: "Add anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        if isEditing {
            model.updateEntry(result)
            model.showToast("Updated \(trimmedService)")
        } else {
            model.addEntry(result)
            model.showToast("Added \(trimmedService)")
        }
        dismiss()
    }
}

/// Label above an editor control.
struct LabeledField<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
            content
                .font(.system(size: 12.5))
        }
    }
}
