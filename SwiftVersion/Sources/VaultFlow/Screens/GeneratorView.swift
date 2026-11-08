// GeneratorView.swift
// VaultFlow · Password generator (characters, passphrase, PIN)
//
// The Python/Java versions only generate character passwords with four boolean
// toggles. This version adds BIP-39 passphrases, PINs, ambiguous-character
// filtering, guaranteed character classes, live strength, batch generation and
// a "no similar characters" history so repeats are obvious.

import SwiftUI
import VaultFlowCore

struct GeneratorView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage("vf.generatorOptions") private var optionsJSON = ""
    @State private var options = GeneratorOptions()
    @State private var password = ""
    @State private var error: String?
    @State private var batches: [String] = []
    @State private var saveTarget = ""
    @State private var saveUsername = ""
    @State private var showSaveSheet = false

    private var strength: StrengthResult { PasswordStrength.evaluate(password) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                outputCard
                optionsCard
                if !batches.isEmpty { batchCard }
            }
            .vaultPagePadding()
            .frame(maxWidth: 720)
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: restore)
        .onChange(of: options) { _, newValue in persist(newValue); regenerate() }
        .sheet(isPresented: $showSaveSheet) { saveSheet }
    }

    // MARK: Output

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(password.isEmpty ? "Select options & generate" : password)
                    .font(.system(size: password.count > 28 ? 17 : 22,
                                  weight: .semibold, design: .monospaced))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                    .foregroundStyle(password.isEmpty ? VaultTheme.faint : Color.primary)
                Spacer(minLength: 8)
                IconAction(systemImage: "arrow.clockwise", help: "Regenerate (⌘R)", tint: VaultTheme.ribbon) {
                    regenerate()
                }
            }
            StrengthMeter(result: strength)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button {
                    toggleCharacterClasses(selectAll: true)
                } label: {
                    Label("Show all character classes", systemImage: "textformat.abc")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(VaultTheme.subtle)
                Spacer()
                Button {
                    model.copy(password, label: "Generated password")
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                Button {
                    saveTarget = ""
                    showSaveSheet = true
                } label: { Label("Save to vault", systemImage: "plus.circle") }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
            }
            .disabled(password.isEmpty)
        }
        .padding(18)
        .glass(cornerRadius: 18)
    }

    // MARK: Options

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $options.mode) {
                ForEach(GenerationMode.allCases, id: \.self) { mode in
                    Text(title(for: mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch options.mode {
            case .characters: charactersOptions
            case .passphrase: passphraseOptions
            case .pin: pinOptions
            }
        }
        .padding(18)
        .glass(cornerRadius: 18)
    }

    private func title(for mode: GenerationMode) -> String {
        switch mode {
        case .characters: return "Characters"
        case .passphrase: return "Passphrase"
        case .pin: return "PIN"
        }
    }

    private var charactersOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Length").font(.system(size: 12, weight: .medium))
                Slider(value: Binding(get: { Double(options.length) },
                                      set: { options.length = Int($0.rounded()) }), in: 8...128, step: 1)
                TextField("", value: Binding(get: { options.length },
                                             set: { options.length = min(128, max(8, $0)) }),
                          format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 54)
                    .font(.system(size: 12).monospacedDigit())
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                classToggle("Lowercase", .lowercase, "abcdefghij")
                classToggle("Uppercase", .uppercase, "ABCDEFGHIJ")
                classToggle("Numbers", .digits, "0123456789")
                classToggle("Symbols", .symbols, "!@#$%^&*")
            }
            if options.characterSets.contains(.custom) {
                TextField("Custom characters", text: $options.customCharacters)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            Toggle("Avoid ambiguous characters (0/O, 1/l/I)", isOn: $options.avoidAmbiguous)
                .toggleStyle(.checkbox).font(.system(size: 12))
            Toggle("Require at least one of every selected class", isOn: $options.requireEveryClass)
                .toggleStyle(.checkbox).font(.system(size: 12))
        }
    }

    private func classToggle(_ label: String, _ characterSet: PasswordCharacterSet, _ sample: String) -> some View {
        let isOn = Binding(
            get: { options.characterSets.contains(characterSet) },
            set: { on in
                if on { options.characterSets.insert(characterSet) }
                else { options.characterSets.remove(characterSet) }
            }
        )
        return Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 12))
                Text(sample)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(VaultTheme.faint)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var passphraseOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Words").font(.system(size: 12, weight: .medium)).frame(width: 52, alignment: .leading)
                Slider(value: Binding(get: { Double(options.wordCount) },
                                      set: { options.wordCount = Int($0.rounded()) }), in: 3...10, step: 1)
                Text("\(options.wordCount)").font(.system(size: 12).monospacedDigit()).frame(width: 20)
            }
            Picker("Separator", selection: $options.separator) {
                Text("Hyphen  -").tag("-")
                Text("Space").tag(" ")
                Text("Dot  .").tag(".")
                Text("Underscore  _").tag("_")
                Text("None").tag("")
            }
            .pickerStyle(.segmented)
            .font(.system(size: 11))
            Toggle("Capitalise each word", isOn: $options.capitalizeWords).toggleStyle(.checkbox).font(.system(size: 12))
            Toggle("Include a random number", isOn: $options.includeDigitInPassphrase).toggleStyle(.checkbox).font(.system(size: 12))
            Toggle("Include a random symbol", isOn: $options.includeSymbolInPassphrase).toggleStyle(.checkbox).font(.system(size: 12))
            Text("Words come from the 2,048-word BIP-39 list, which is easy to type and to memorise.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
        }
    }

    private var pinOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Digits").font(.system(size: 12, weight: .medium)).frame(width: 52, alignment: .leading)
                Slider(value: Binding(get: { Double(options.pinLength) },
                                      set: { options.pinLength = Int($0.rounded()) }), in: 4...12, step: 1)
                Text("\(options.pinLength)").font(.system(size: 12).monospacedDigit()).frame(width: 20)
            }
            Text("PINs are for device locks. Even a 12-digit PIN has only 40 bits of entropy — never use one for an online account.")
                .font(.system(size: 10.5)).foregroundStyle(.orange.opacity(0.85))
        }
    }

    private var batchCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Batch", subtitle: "\(batches.count) alternatives · click one to keep it")
            ForEach(Array(batches.enumerated()), id: \.offset) { index, value in
                HStack {
                    Text(value)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(PasswordStrength.evaluate(value).bits.rounded())) bits")
                        .font(.system(size: 10)).foregroundStyle(VaultTheme.faint)
                    IconAction(systemImage: "checkmark", help: "Use this one", tint: VaultTheme.electric) {
                        password = value
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { password = value }
            }
        }
        .padding(16)
        .glass(cornerRadius: 16)
    }

    private var saveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save generated password").font(.system(size: 15, weight: .semibold))
            TextField("Service (e.g. github.com)", text: $saveTarget).textFieldStyle(.roundedBorder)
            TextField("Username", text: $saveUsername).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showSaveSheet = false }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.addEntry(Entry(service: saveTarget, username: saveUsername, password: password))
                    showSaveSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: Behaviour

    private func regenerate() {
        do {
            password = try PasswordGenerator.generate(options: options)
            error = nil
        } catch {
            self.error = error.localizedDescription
            password = ""
        }
        generateBatch()
        model.registerActivity()
    }

    private func generateBatch() {
        batches = (0..<4).compactMap { _ in try? PasswordGenerator.generate(options: options) }
    }

    private func toggleCharacterClasses(selectAll: Bool) {
        options.characterSets = selectAll
            ? Set(PasswordCharacterSet.allCases).subtracting([.custom])
            : []
    }

    private func restore() {
        if let data = optionsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(GeneratorOptions.self, from: data) {
            options = decoded
        }
        regenerate()
    }

    private func persist(_ value: GeneratorOptions) {
        if let data = try? JSONEncoder().encode(value) {
            optionsJSON = String(decoding: data, as: UTF8.self)
        }
    }
}
