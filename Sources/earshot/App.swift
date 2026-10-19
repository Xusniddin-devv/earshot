import AppKit
import EarshotCore
import EarshotMac
import EarshotVoice
import Foundation

/// The dashboard: tails the event log, tracks sessions, maps them to Terminal tabs.
/// Everything runs on the main thread / main run loop.
final class App {
    let paths = Paths.live
    let log: EventLog
    let store = SessionStore()
    let terminal: TerminalAdapter
    let ownTTY = ttyname(STDIN_FILENO).map { String(cString: $0) }
    var config: Config
    let speaker: Speaker
    let transcriber = Transcriber()
    let recorder = Recorder()
    var hotkey: Hotkey?
    var listenStarted: Date?

    var selected = 0
    /// Selection follows the session, not the row, when the list re-sorts.
    var selectedId: String?
    var focusedTTY: String?
    var titles: [String: String] = [:]
    var playingId: String?
    var listening = false
    var status = ""
    var lastTranscript: String?
    private var inputSource: DispatchSourceRead?
    private var signalSources: [DispatchSourceSignal] = []
    private var timers: [Timer] = []

    init() {
        log = EventLog(url: paths.eventLog)
        config = Config.load(paths.configFile)
        terminal = makeTerminal(config.terminal)
        speaker = Speaker(voice: config.voice, speed: config.speed)
        speaker.onFinish = { [weak self] in
            self?.playingId = nil
            self?.redraw()
        }
    }

