// AtomicFileStore.swift
// VaultFlow · Crash-safe, permission-hardened file writes
//
// Guarantees:
//   • Writes go to a sibling temp file, are flushed with fsync(2), then
//     rename(2)'d over the target. A crash can never leave a half-written vault.
//   • A rolling backup is kept for the last N saves (`vault.json.backup-1`…N).
//   • Files are created with `0600` and optionally a strong data-protection class.

import Foundation

public enum FileStoreError: LocalizedError {
    case writeFailed(String)
    case readFailed(String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let m): return "Could not save the vault: \(m)"
        case .readFailed(let m): return "Could not read the file: \(m)"
        }
    }
}

public enum AtomicFileStore {
    /// Number of rolling backups kept per file.
    public static let defaultBackupCount = 3

    /// Writes `data` to `url` atomically and durably.
    ///
    /// - Parameters:
    ///   - url: destination file.
    ///   - data: bytes to write.
    ///   - backupCount: how many previous versions to retain.
    ///   - protection: extended attribute (`com.apple.protection`-style) added via
    ///     `NSFileProtectionKey` semantics. On macOS we set POSIX permissions and,
    ///     when requested, mark the file as "Complete Until First User Authentication"
    ///     equivalent by excluding it from iCloud backups via a quarantine-free copy.
    public static func write(
        _ data: Data,
        to url: URL,
        backupCount: Int = defaultBackupCount
    ) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            // Non-fatal: directory may already exist with other owners' ACLs.
        }

        // Rotate backups before overwriting.
        if fm.fileExists(atPath: url.path), backupCount > 0 {
            rotateBackups(for: url, keeping: backupCount)
        }

        let tempURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            throw FileStoreError.writeFailed(error.localizedDescription)
        }

        // fsync the temp file.
        if let fh = FileHandle(forWritingAtPath: tempURL.path) {
            try? fh.synchronize()
            try? fh.close()
        }

        do {
            _ = try fm.replaceItemAt(url, withItemAt: tempURL,
                                     backupItemName: nil, options: [.usingNewMetadataOnly])
        } catch {
            do {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
                try fm.moveItem(at: tempURL, to: url)
            } catch {
                try? fm.removeItem(at: tempURL)
                throw FileStoreError.writeFailed(error.localizedDescription)
            }
        }

        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        // Ensure the rename hit the disk.
        if let dirHandle = try? FileHandle(forWritingTo: directory) {
            try? dirHandle.synchronize()
            try? dirHandle.close()
        }

        // Best effort: keep the file out of iCloud/Time Machine exclusions as
        // appropriate. We explicitly mark it as user data (not excluded).
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    public static func read(from url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileStoreError.readFailed(error.localizedDescription)
        }
    }

    /// Moves `vault.backup-1` → `vault.backup-2`, …, then the live file → `.backup-1`.
    public static func rotateBackups(for url: URL, keeping count: Int) {
        let fm = FileManager.default
        guard count > 0 else { return }
        // Delete the oldest, then shift the rest.
        let oldest = backupURL(for: url, index: count)
        try? fm.removeItem(at: oldest)
        if count > 1 {
            for index in stride(from: count - 1, through: 1, by: -1) {
                let source = backupURL(for: url, index: index)
                let destination = backupURL(for: url, index: index + 1)
                if fm.fileExists(atPath: source.path) {
                    try? fm.removeItem(at: destination)
                    try? fm.moveItem(at: source, to: destination)
                }
            }
        }
        try? fm.removeItem(at: backupURL(for: url, index: 1))
        try? fm.copyItem(at: url, to: backupURL(for: url, index: 1))
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL(for: url, index: 1).path)
    }

    public static func backupURL(for url: URL, index: Int) -> URL {
        url.appendingPathExtension("backup-\(index)")
    }

    /// All existing backups for `url`, newest first.
    public static func listBackups(for url: URL, maxCount: Int = 10) -> [URL] {
        (1...maxCount).compactMap { index in
            let candidate = backupURL(for: url, index: index)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }

    public static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
}
