// PasswordStrength.swift
// VaultFlow · Offline password strength analysis
//
// A compact zxcvbn-inspired estimator:
//   1. Classify the password (pure digits / letters / mixed / passphrase).
//   2. Estimate raw character entropy: length × log2(alphabet).
//   3. Penalise common patterns: repeated runs, sequences (abc/123/qwerty),
//      keyboard walks, years, common words and dictionary hits.
//   4. Turn the result into a 0–4 score, human label and crack-time estimate.
//
// Everything is local; no password ever leaves the machine.

import Foundation

public enum StrengthScore: Int, CaseIterable, Comparable, Sendable {
    case extremelyWeak = 0
    case weak = 1
    case fair = 2
    case strong = 3
    case excellent = 4

    public static func < (lhs: StrengthScore, rhs: StrengthScore) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .extremelyWeak: return "Very Weak"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .excellent: return "Excellent"
        }
    }

    public var shortLabel: String {
        switch self {
        case .extremelyWeak: return "Very weak"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .excellent: return "Excellent"
        }
    }
}

public struct StrengthResult: Equatable, Sendable {
    /// Estimated entropy in bits.
    public let bits: Double
    /// 0…4 score.
    public let score: StrengthScore
    /// Qualitative feedback, most important first.
    public let feedback: [String]
    /// Detected weak patterns (empty when clean).
    public let warnings: [String]
    /// Human-readable time to crack at 10^10 guesses / second.
    public let crackTime: String

    public var isBreachProne: Bool { score <= .weak }
    public var isWeak: Bool { score <= .fair }
    public var isReusedOrCommon: Bool { warnings.contains { $0.contains("common") || $0.contains("reused") } }
}

public enum PasswordStrength {

    public static func evaluate(_ password: String) -> StrengthResult {
        guard !password.isEmpty else {
            return StrengthResult(bits: 0, score: .extremelyWeak,
                                  feedback: ["Enter a password"],
                                  warnings: [], crackTime: "instant")
        }

        var bits = rawEntropyBits(password)
        var warnings: [String] = []
        var feedback: [String] = []

        // 1. Common password / dictionary hits
        if let hit = CommonPasswordList.match(password) {
            bits = min(bits, log2(Double(CommonPasswordList.count + 1000)))
            warnings.append("This is a common password")
            feedback.append("Avoid passwords that appear in public breach lists")
            _ = hit
        }

        // 2. Repeated runs ("aaaa", "abab") and sequences ("abcd", "4321")
        let repeatPenalty = repetitionPenalty(password)
        let sequencePenalty = sequencePenalty(password)
        bits -= repeatPenalty + sequencePenalty
        if repeatPenalty > 0 { warnings.append("Contains repeated characters") }
        if sequencePenalty > 0 { warnings.append("Contains a predictable sequence") }

        // 3. Keyboard walks ("qwerty", "asdfgh", "1qaz2wsx")
        if containsKeyboardWalk(password) {
            bits *= 0.75
            warnings.append("Contains a keyboard pattern")
        }

        // 4. Years / dates
        if password.range(of: #"(19|20)\d{2}"#, options: .regularExpression) != nil {
            bits = min(bits, bits * 0.9)
            warnings.append("Contains a year")
        }

        // 5. Repetition of the same whole string
        if password.count >= 4, password.count % 2 == 0 {
            let half = password.count / 2
            if password.prefix(half) == password.suffix(half) {
                let distinct = Set(password).count
                bits = min(bits, log2(Double(max(distinct, 2))) * Double(half))
                warnings.append("Contains a repeated pattern")
            }
        }

        // 6. Passphrase detection gives an exact figure.
        if let passphraseBits = passphraseEntropy(password) {
            bits = max(min(bits, passphraseBits), passphraseBits * 0.9)
        }

        // 7. Short passwords get an upper bound regardless of alphabet.
        if password.count < 8 {
            bits = min(bits, Double(password.count) * 3.3)
            feedback.append("Use at least 12 characters")
        }

        bits = max(0, bits)
        let score = scoreFor(bits: bits)

        if warnings.isEmpty {
            switch score {
            case .excellent: feedback.append("Excellent — resistant to offline attacks")
            case .strong: feedback.append("Strong for most accounts")
            case .fair: feedback.append("Consider adding another word or character type")
            default: feedback.append("Use a longer password or a passphrase")
            }
        }
        return StrengthResult(bits: bits, score: score, feedback: feedback,
                              warnings: warnings, crackTime: crackTimeDescription(bits: bits))
    }

    // MARK: Entropy

    static func rawEntropyBits(_ password: String) -> Double {
        var alphabet = 0
        let lower = password.contains { $0.isLowercase }
        let upper = password.contains { $0.isUppercase }
        let digits = password.contains { $0.isNumber }
        let symbols = password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        let spaces = password.contains { $0.isWhitespace }
        if lower { alphabet += 26 }
        if upper { alphabet += 26 }
        if digits { alphabet += 10 }
        if symbols { alphabet += 33 }
        if spaces { alphabet += 1 }
        if password.unicodeScalars.contains(where: { $0.value > 127 }) { alphabet += 100 }
        let perChar = log2(Double(max(alphabet, 2)))
        return Double(password.count) * perChar
    }

    static func scoreFor(bits: Double) -> StrengthScore {
        switch bits {
        case ..<28: return .extremelyWeak
        case ..<36: return .weak
        case ..<60: return .fair
        case ..<80: return .strong
        default: return .excellent
        }
    }

