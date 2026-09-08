---
name: drive-cockpit
description: Drive the live Tlön cockpit (the console TUI) from Claude through a shared tmux session — send keys, read the frame back as text, screenshot it. Use for live passes, reproducing a UX bug, or verifying a frame change end to end (not just tests). Andrew starts the session in ghostty; Claude never launches the cockpit itself.
---

# Driving the cockpit over tmux

The cockpit (`mise run console:run`) is a termbox TUI: it cannot be scripted directly, but inside a
tmux session its frame is text tmux can capture and its keys are keys tmux can send. This is how
Claude and Andrew look at the same screen.

## Setup (Andrew, in a ghostty window)

```
mise run console:run:tmux
```

That variant runs the cockpit inside the `tlon` tmux server (session `cockpit`, `-A` attaches).
The plain `console:run` runs on the bare terminal on purpose: the cockpit draws icons with the
kitty graphics protocol and reads keys with the kitty keyboard protocol, and tmux passes
neither through — so under tmux the WS tiles and icons are blank and Ctrl+Space is `C-Space`.
Drive layout, text and flow in tmux; judge icons and glyph alignment on the bare terminal.

- `-L tlon` is a dedicated tmux server so the cockpit's own coworker servers (`console-workspace-*`)
  and the default server are never touched.
- Alt chords (`Alt+d`, `Alt+\`, `Alt+Shift+N`) must pass through tmux: the flake's tmux.conf sets
  `extended-keys on` and `escape-time 0`; if a chord does not land, check `tmux -L tlon show -s extended-keys`.
- The tlon service must be up (`systemctl --user is-active tlon`); `console:run` refuses otherwise.

## Driving (Claude)

Every tmux call needs the sandbox off (the socket is under `/tmp/tmux-1000`): pass
`dangerouslyDisableSandbox: true` and say why once.

Prefer the helper — it sends, waits for the frame to SETTLE (two identical captures 300 ms
apart, tmux-cli's wait_idle idea), and prints the frame, so a read never lands mid-repaint:

```
scripts/cockpit-tmux.sh send j j Enter      # keys, then the settled frame
scripts/cockpit-tmux.sh send M-d            # the drawer
scripts/cockpit-tmux.sh type 'hello there'  # literal text into the focused input
scripts/cockpit-tmux.sh cap                 # just read
scripts/cockpit-tmux.sh idle 10             # wait up to 10 s for a slow repaint
scripts/cockpit-tmux.sh size 79 30          # the narrow layout
```

Raw tmux, when the helper is not enough. Read the frame:

```
tmux -L tlon capture-pane -t cockpit -p -e      # -e keeps colours as SGR; drop it for plain text
```

Send keys (tmux key names; `M-` is Alt, `C-` is Ctrl, `Escape`, `Enter`, `Tab`, `BTab`):

```
tmux -L tlon send-keys -t cockpit j j Enter
tmux -L tlon send-keys -t cockpit M-d           # the drawer
tmux -L tlon send-keys -t cockpit -l 'hello'    # literal text into the reply box
tmux -L tlon send-keys -t cockpit Escape
```

Wait ~300 ms after a key before capturing (the cockpit repaints on its tick). A real screenshot
when colours or glyph alignment matter: `mise run shot:window ghostty` (grim, prints the path),
then Read the png.

Size: `tmux -L tlon resize-window -t cockpit -x 120 -y 40` to test the narrow layout (< 80 cols
collapses to one column).

## Reading what happened underneath

- Cockpit stderr: `~/.cache/tlon/stderr.log` (the frame never shows it).
- Crash notice: printed to stdout after the tty is restored (`Console.Cockpit.Recovery`).
- Server side: `mise run server:console` (remote iex into the service), or
  `journalctl --user -u tlon -n 50`.
- Hot reload after a code edit: `mise run console:reload` in a second terminal (render/keymap/panel
  edits land on the next tick; a state-shape change needs a restart: `q` then `console:run` again).

## Rules

- Never `tmux kill-server -L tlon` or `kill-session`: that is Andrew's window. `q` in the cockpit quits it cleanly.
- Never type into the coworker's terminal pane on his behalf unless asked — that is a live agent.
- Report what the capture shows, not what the code says should be there.

## The bare-terminal path (untested as of 2026-09-08 — try it first next time)

Ghostty has no `kitty @ send-text` equivalent, but the compositor does: `wtype` (flake) is a
Wayland virtual keyboard. Focus the cockpit's ghostty window, type, screenshot — nothing in the
path degrades icons or kitty keys, at the cost of stealing focus while keys are sent.

```
A=$(hyprctl -j clients | jq -r '.[]|select(.title=="mise run console:run")|.address')
hyprctl dispatch "hl.dsp.focus({ window = \"address:$A\" })"
wtype -M ctrl -k space -m ctrl          # Ctrl+Space
wtype -k Tab; wtype 'hello'; wtype -k Return
mise run shot:window 'mise run console:run'   # grim → png; Read it
```

If this works, prefer it over `console:run:tmux` for anything visual, and tmux for text/flow.
