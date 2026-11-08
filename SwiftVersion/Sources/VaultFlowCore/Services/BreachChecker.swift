// BreachChecker.swift
// VaultFlow · Have I Been Pwned range queries (k-anonymity)
//
// Only the first 5 hex characters of the password's SHA-1 leave the device
// (https://api.pwnedpasswords.com/range/XXXXX). The server returns every suffix
// matching that prefix and we compare locally — the full password is never
// sent, and the request path alone can't identify it.
//
// Results are cached in memory for the session only.

import Foundation

public actor BreachChecker {
    public static let shared = BreachChecker()

    public enum Result: Equatable, Sendable {
        case found(count: Int)
        case clean
        case unavailable(String)
        case skipped
    }

    private var cache: [String: Result] = [:]
    private var inFlight: [String: Bool] = [:]
    private let session: URLSession
    private var lastRequest = Date.distantPast
    private let minInterval: TimeInterval = 1.6   // be a good citizen
    public private(set) var isEnabled = true

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpAdditionalHeaders = ["User-Agent": "VaultFlow-macOS/1.0"]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cache.removeAll() }
    }

    public func check(password: String) async -> Result {
        guard isEnabled, !password.isEmpty else { return .skipped }
        let hash = Hashes.sha1Hex(Data(password.utf8)).uppercased()
        if let cached = cache[hash] { return cached }
        if inFlight[hash] == true { return .skipped }
        inFlight[hash] = true
        defer { inFlight[hash] = nil }

        // Rate limiting.
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000))
        }
        lastRequest = Date()

        let prefix = String(hash.prefix(5))
        let suffix = String(hash.dropFirst(5))
        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else {
            return .unavailable("Invalid URL")
        }
        do {
            var request = URLRequest(url: url)
            request.addValue("true", forHTTPHeaderField: "Add-Padding")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .unavailable("Service returned an error")
            }
            let body = String(decoding: data, as: UTF8.self)
            for line in body.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
                let parts = line.split(separator: ":")
                guard parts.count == 2, parts[0].uppercased() == suffix else { continue }
                let count = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                let result = count > 0 ? Result.found(count: count) : .clean
                cache[hash] = result
                return result
            }
            cache[hash] = .clean
            return .clean
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    public func cachedResult(for password: String) -> Result? {
        cache[Hashes.sha1Hex(Data(password.utf8)).uppercased()]
    }

    public func reset() { cache.removeAll() }
}
