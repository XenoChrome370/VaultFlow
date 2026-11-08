// PasswordGenerator.swift
// VaultFlow · Password generation engine
//
// Three modes:
//   • Characters  – configurable alphabet, optional "no ambiguous characters",
//                   guaranteed inclusion of every selected character class
//                   (so a policy like "must contain a symbol" is actually met).
//   • Passphrase  – BIP-39 English wordlist, CSPRNG-chosen words, optional
//                   capitalisation / separators / digits.
//   • PIN         – digits only.
//
// All randomness flows through `SecureRandom` (SecRandomCopyBytes).

import Foundation

public enum PasswordCharacterSet: String, CaseIterable, Codable, Sendable, Identifiable {
    case uppercase
    case lowercase
    case digits
    case symbols
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .digits: return "Digits"
        case .symbols: return "Symbols"
        case .custom: return "Custom"
        }
    }

    public var sample: String {
        switch self {
        case .uppercase: return "A–Z"
        case .lowercase: return "a–z"
        case .digits: return "0–9"
        case .symbols: return "!@#$…"
        case .custom: return "Your own set"
        }
    }

    public static let allSymbols = "!@#$%^&*()_+-=[]{}|;:,.<>?"

    /// Characters that are easy to confuse — removed by "avoid ambiguous".
    public static let ambiguousCharacters = Set("O0oIl1|`'\";:,./\\-_")

    /// The raw alphabet for this class (before ambiguity filtering).
    public var baseAlphabet: String {
        switch self {
        case .uppercase: return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        case .lowercase: return "abcdefghijklmnopqrstuvwxyz"
        case .digits: return "0123456789"
        case .symbols: return PasswordCharacterSet.allSymbols
        case .custom: return ""
        }
    }

    public func alphabet(avoidAmbiguous: Bool, custom: String = "") -> String {
        let base = self == .custom ? custom : baseAlphabet
        guard avoidAmbiguous else { return base }
        return String(base.filter { !PasswordCharacterSet.ambiguousCharacters.contains($0) })
    }
}

public enum GenerationMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case characters
    case passphrase
    case pin

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .characters: return "Characters"
        case .passphrase: return "Passphrase"
        case .pin: return "PIN"
        }
    }

    public var icon: String {
        switch self {
        case .characters: return "textformat.abc"
        case .passphrase: return "text.line.first.and.arrowtriangle.forward"
        case .pin: return "number"
        }
    }
}

public struct GeneratorOptions: Codable, Equatable, Sendable {
    public var mode: GenerationMode
    public var characterSets: Set<PasswordCharacterSet>
    public var customCharacters: String
    public var length: Int
    public var avoidAmbiguous: Bool
    public var requireEveryClass: Bool

    public var wordCount: Int
    public var separator: String
    public var capitalizeWords: Bool
    public var includeDigitInPassphrase: Bool
    public var includeSymbolInPassphrase: Bool

    public var pinLength: Int

    public init(
        mode: GenerationMode = .characters,
        characterSets: Set<PasswordCharacterSet> = [.uppercase, .lowercase, .digits, .symbols],
        customCharacters: String = "",
        length: Int = 20,
        avoidAmbiguous: Bool = false,
        requireEveryClass: Bool = true,
        wordCount: Int = 4,
        separator: String = "-",
        capitalizeWords: Bool = true,
        includeDigitInPassphrase: Bool = true,
        includeSymbolInPassphrase: Bool = false,
        pinLength: Int = 6
    ) {
        self.mode = mode
        self.characterSets = characterSets
        self.customCharacters = customCharacters
        self.length = length
        self.avoidAmbiguous = avoidAmbiguous
        self.requireEveryClass = requireEveryClass
        self.wordCount = wordCount
        self.separator = separator
        self.capitalizeWords = capitalizeWords
        self.includeDigitInPassphrase = includeDigitInPassphrase
        self.includeSymbolInPassphrase = includeSymbolInPassphrase
        self.pinLength = pinLength
    }

    public static let `default` = GeneratorOptions()

    public var effectiveLength: Int {
        switch mode {
        case .characters: return length
        case .passphrase: return wordCount
        case .pin: return pinLength
        }
    }

    /// Separators are stored as their literal value ("-", " ", "_", "." or "").
    public var activeSeparator: String { separator }

