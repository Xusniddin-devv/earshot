# Earshot

Talk to your Claude Code sessions and hear them back, without leaving the keyboard
and without sending your voice anywhere.

Earshot is a small terminal dashboard for people who run several Claude Code
sessions at once, each in its own terminal tab. It shows every session's live
status, lets you hold a key and speak into the tab you are on, and reads a
session's last reply aloud when you ask. Speech recognition and the voice run
entirely on your Mac.

```
Earshot  ·  3 sessions  ·  mode: whole

> * webapp           finished         2m  Fix login bug
    store            waiting on you   10s  Booking flow
  @ crawl            working           1m  Scraper retries

↑↓ select  enter jump  p play  s mode  c copy  q quit
ready — hold Right Option to talk
```

## Why

- **Many sessions, one glance.** See which session finished, which is working
  and which is blocked on you (a permission prompt or a question), across all
  tabs. Enter jumps to that tab.
- **Talk instead of type.** Hold a key, speak, let go: the words land in the
  Claude prompt of the tab in front and are sent.
- **Listen instead of read.** Press `p` to hear a reply, or `s` first for a
  three-sentence summary.
- **Local.** Claude Code's built-in `/voice` sends your audio to Anthropic for
  transcription and needs a claude.ai login. Earshot transcribes on the Neural
  Engine with [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) and
  speaks with [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M), via
  [FluidAudio](https://github.com/FluidInference/FluidAudio).

## Privacy and safety

- Audio and transcripts never leave the Mac. The only network use is the
  one-time model download: Parakeet (~450 MB on disk, in
  `~/Library/Application Support/FluidAudio/Models`) and Kokoro (~420 MB, in
  `~/.cache/fluidaudio`).
- Earshot never reads or stores Claude credentials. It sees sessions through
  Claude Code's own hooks. Summary mode runs your own `claude -p --model haiku`
  (it counts toward your normal Claude usage); whole-reply mode uses no model.
- It types only into the tab that is in front when you release the key, only if
  that tab is running `claude`, and checks again just before pressing Enter.
  Never into the dashboard, never into another tab. It types your words as
  keystrokes; the clipboard is touched only when you press `c` to copy the last
  transcript.
- Nothing plays or switches tabs on its own. The only automatic output is a soft
  sound when a session finishes (`"finishSound": false` turns it off).

## Install

Requires macOS 15+ on Apple Silicon and Claude Code.

```sh
brew install Xusniddin-devv/tap/earshot
earshot          # first run offers to add the hooks, then opens the dashboard
```

Or from source (needs Xcode 26 / Swift 6.2+):

```sh
git clone https://github.com/Xusniddin-devv/earshot && cd earshot
make install     # builds and copies the binary to ~/.local/bin/earshot
```

Run `earshot` in its own small terminal window next to your main one and keep
it open; closing it stops Earshot. The first start downloads the speech models.

### Permissions

macOS grants these to the terminal app you run `earshot` in (Terminal, or
iTerm2):

| Permission | Why | Where |
|---|---|---|
| Automation | list tabs, jump to a tab | prompted on first run |
| Accessibility | type your words into a tab | Privacy & Security › Accessibility |
| Input Monitoring | notice the talk key | Privacy & Security › Input Monitoring |
| Microphone | hear you | prompted on first run |

Because they belong to the terminal app, other programs you run in it can use
them too. That is the trade-off for not needing a signed app bundle.
`earshot doctor` shows what is missing.

## Use

| Key | Does |
|---|---|
| ↑ ↓ (or k j) | select a session |
| Enter | bring that session's tab to the front |
| p | read the selected session's last reply aloud; again to stop |
| s | switch between whole reply and short summary |
| c | copy the last thing you said (when it could not be typed) |
| q | quit |

**Talking.** Hold the talk key (default **Right Option**), wait for the tick,
speak, release. If your keyboard has no Right Option, run `earshot set-key` and
press the key you want. Shift and Ctrl work too: they count only when held on
their own, so typing capitals or shortcuts never records. If the tab in front
isn't a Claude session, nothing is typed and the text waits for `c`.

**Rows.** `>` selected, `*` unread reply, `@` the tab you are in. Status is one
of `working`, `waiting on you`, `finished`, `error` or `idle`. Sessions running
as Claude Code background jobs are shown under the tab they are attached to.

## Settings

`~/.config/earshot/config.json` (missing keys use defaults; restart `earshot`
after editing):

```json
{
  "mode": "whole",
  "voice": "af_heart",
  "speed": 1.0,
  "finishSound": true,
  "autoSend": true,
  "hotkey": "rightOption",
  "terminal": "auto"
}
```

- `mode`: `whole` or `summary`
- `voice`: any Kokoro English voice, e.g. `af_heart`, `af_bella`, `am_michael`
- `speed`: reading speed, e.g. `1.2`
- `autoSend`: `false` types the words but lets you press Enter yourself
- `hotkey`: `rightOption`, `rightCommand`, `rightControl`, `shift` or `control`
- `hotkeyKeycode`: any ordinary key by its macOS key code, overriding `hotkey`
  (`earshot set-key` writes it). Earshot only listens, so the key still reaches
  the app in front; pick one that does nothing there.
- `terminal`: `auto` (Apple Terminal, plus iTerm2 while it is running),
  `terminal` or `iterm`

## Commands

```sh
earshot                 # dashboard
earshot set-key         # press a key to make it the talk key
earshot doctor          # check hooks and permissions
earshot selftest        # speak a sentence and transcribe it back (no audio)
earshot install-hooks   # add or update hooks in ~/.claude/settings.json (backup first)
earshot uninstall-hooks # remove only Earshot's hooks
earshot uninstall       # remove hooks, event log and config (keeps the model cache)
```

## How it works

Claude Code [hooks](https://code.claude.com/docs/en/hooks) (`SessionStart`,
`UserPromptSubmit`, `PermissionRequest`, `PostToolUse`, `Notification`, `Stop`,
`StopFailure`, `SessionEnd`) run `earshot hook`, which appends one line to
`~/Library/Application Support/Earshot/events.jsonl` with the session's terminal
device. The dashboard tails that log, asks the terminal app (AppleScript) which
tab owns which device, and checks that `claude` is actually running there. The
hooks are async, so they never slow Claude down.

## Uninstall

```sh
earshot uninstall          # hooks (settings backed up first), event log, config
brew uninstall earshot     # or: make uninstall
```

The models are shared with other FluidAudio apps, so Earshot leaves them. If
nothing else uses them:

```sh
rm -rf ~/Library/Application\ Support/FluidAudio/Models ~/.cache/fluidaudio
```

## Limitations

- Apple Terminal is the tested terminal. iTerm2 support is **experimental**:
  written against iTerm2's AppleScript dictionary, not yet tried on a real
  machine. Earshot never launches iTerm2. Ghostty and others can be added by
  implementing `TerminalAdapter`; Ghostty needs 1.4 for terminal devices.
- English only.
- No tmux, screen or ssh sessions: they can't be matched to a tab.
- The dashboard window must stay open.

Reports and pull requests welcome.

## License

MIT
