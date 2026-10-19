import Foundation

/// `earshot uninstall`: removes Earshot's hooks (backing up settings first) and Earshot's own files.
/// The model caches are shared with other FluidAudio apps, so they are only pointed at, never deleted.
public enum Uninstaller {
    /// Runs against `home` (a temp dir in tests). Returns what was done, one line each.
    public static func run(home: URL, now: Date = Date(), fm: FileManager = .default) throws -> [String] {
        let paths = Paths(home: home)
        var lines: [String] = []

        let settings = paths.claudeSettings
        if let current = try? Data(contentsOf: settings), HookInstaller.hasOurs(settings: current) {
            let updated = try HookInstaller.uninstall(settings: current)
            let backup = settings.path + HookInstaller.backupSuffix(for: now)
            try current.write(to: URL(fileURLWithPath: backup))
            try HookInstaller.writeSettings(updated, to: settings)
            lines.append("Removed Earshot hooks from \(settings.path) (backup: \(backup))")
        } else {
            lines.append("No Earshot hooks in \(settings.path)")
        }

        for dir in [paths.supportDir, paths.configDir] where fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
            lines.append("Deleted \(dir.path)")
        }

        let caches = paths.modelCaches.filter { fm.fileExists(atPath: $0.path) }
        if !caches.isEmpty {
            lines.append("Kept the speech models (other FluidAudio apps share them):")
            for dir in caches { lines.append("  \(dir.path)") }
            lines.append("To delete them anyway: rm -rf " + caches.map { "'\($0.path)'" }.joined(separator: " "))
        }
        return lines
    }
}