    /// Human-readable label for a separator value (also accepts legacy names).
    public static func separatorLabel(for value: String) -> String {
        switch value {
        case "": return "None"
        case "-": return "Hyphen"
        case " ": return "Space"
        case "_": return "Underscore"
        case ".": return "Dot"
        case "·": return "Middle Dot"
        default: return value
        }
    }
}

public enum GeneratorError: LocalizedError {
    case noCharacterSetsSelected
    case noCharactersAvailable
    case lengthTooShortForClassRequirement

    public var errorDescription: String? {
        switch self {
        case .noCharacterSetsSelected: return "Select at least one character type."
        case .noCharactersAvailable: return "The selected character set is empty."
        case .lengthTooShortForClassRequirement:
            return "The password is too short to include every selected character type."
        }
    }
}

public enum PasswordGenerator {

    public static func generate(options: GeneratorOptions) throws -> String {
        switch options.mode {
        case .characters: return try generateCharacters(options: options)
        case .passphrase: return generatePassphrase(options: options)
        case .pin: return generatePIN(length: options.pinLength)
        }
    }

    // MARK: Characters

    public static func generateCharacters(options: GeneratorOptions) throws -> String {
        guard !options.characterSets.isEmpty else { throw GeneratorError.noCharacterSetsSelected }

        let alphabets: [String] = PasswordCharacterSet.allCases
            .filter { options.characterSets.contains($0) }
            .map { $0.alphabet(avoidAmbiguous: options.avoidAmbiguous, custom: options.customCharacters) }
            .filter { !$0.isEmpty }

        guard !alphabets.isEmpty else { throw GeneratorError.noCharactersAvailable }

        let length = max(1, min(128, options.length))
        // The pool is the union of all selected alphabets; drawing from a
        // uniform pool keeps every position independent of class weights.
        var seen = Set<Character>()
        var pool = ""
        for alphabet in alphabets {
            for character in alphabet where seen.insert(character).inserted {
                pool.append(character)
            }
        }
        guard !pool.isEmpty else { throw GeneratorError.noCharactersAvailable }

        var characters: [Character] = []
        if options.requireEveryClass {
            guard length >= alphabets.count else { throw GeneratorError.lengthTooShortForClassRequirement }
            for alphabet in alphabets {
                characters.append(pick(from: alphabet))
            }
        }
        while characters.count < length {
            characters.append(pick(from: pool))
        }

        // Cryptographic Fisher–Yates shuffle so guaranteed characters aren't
        // always at the front.
        shuffle(&characters)
        return String(characters)
    }

    // MARK: Passphrase

    public static func generatePassphrase(options: GeneratorOptions) -> String {
        let count = max(3, min(12, options.wordCount))
        var words: [String] = []
        for _ in 0..<count {
            var word = Wordlist.words[SecureRandom.int(Wordlist.words.count)]
            if options.capitalizeWords {
                word = word.prefix(1).uppercased() + word.dropFirst()
            }
            if options.includeDigitInPassphrase && SecureRandom.int(2) == 0 {
                word += String(SecureRandom.int(10))
            }
            if options.includeSymbolInPassphrase && SecureRandom.int(2) == 0 {
                let symbols = Array("!@#$%^&*")
                word += String(symbols[SecureRandom.int(symbols.count)])
            }
            words.append(word)
        }
        return words.joined(separator: options.activeSeparator)
    }

    // MARK: PIN

    public static func generatePIN(length: Int) -> String {
        let digits = Array("0123456789")
        return String((0..<max(4, min(16, length))).map { _ in digits[SecureRandom.int(digits.count)] })
    }

    // MARK: Character class detection (used by strength scoring)

    public static func containsUppercase(_ s: String) -> Bool { s.contains { $0.isUppercase } }
    public static func containsLowercase(_ s: String) -> Bool { s.contains { $0.isLowercase } }
    public static func containsDigit(_ s: String) -> Bool { s.contains { $0.isNumber } }
    public static func containsSymbol(_ s: String) -> Bool {
        s.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
    }

    // MARK: Helpers

    private static func pick(from alphabet: String) -> Character {
        let chars = Array(alphabet)
        return chars[SecureRandom.int(chars.count)]
    }

    public static func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            let j = SecureRandom.int(i + 1)
            if i != j { array.swapAt(i, j) }
        }
    }
}