    func prepareVoice() {
        status = "loading voice… (first run downloads ~900 MB)"
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.speaker.prepare()
                await MainActor.run { self.status = "voice ready; loading speech recognition…"; self.redraw() }
                try await self.transcriber.prepare()
                await MainActor.run { self.status = "ready — hold \(self.config.hotkeyLabel) to talk"; self.redraw() }
            } catch {
                await MainActor.run { self.status = "voice failed to load: \(error)"; self.redraw() }
            }
        }
    }

    func run() {
        EventLog.trim(url: paths.eventLog, keepLast: 2000)
        for e in log.readNew() { store.apply(e) }
        refreshTabs()
        // Replayed history is not news: nothing starts unread.
        for s in store.sessions { store.markRead(id: s.id) }

        signal(SIGPIPE, SIG_IGN)
        TTY.enter()
        atexit { TTY.leave() }
        watchSignals()
        prepareVoice()
        startHotkey()
        recorder.warmUp()
        watchInput()
        timers.append(.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.pollEvents() })
        timers.append(.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshTabs()
            self?.redraw()
        })
        redraw()
        RunLoop.main.run()
    }

    // MARK: events and tabs

    func pollEvents() {
        let events = log.readNew()
        guard !events.isEmpty else { return }
        for e in events {
            store.apply(e)
            // The session's tty, not the hook's: a background job's hook reports its hidden pty.
            let tty = store.sessions.first { $0.id == e.sessionId }?.tty ?? e.tty
            if e.kind.endsTurn, config.finishSound, tty != focusedTTY { Sounds.finish() }
        }
        markFocusedRead()
        redraw()
    }

    func refreshTabs() {
        // Background jobs report a hidden pty; move them to the tab running their client first.
        let tree = SysctlProcessTree()
        store.setTTYOverrides(SessionRegistry.ttyOverrides(SessionRegistry.load(dir: SessionRegistry.liveDir),
                                                           process: { pid in
            tree.name(of: pid).map { SessionRegistry.Process(name: $0, tty: tree.tty(of: pid).map { "/dev/" + $0 }) }
        }))
        let tabs = terminal.tabs()
        let failed = terminal.failedApps
        if let scan = TabScan.result(tabs: tabs, failedApps: failed, allFailed: terminal.lastError != nil,
                                     claudeTTYs: ClaudeProcesses.live(), ownTTY: ownTTY, oldTitles: titles) {
            store.prune(liveTTYs: scan.live)
            titles = scan.titles
        }
        if !failed.isEmpty {
            status = "\(failed.joined(separator: " and ")) automation blocked — run `earshot doctor`"
        }
        focusedTTY = terminal.focusedTTY()
        markFocusedRead()
    }

    func markFocusedRead() {
        if let f = focusedTTY, let s = store.session(forTTY: f) { store.markRead(id: s.id) }
    }

    var selectedSession: Session? {
        store.sessions.indices.contains(selected) ? store.sessions[selected] : nil
    }

    // MARK: input

    func watchInput() {
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 64)
            let n = read(STDIN_FILENO, &buf, buf.count)
            guard n > 0 else { return }
            for key in TTY.keys(Array(buf[0..<n])) { self?.handle(key) }
        }
        source.resume()
        inputSource = source
    }

    func handle(_ key: Key) {
        switch key {
        case .up, .char("k"):
            select(selected - 1)
        case .down, .char("j"):
            select(selected + 1)
        case .enter:
            if let s = selectedSession, let tty = s.tty {
                if terminal.focus(tty: tty) { store.markRead(id: s.id) } else { status = "could not find that tab" }
            }
        case .char("s"):
            config.mode = config.mode == .whole ? .summary : .whole
            try? config.save(paths.configFile)
            status = "mode: \(config.mode.rawValue)"
        case .char("c"):
            if let t = lastTranscript {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(t, forType: .string)
                status = "copied"
            } else {
                status = "nothing to copy yet"
            }
        case .char("p"):
            play()
        case .char("q"), .quit:
            quit()
        default:
            break
        }
        redraw()
    }

    /// `p`: play the selected session's reply, or stop it if it is already playing.
    func play() {
        guard let s = selectedSession else { return }
        if playingId == s.id {
            stopPlayback()
            return
        }
        stopPlayback()
        guard let reply = s.reply, !reply.isEmpty else {
            status = "no reply yet"
            return
        }
        guard speaker.isReady else {
            status = "voice still loading"
            return
        }
        store.markRead(id: s.id)
        playingId = s.id
        if config.mode == .whole {
            status = "reading \(s.project)"
            speaker.speak(chunks: SpeechText.chunks(from: reply))
            return
        }
        status = "summarizing…"
        let id = s.id
        Task { [weak self] in
            let result: Result<String, Error>
            do { result = .success(try await Summarizer.summarize(reply)) } catch { result = .failure(error) }
            await MainActor.run {
                guard let self, self.playingId == id else { return }
                switch result {
                case .success(let summary):
                    self.status = summary.isEmpty ? "summary came back empty" : "summary of \(s.project)"
                    self.speaker.speak(chunks: SpeechText.chunks(from: summary))
                case .failure(let error):
                    self.playingId = nil
                    self.status = "summary failed: \(error)"
                }
                self.redraw()
            }
        }
    }

    // MARK: push-to-talk

    func startHotkey() {
        Permissions.request()
        let key = Hotkey(machine: config.hotkeyKeycode.map { PushToTalk(keycode: $0) } ?? PushToTalk(key: config.hotkey), onDown: { [weak self] in self?.listenDown() },
                         onUp: { [weak self] in self?.listenUp() },
                         onCancel: { [weak self] in self?.listenCancel() })
        if key.start() {
            hotkey = key
        } else {
            let host = HostApp.name(env: ProcessInfo.processInfo.environment)
            status = "push-to-talk off: allow \(host) in Input Monitoring, then restart (earshot doctor)"
        }
    }

    func listenDown() {
        guard transcriber.isReady else {
            status = "speech recognition still loading"
            redraw()
            return
        }
        do {
            try recorder.start()
        } catch {
            status = "mic failed: \(error.localizedDescription)"
            redraw()
            return
        }
        listening = true
        listenStarted = Date()
        // Only announce once the key has been held alone for a moment: a Shift used for a
        // capital letter is cancelled before this fires, so it never ticks or stops playback.
        DispatchQueue.main.asyncAfter(deadline: .now() + App.minHold) { [weak self] in
            guard let self, self.listening else { return }
            self.stopPlayback()
            Sounds.listenStart()
            self.status = "listening…"
            self.redraw()
        }
    }

    static let minHold = 0.3
    static let sendDelay = 0.4

    /// Another key was pressed while the talk key was held (e.g. Shift+A): drop the recording silently.
    func listenCancel() {
        guard listening else { return }
        listening = false
        _ = recorder.stop()
        status = "ready — hold \(config.hotkeyLabel) to talk"
        redraw()
    }

    func listenUp() {
        guard listening else { return }
        listening = false
        if Date().timeIntervalSince(listenStarted ?? Date()) >= App.minHold { Sounds.listenStop() }
        // Decide the target now, at release, not after transcription.
        let focused = terminal.focusedTTY()
        let samples = recorder.stop()
        let long = Date().timeIntervalSince(listenStarted ?? Date()) >= App.minHold
        guard long, !samples.isEmpty else { return }
        status = "transcribing…"
        redraw()
        // Any tab with claude running counts. Hook history is not enough: a tab attached to a
        // background job reports the job's hidden pty, not the tab's own.
        let known = ClaudeProcesses.live()
        Task { [weak self] in
            guard let self else { return }
            let text = (try? await self.transcriber.transcribe(samples)) ?? ""
            await MainActor.run { self.deliver(text, focused: focused, known: known) }
        }
    }

    func deliver(_ text: String, focused: String?, known: Set<String>) {
        if !text.isEmpty { lastTranscript = text }
        switch route(focusedTTYAtRelease: focused, ownTTY: ownTTY, knownTTYs: known, transcript: text) {
        case .type:
            // Focus may have moved during transcription; only type if the same tab is still in front.
            guard terminal.focusedTTY() == focused else {
                status = "not typed (tab changed): \"\(text)\" — c to copy"
                break
            }
            KeyTyper.type(text)
            status = "typed: \"\(text)\""
            if config.autoSend {
                // Claude Code treats a fast burst of keys as a paste and swallows an Enter inside it,
                // so press Enter only after a pause — and only if the same tab is still in front.
                DispatchQueue.main.asyncAfter(deadline: .now() + App.sendDelay) { [weak self] in
                    guard let self else { return }
                    guard self.terminal.focusedTTY() == focused else {
                        self.status = "typed but not sent (tab changed): \"\(text)\""
                        self.redraw()
                        return
                    }
                    KeyTyper.pressReturn()
                    self.status = "sent: \"\(text)\""
                    self.redraw()
                }
            }
        case .refuse(let reason):
            status = text.isEmpty ? "not typed (\(reason))" : "not typed (\(reason)): \"\(text)\" — c to copy"
        }
        redraw()
    }

    func stopPlayback() {
        speaker.stop()
        playingId = nil
    }

    func quit() -> Never {
        TTY.leave()
        exit(0)
    }

    func watchSignals() {
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGWINCH] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { [weak self] in
                if sig == SIGWINCH { self?.redraw() } else { self?.quit() }
            }
            s.resume()
            signalSources.append(s)
        }
    }

    func select(_ index: Int) {
        selected = Render.reselect(id: nil, fallback: index, in: store.sessions)
        selectedId = selectedSession?.id
    }

    // MARK: drawing

    func redraw() {
        selected = Render.reselect(id: selectedId, fallback: selected, in: store.sessions)
        selectedId = selectedSession?.id
        let size = TTY.size
        let state = ViewState(sessions: store.sessions, titles: titles, selected: selected, focusedTTY: focusedTTY,
                              playingId: playingId, listening: listening, mode: config.mode, status: status,
                              now: Date())
        let lines = Render.lines(state, width: size.cols)
        TTY.draw(lines, highlight: store.sessions.isEmpty ? nil : Render.firstRow + selected)
    }
}

/// `auto` keeps Apple Terminal as before and adds iTerm2 (which only answers while it is running).
func makeTerminal(_ choice: Config.Terminal) -> TerminalAdapter {
    switch choice {
    case .terminal: AppleTerminalAdapter()
    case .iterm: ITermAdapter()
    case .auto: CompositeTerminal([AppleTerminalAdapter(), ITermAdapter()])
    }
}

/// Asks once whether to add the hooks. Returns false if the user declines.
func ensureHooks() -> Bool {
    let settings = try? Data(contentsOf: claudeSettings)
    let status = HookInstaller.status(settings: settings, binary: binaryPath)
    if status == .installed { return true }
    if case .outdated = status {
        print("Earshot's hooks in \(claudeSettings.path) are out of date and need updating.")
    } else {
        print("Earshot needs to add hooks to \(claudeSettings.path) so it can see your Claude sessions.")
    }
    print("A backup is made first; `earshot uninstall-hooks` removes them. Install? [y/n] ", terminator: "")
    guard readLine()?.lowercased().hasPrefix("y") == true else { return false }
    rewriteSettings({ try HookInstaller.install(settings: $0, binary: binaryPath) }, done: "Hooks installed.")
    return true
}
