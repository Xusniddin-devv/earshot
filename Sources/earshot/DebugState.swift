import EarshotCore
import EarshotMac
import Foundation

/// `earshot debug-state`: one refresh cycle, printed stage by stage, for bug reports.
func runDebugState() {
    let config = Config.load(Paths.live.configFile)
    let store = SessionStore()
    for e in EventLog(url: Paths.live.eventLog).readNew() { store.apply(e) }
    func dump(_ stage: String) {
        print("== \(stage): \(store.sessions.count)")
        for s in store.sessions { print("   \(s.id.prefix(8)) \(s.status) tty=\(s.tty ?? "-") hook=\(s.hookTTY ?? "-") \(s.cwd)") }
    }
    dump("after replay")
    let tree = SysctlProcessTree()
    let overrides = SessionRegistry.ttyOverrides(SessionRegistry.load(dir: SessionRegistry.liveDir), process: { pid in
        tree.name(of: pid).map { SessionRegistry.Process(name: $0, tty: tree.tty(of: pid).map { "/dev/" + $0 }) }
    })
    print("== overrides: \(overrides.map { "\($0.key.prefix(8))→\($0.value)" }.sorted())")
    store.setTTYOverrides(overrides)
    dump("after overrides")
    store.seed(SessionRegistry.visible(SessionRegistry.load(dir: SessionRegistry.liveDir), process: { pid in
        tree.name(of: pid).map { SessionRegistry.Process(name: $0, tty: tree.tty(of: pid).map { "/dev/" + $0 }) }
    }))
    dump("after seed")
    let terminal = makeTerminal(config.terminal)
    let tabs = terminal.tabs()
    print("== tabs: \(tabs.map(\.tty).sorted())  failed=\(terminal.failedApps) error=\(terminal.lastError ?? "-")")
    let claude = ClaudeProcesses.live()
    print("== claude ttys: \(claude.sorted())")
    let scan = TabScan.result(tabs: tabs, failedApps: terminal.failedApps, allFailed: terminal.lastError != nil,
                              claudeTTYs: claude, ownTTY: nil, oldTitles: [:])
    print("== live: \(scan.map { $0.live.sorted() }?.description ?? "nil (no prune)")")
    if let scan { store.prune(liveTTYs: scan.live) }
    dump("after prune")
}
