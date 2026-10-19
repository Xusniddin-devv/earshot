# Earshot — design

Date: 2026-10-19
Status: draft, awaiting owner approval (builder check done)

## Intent

The owner runs many Claude Code sessions at once, each in its own tab of Apple
Terminal. Switching between tabs to find out which session finished, which is
waiting, and what each one said is the pain. Earshot is a terminal tool: a
live dashboard (`earshot`) the owner runs in its own small Terminal window
next to the main one. It:

1. lists every Claude Code session running in Terminal tabs, with live status;
2. lets the owner speak into the Terminal tab they are on (and only that tab);
3. reads a session's reply aloud, in a natural (non-robotic) voice, when the
   owner asks for it.

Why build instead of using an existing tool: the owner checked the field
(Paseo, Vibe Island, Claude Island, AgentManager, voice-hooks projects). None
combine all three. The closest (Paseo) runs Claude through its own app; the
owner does not want their Claude account used inside someone else's app.
Earshot never touches Claude credentials. It only observes the owner's own
Claude Code CLI through Claude Code's official hooks and types text into the
owner's own Terminal.

v1 is built for the owner's own use. Open-sourcing may come later; v1 does
not need to be packaged for strangers.

## Goals

- One dashboard that shows all Claude Code sessions running in Apple Terminal tabs.
- Push-to-talk voice input that lands in the currently focused Terminal tab only.
- Natural-sounding voice output of a session's reply, on demand.
- Fully local: speech-to-text and text-to-speech run on the Mac. No third-party
  servers, no accounts, no telemetry.
- English only, for both voice input and voice output.

## Non-goals (v1)

- Replacing Terminal or hosting terminals inside Earshot.
- Supporting iTerm2, Ghostty, Warp, VS Code terminal, etc. (v1 is Apple Terminal
  only; the design must leave room to add them later — see "Terminal adapter").
- Windows / Linux.
- Mobile/remote control.
- Wake word / always-listening mode.
- Approving permission prompts from the panel.
- Selling it.
- A GUI app (no SwiftUI window, no menu bar icon, no .app bundle).
- Packaging for other people in v1: no Homebrew formula or release pipeline.
  Owner builds and runs it locally. No Apple Developer account needed.
- Languages other than English.
- Claude sessions inside tmux/screen or over ssh (owner does not use tmux).
  Such sessions may show as "not linked to a tab" or not at all; document it.

## Anti-goals (would be a failure even if it "works")

- Anything plays or switches on its own. No auto-play of replies, no automatic
  tab switching. The owner explicitly said audio must not start automatically.
- Robotic voice (e.g. macOS `say` as the main voice).
- Voice text going into the wrong tab.
- Sending spoken text to Claude without the owner pressing Enter (by default).
- Earshot reading, storing, or proxying Claude credentials, or sending
  transcripts / audio anywhere off the machine.
- Heavy, slow app (Electron-sized) for what is a small utility.

## Decisions made with the owner

- Terminal tool, not a Mac app (owner chose this after the Mac-app draft).
  Dashboard runs in its own Terminal window beside the main one. Selecting a
  row and pressing Enter brings Terminal's main window to that tab.
- Voice input goes to the focused Terminal tab, never others.
- Voice output must sound natural, not robotic.
- Replies never auto-play. When a session finishes, the panel shows it; audio
  starts only when the owner presses play.
- By default, play reads the **whole reply**. A setting switches to
  **summary only**.
- 2026-10-20 owner changes: spoken text is sent automatically (autoSend default
  true, "no confirm after speaking"); Shift (held alone) as talk key because the
  owner's PC keyboard has no Right Option and reports Right Shift as Left Shift.
- English only.
- v1 is for the owner's own use ("just build for our own"). Open source later,
  maybe.
- Owner agreed (“sounds good”) to: Apple Terminal first, Swift,
  hooks installed with permission on first run, hold Right Option to talk,
  spoken text typed into the prompt without pressing Enter (auto-send is a
  setting).

## Calls made by Claude (owner can override)

- Name "Earshot", repo `~/dev/earshot`.
- Swift command-line tool `earshot`, full-screen text UI (TUI) in the window
  it runs in. Keys: up/down select, Enter jump to tab, `p` play/stop, `s`
  toggle whole/summary, `c` copy last transcript, `?` help, `q` quit.
- Process model: v1 runs everything (hotkey, mic, STT, TTS, event watching,
  dashboard) in the one `earshot` process. Because it runs inside Terminal,
  macOS attributes Microphone, Accessibility/Input Monitoring and Automation
  to Terminal.app, so grants persist across rebuilds with no code signing.
  The owner accepted the trade-off that any program run in Terminal can then
  use those grants. Closing the dashboard window stops Earshot; that is fine
  for v1. A detached background service is a later option: only if the
  builder confirms a detached child keeps Terminal as its responsible process
  for permissions.
- Speech-to-text and TTS via local models. Candidate: FluidAudio
  (github.com/FluidInference/FluidAudio) — Parakeet for STT, Kokoro for TTS,
  CoreML on the Neural Engine. Apple's on-device speech recognition
  (SpeechAnalyzer, macOS 26) is an acceptable STT alternative. Builder picks
  after a quick quality/latency check; TTS must be Kokoro-class or better.
- Models download on first run, not bundled in the install.
- License is decided only if/when it is published. GPL-licensed pieces (e.g.
  espeak-ng used by some Kokoro setups) are fine for v1; do not let license
  concerns weaken the voice.
- Settings live in `~/.config/earshot/config.json` (or similar); common
  toggles (whole/summary, finish sound, auto-send) are also keys in the
  dashboard.
