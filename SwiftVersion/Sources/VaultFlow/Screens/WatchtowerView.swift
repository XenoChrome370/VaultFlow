// WatchtowerView.swift
// VaultFlow · Security overview (new in the Swift version)
//
// Scores every stored password, flags reuse, ageing, missing 2FA and (optionally)
// breaches using the Have I Been Pwned k-anonymity range API — only the first
// five hex characters of the SHA-1 ever leave the Mac.

import SwiftUI
import VaultFlowCore

struct WatchtowerView: View {
    @EnvironmentObject private var model: AppModel

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All issues"
        case weak = "Weak"
        case reused = "Reused"
        case aging = "Old"
        case noTwoFactor = "No 2FA"
        case breached = "Breached"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var breachResults: [UUID: Int] = [:]
    @State private var breachScanning = false
    @State private var breachMessage = ""

    private var evaluated: [(Entry, StrengthResult)] {
        model.entries.map { ($0, PasswordStrength.evaluate($0.password)) }
    }

    private var reuseCounts: [String: Int] {
        Dictionary(grouping: model.entries, by: \.password).mapValues(\.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                scoreCard
                breachCard
                metricsGrid
                issuesCard
            }
            .vaultPagePadding()
            .frame(maxWidth: 760)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Health score

    private var healthScore: Int {
        guard !model.entries.isEmpty else { return 100 }
        let weak = evaluated.filter { $0.1.isWeak }.count
        let reused = model.entries.filter { (reuseCounts[$0.password] ?? 0) > 1 }.count
        let aging = model.entries.filter { $0.ageInDays > 180 }.count
        let breached = breachResults.values.filter { $0 > 0 }.count
        let total = Double(model.entries.count)
        let penalty = (Double(weak) * 1.0 + Double(reused) * 0.8 + Double(aging) * 0.5 + Double(breached) * 1.2) / total
        return max(0, min(100, Int(100 - penalty * 45)))
    }

    private var scoreCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(healthScore) / 100)
                    .stroke(scoreGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -2) {
                    Text("\(healthScore)").font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    Text("/100").font(.system(size: 9)).foregroundStyle(VaultTheme.subtle)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 5) {
                Text(scoreHeadline)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(scoreDetail)
                    .font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    VaultBadge(text: "\(model.stats.total) items", systemImage: "key.horizontal")
                    VaultBadge(text: "\(model.stats.strongPercent.formatted(.percent.precision(.fractionLength(0)))) strong",
                               systemImage: "bolt.fill", tint: .green)
                    VaultBadge(text: "\(model.stats.withTOTP) with 2FA", systemImage: "clock.badge.checkmark",
                               tint: VaultTheme.flow)
                }
            }
            Spacer()
            Button {
                model.activeSheet = .securityReport
            } label: { Label("Report", systemImage: "doc.text.magnifyingglass") }
                .buttonStyle(VaultButtonStyle(kind: .secondary))
        }
        .padding(18)
        .glass(cornerRadius: 18)
    }

    private var scoreGradient: AngularGradient {
        AngularGradient(colors: [scoreColor.opacity(0.7), scoreColor, scoreColor.opacity(0.7)],
                        center: .center)
    }

    private var scoreColor: Color {
        healthScore >= 85 ? .green : healthScore >= 65 ? .yellow : healthScore >= 40 ? .orange : .red
    }

    private var scoreHeadline: String {
        if model.entries.isEmpty { return "Nothing to audit yet" }
        switch healthScore {
        case 90...: return "Fortress-grade"
        case 75..<90: return "Solid"
        case 55..<75: return "Needs a tune-up"
        default: return "At risk"
        }
    }

    private var scoreDetail: String {
        guard !model.entries.isEmpty else { return "Add a few items and VaultFlow will start scoring your passwords." }
        let weak = evaluated.filter { $0.1.isWeak }.count
        let reused = model.entries.filter { (reuseCounts[$0.password] ?? 0) > 1 }.count
        if weak == 0 && reused == 0 { return "No weak or reused passwords found. Keep it up." }
        var parts: [String] = []
        if weak > 0 { parts.append("\(weak) weak password\(weak == 1 ? "" : "s")") }
        if reused > 0 { parts.append("\(reused) reused") }
        return "Fix " + parts.joined(separator: " and ") + " to raise your score."
    }

    // MARK: HIBP

    private var breachCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 22))
                .foregroundStyle(VaultTheme.ringGradient)
            VStack(alignment: .leading, spacing: 3) {
                Text(breachMessage.isEmpty ? "Have I Been Pwned check" : breachMessage)
                    .font(.system(size: 12.5, weight: .medium))
                Text("Only the first 5 characters of each password's SHA-1 leave this Mac (k-anonymity).")
                    .font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
            }
            Spacer()
            if breachScanning {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await scanBreaches() }
            } label: { Label("Scan now", systemImage: "magnifyingglass.circle") }
                .buttonStyle(VaultButtonStyle(kind: .secondary))
                .disabled(breachScanning || model.entries.isEmpty)
        }
        .padding(16)
        .glass(cornerRadius: 16)
    }

    private func scanBreaches() async {
        breachScanning = true
        breachMessage = ""
        await BreachChecker.shared.setEnabled(model.breachCheckEnabled)
        var breaches = 0
        var unavailable = 0
        for entry in model.entries {
            if entry.password.isEmpty { continue }
            let result = await BreachChecker.shared.check(password: entry.password)
            switch result {
            case .found(let count):
                breachResults[entry.id] = count
                breaches += 1
            case .clean:
                breachResults[entry.id] = 0
            case .unavailable:
                unavailable += 1
            case .skipped:
                break
            }
        }
        breachScanning = false
        if unavailable > 0 && breaches == 0 {
            breachMessage = "Couldn't reach the breach service — check your connection."
        } else {
            breachMessage = breaches == 0
                ? "No passwords found in known breaches."
                : "\(breaches) password\(breaches == 1 ? "" : "s") found in known breaches."
        }
    }

    // MARK: Metrics

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metric("Weak", "\(model.stats.weak)", "shield.slash", .red)
            metric("Reused", "\(model.stats.reused)", "arrow.triangle.2.circlepath", .orange)
            metric("Aged > 6 mo", "\(model.stats.aging)", "clock.arrow.circlepath", .yellow)
            metric("Average age", "\(Int(model.stats.averageAge))d", "calendar", VaultTheme.ribbon)
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
            Text(title).font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glass(cornerRadius: 14)
    }

    // MARK: Issues

    private var issues: [Entry] {
        switch filter {
        case .all:
            return evaluated.filter { $0.1.isWeak || (reuseCounts[$0.0.password] ?? 0) > 1 || $0.0.ageInDays > 180
                || !$0.0.hasTOTP || (breachResults[$0.0.id] ?? 0) > 0 }.map(\.0)
        case .weak: return evaluated.filter { $0.1.isWeak }.map(\.0)
        case .reused: return model.entries.filter { (reuseCounts[$0.password] ?? 0) > 1 }
        case .aging: return model.entries.filter { $0.ageInDays > 180 }
        case .noTwoFactor: return model.entries.filter { !$0.hasTOTP }
        case .breached: return model.entries.filter { (breachResults[$0.id] ?? 0) > 0 }
        }
    }

    private var issuesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Issues", subtitle: "\(issues.count) item\(issues.count == 1 ? "" : "s") need attention")
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }
            if issues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Nothing to fix in this view.").font(.system(size: 12))
                }
                .padding(.vertical, 6)
            } else {
                ForEach(issues) { entry in
                    HStack(spacing: 10) {
                        ServiceAvatar(service: entry.service, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.service).font(.system(size: 12, weight: .medium))
                            HStack(spacing: 5) {
                                ForEach(issueLabels(for: entry), id: \.self) { label in
                                    Text(label)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        Spacer()
                        Button("Review") {
                            model.selectedEntryID = entry.id
                            model.destination = .all
                        }
                        .buttonStyle(VaultButtonStyle(kind: .ghost))
                        Button {
                            regenerate(for: entry)
                        } label: { Label("Replace", systemImage: "wand.and.stars") }
                            .buttonStyle(VaultButtonStyle(kind: .secondary))
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.3)
                }
            }
        }
        .padding(16)
        .glass(cornerRadius: 16)
    }

    private func issueLabels(for entry: Entry) -> [String] {
        var labels: [String] = []
        let result = PasswordStrength.evaluate(entry.password)
        if result.isWeak { labels.append(result.score.shortLabel) }
        if (reuseCounts[entry.password] ?? 0) > 1 { labels.append("Reused") }
        if entry.ageInDays > 180 { labels.append("\(entry.ageInDays / 30) mo old") }
        if !entry.hasTOTP { labels.append("No 2FA") }
        if let count = breachResults[entry.id], count > 0 { labels.append("Breached \(count)×") }
        return Array(labels.prefix(3))
    }

    private func regenerate(for entry: Entry) {
        var options = GeneratorOptions()
        options.length = max(16, entry.password.count)
        guard let fresh = try? PasswordGenerator.generate(options: options) else { return }
        var copy = entry
        copy.password = fresh
        model.updateEntry(copy)
        model.showToast("Replaced the password for \(entry.service) — update it on the website too.")
    }
}