    /// Crack time at 10^10 guesses per second (a modern GPU cluster).
    static func crackTimeDescription(bits: Double) -> String {
        let guessesPerSecond = 1e10
        let seconds = pow(2, bits) / (2 * guessesPerSecond) // average case
        if seconds < 1 { return "Instant" }
        if seconds < 60 { return "\(Int(seconds)) seconds" }
        if seconds < 3600 { return "\(Int(seconds / 60)) minutes" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) hours" }
        let days = seconds / 86_400
        if days < 30 { return "\(Int(days)) days" }
        if days < 365 { return "\(Int(days / 30)) months" }
        let years = days / 365
        if years < 1000 { return "\(Int(years)) years" }
        if years < 1_000_000 { return "\(Int(years / 1000))K years" }
        if years < 1e9 { return "\(Int(years / 1_000_000))M years" }
        if years < 1e12 { return "\(Int(years / 1e9))B years" }
        return "Centuries beyond reach"
    }

    // MARK: Pattern penalties (bits removed)

    static func repetitionPenalty(_ password: String) -> Double {
        let chars = Array(password.lowercased())
        guard chars.count >= 3 else { return 0 }
        var penalty: Double = 0
        var run = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1] {
                run += 1
                if run >= 3 { penalty += 1.0 }
            } else {
                run = 1
            }
        }
        // "abab" style
        if chars.count >= 4, chars.count % 2 == 0 {
            let half = chars.count / 2
            if Array(chars[..<half]) == Array(chars[half...]) { penalty += Double(half) * 1.2 }
        }
        return min(penalty, Double(chars.count) * 2)
    }

    static func sequencePenalty(_ password: String) -> Double {
        let lower = Array(password.lowercased())
        guard lower.count >= 3 else { return 0 }
        let ascending = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let descending = Array("zyxwvutsrqponmlkjihgfedcba9876543210")
        var penalty: Double = 0
        for i in 0..<(lower.count - 2) {
            let a = indexIn(ascending, lower[i]), b = indexIn(ascending, lower[i + 1]), c = indexIn(ascending, lower[i + 2])
            if let a, let b, let c, b == a + 1, c == b + 1 { penalty += 1.5 }
            let da = indexIn(descending, lower[i]), db = indexIn(descending, lower[i + 1]), dc = indexIn(descending, lower[i + 2])
            if let da, let db, let dc, db == da + 1, dc == db + 1 { penalty += 1.5 }
        }
        return min(penalty, Double(lower.count))
    }

    static func containsKeyboardWalk(_ password: String) -> Bool {
        let walks = ["qwerty", "qwert", "werty", "asdf", "sdfg", "dfgh", "zxcv", "xcvb",
                     "1qaz", "2wsx", "3edc", "4rfv", "qazwsx", "qweasd", "1234qwer"]
        let lower = password.lowercased()
        return walks.contains { lower.contains($0) }
    }

    static func passphraseEntropy(_ password: String) -> Double? {
        let separators = CharacterSet(charactersIn: "-_. ·")
        let rawWords = password.components(separatedBy: separators)
            .map { $0.lowercased().trimmingCharacters(in: CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "!@#$%^&*"))) }
            .filter { !$0.isEmpty }
        guard rawWords.count >= 3 else { return nil }
        let dictionary = Set(Wordlist.words)
        let allKnown = rawWords.allSatisfy { dictionary.contains($0) }
        guard allKnown else { return nil }
        let bits = Double(rawWords.count) * log2(Double(Wordlist.words.count))
        return bits + Double(password.count) * 0.5 // small bonus for length/format
    }

    private static func indexIn(_ array: [Character], _ character: Character) -> Int? {
        array.firstIndex(of: character)
    }
}

/// Small embedded set of the most common passwords, so a weak master
/// password or generated password is flagged locally without any network call.
public enum CommonPasswordList {
    public static let entries: [String] = """
    password password1 password12 password123 password1234 passw0rd password! p@ssw0rd p@ssword
    123456 1234567 12345678 123456789 1234567890 12345 1234 111111 11111111 000000 00000000
    654321 121212 112233 131313 123123 123321 6543210 987654321 102030 123abc abc123 abc1234
    qwerty qwerty1 qwerty12 qwerty123 qwertyuiop qwertyui asdfgh asdfghjkl zxcvbn zxcvbnm
    letmein letmein1 welcome welcome1 welcome123 admin administrator root toor guest changeme
    iloveyou iloveyou1 monkey dragon master sunshine princess football baseball soccer hockey
    superman batman starwars whatever trustno1 shadow michael jennifer jordan hunter buster
    harley ranger daniel thomas robert matthew joshua andrew charlie banana orange purple silver
    summer winter spring autumn january february march april may june july august september october
    november december secret mypassword yourpassword newpassword default temp temporary test test123
    login logout access pass pass1234 changeme123 me MYPASSWORD Myself trustme nopassword
    1q2w3e4r 1qaz2wsx qwe123 qweasd zaq12wsx 1qazxsw2 !qaz2wsx 1q2w3e 1qaz2wsx3edc
    """.split(separator: " ").map(String.init).filter { !$0.isEmpty }

    private static let set: Set<String> = Set(entries.map { $0.lowercased() })

    public static let count = entries.count

    public static func match(_ password: String) -> String? {
        let lower = password.lowercased()
        if set.contains(lower) { return lower }
        // Strip common leet substitutions.
        let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"]
        let deleet = String(lower.map { leet[$0] ?? $0 })
        if set.contains(deleet) { return deleet }
        // Trailing digits ("password2024")
        let trimmed = lower.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789!"))
        if set.contains(trimmed) && !trimmed.isEmpty { return trimmed }
        return nil
    }
}