- `make install` (or a script) builds release and copies the binary onto
  PATH (e.g. `~/.local/bin/earshot`).
- "Reply" = Claude's final answer text for the turn: the assistant text that
  comes after the last tool call of that turn (all text blocks after it,
  joined). Intermediate narration ("Let me check X…") is not read.
- When reading a whole reply, code blocks are not read character by character:
  speak a short marker instead ("code block, 12 lines"). Long file paths are
  shortened to the file name. Markdown symbols are stripped.
- Summary mode uses the owner's own `claude` CLI in headless mode
  (`claude -p`, cheapest model) run locally by Earshot. Earshot never sees the
  credentials; it just invokes the CLI. Summaries are generated only when the
  owner presses play in summary mode (no background usage).
- When a session finishes in a tab the owner is not looking at: its row
  highlights and a short, soft sound plays (can be turned off). Nothing else.
- Default hotkey: hold Right Option to talk, release to stop. Configurable.

## How it works

### Session discovery: Claude Code hooks

On first run Earshot asks permission, then adds hook entries to
`~/.claude/settings.json` (merging, never clobbering existing hooks; a
backup is written first; an "uninstall hooks" action removes exactly what it
added). Hooks used, at minimum:

- `SessionStart` — session appeared.
- `UserPromptSubmit` — session is working.
- `Stop` — session finished a reply.
- `Notification` — session waiting on the user (permission prompt, idle).
- `SessionEnd` — session gone.

Each hook runs a tiny script (shipped with Earshot) that appends one JSON
line to an event file (e.g. `~/Library/Application Support/Earshot/events.jsonl`)
or sends it over a local Unix socket. Each event carries: event name,
`session_id`, `cwd`, `transcript_path`, timestamp, and the **TTY** of the
Claude process (found from the hook's parent process). The hook must be fast
(well under 100 ms) and must never block or break Claude Code if Earshot is
not running.

### Mapping sessions to Terminal tabs

Apple Terminal exposes each tab's `tty` via AppleScript. Earshot matches the
session's TTY to a Terminal window and tab. This gives exact mapping without
guessing from screen text. Requires the Automation permission (Terminal controlling
Terminal).

### The dashboard

One row per live session:
- project name (last folder of `cwd`), plus the tab title if useful;
- status: working / finished (unread) / waiting on you / idle;
- play indicator (reply available / playing);
- time since last change.

Enter on a row: activate Terminal, select that window and tab. Sessions
disappear when they end or their tab closes. The row for the focused tab is
marked. The dashboard's own tab is never listed and never receives voice text.
Status updates live (no manual refresh).

### Voice input

1. Owner holds the hotkey. Earshot records the mic and the dashboard shows
   "listening". A short start/stop tick sound confirms, since the dashboard
   may be out of sight.
2. On release, local STT transcribes the audio.
3. Earshot checks which Terminal tab is frontmost **at the moment of release**,
   and types the text into that tab. If Terminal is not frontmost, or the
   focused tab is not a known Claude session, nothing is typed and the dashboard
   shows the transcript; `c` copies it. Never guess a tab.
4. Default: text is typed without Enter. Setting: auto-send.

Typing method is the builder's choice (e.g. System Events keystrokes or
pasteboard paste into the focused tab). It must not leave the owner's clipboard
changed, or must restore it. Requires Microphone and Accessibility (and
Input Monitoring if the hotkey method needs it), granted to Terminal; first
run explains each one in plain words.

### Voice output

- Source text: the session's final answer for the turn (see "Reply" above),
  read from `transcript_path` (JSONL) after the `Stop` event, or from the
  Stop hook's input if current Claude Code provides the last message there.
- Whole mode: clean up the text (strip markdown, replace code blocks with
  markers, shorten paths), then speak with local TTS. Stream sentence by
  sentence so playback starts quickly.
- Summary mode: run `claude -p` with a short "summarize this reply in 2–3
  spoken sentences" prompt on that text, then speak the result.
- Only one reply plays at a time. Pressing play on another row stops the
  current one. Pressing the hotkey to talk pauses playback.
- Settings: voice choice, speed, mode (whole/summary), finish sound on/off,
  auto-send on/off, hotkey.

### Terminal adapter

All Terminal-specific logic (find tab by TTY, focus tab, get focused tab, type
text) lives behind one small interface, so iTerm2/Ghostty adapters can be added
later by contributors. Only the Apple Terminal adapter ships in v1.

## Constraints

- macOS 26 (owner is on 26.5.1), Apple Silicon. Xcode 26.6, Swift 6.3 available.
- Claude Code 2.1.303 on owner's machine. Verify hook input fields against the
  current Claude Code hooks docs, not memory.
- Must keep working, silently, if Earshot is quit: hooks must not error or slow
  Claude Code.
- Fully offline after model download.
- English-only models are fine (e.g. Parakeet v2 English, Kokoro English voices).

## Packaging (v1)

- Local build only, for the owner's Mac. README covers build, permissions,
  uninstall (restores `~/.claude/settings.json` hooks).
- Keep the code clean enough to open-source later, but no release pipeline now.

## Left to the builder

- STT engine choice (FluidAudio Parakeet vs Apple SpeechAnalyzer), after testing.
- Event transport (append-only file vs Unix socket).
- Exact text-typing method into Terminal.
- Dashboard look and TUI library (plain and readable; no ASCII-art clutter).
- Global hotkey method (CGEventTap vs other) that works from a CLI process.
- Project structure, tests, and how to fake Claude Code events for testing.

## Open questions

None. Builder-check questions answered by owner (English only; own use, no
Developer ID) or settled as calls above (reply definition, tmux, license).
Switched from Mac app to terminal tool at owner's request.
