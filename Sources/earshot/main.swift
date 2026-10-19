import CoreGraphics
import Foundation
import EarshotCore
import EarshotMac

let args = Array(CommandLine.arguments.dropFirst())
let claudeSettings = Paths.live.claudeSettings
let binaryPath = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
    .resolvingSymlinksInPath().path

/// Backs up and rewrites `~/.claude/settings.json`. Exits non-zero on failure.
func rewriteSettings(_ change: (Data?) throws -> Data, done: String) {
    let current = try? Data(contentsOf: claudeSettings)
    do {
        let updated = try change(current)
        if let current {
            let backup = claudeSettings.path + HookInstaller.backupSuffix(for: Date())
            try current.write(to: URL(fileURLWithPath: backup))
        }
        try FileManager.default.createDirectory(at: claudeSettings.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try HookInstaller.writeSettings(updated, to: claudeSettings)
        print(done)
    } catch {
        FileHandle.standardError.write(Data("earshot: could not update \(claudeSettings.path): \(error)\n".utf8))
        exit(1)
    }
}

switch args.first {
case "hook":
    let input = FileHandle.standardInput.readDataToEndOfFile()
    runHook(stdin: input, env: ProcessInfo.processInfo.environment, ppid: getppid(),
            tree: SysctlProcessTree(), log: EventLog(url: Paths.live.eventLog), now: Date())
    exit(0)
case "install-hooks":
    rewriteSettings({ try HookInstaller.install(settings: $0, binary: binaryPath) },
                    done: "Added Earshot hooks (\(HookInstaller.events.joined(separator: ", "))) to \(claudeSettings.path)")
case "uninstall-hooks":
    rewriteSettings({ try HookInstaller.uninstall(settings: $0 ?? Data()) },
                    done: "Removed Earshot hooks from \(claudeSettings.path)")
case "uninstall":
    do {
        for line in try Uninstaller.run(home: FileManager.default.homeDirectoryForCurrentUser) { print(line) }
        print("To remove the binary: make uninstall (from the repo) or rm \(binaryPath)")
    } catch {
        FileHandle.standardError.write(Data("earshot: uninstall failed: \(error)\n".utf8))
        exit(1)
    }
case "doctor":
    runDoctor()
case "debug-state":
    runDebugState()
case "set-key":
    runSetKey()
case "selftest":
    Task {
        await runSelfTest()
        exit(0)
    }
    RunLoop.main.run()
case nil:
    guard ensureHooks() else {
        print("Earshot can't see Claude sessions without hooks. Exiting.")
        exit(1)
    }
    App().run()
default:
    print("usage: earshot [set-key | doctor | selftest | install-hooks | uninstall-hooks | uninstall]")
    exit(2)
}
