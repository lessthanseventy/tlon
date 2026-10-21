#!/usr/bin/env bash
# Drive the office TUI headlessly: start it in a private tmux server (never the operator's), send
# each step's keys, print the screen after each, then tear it all down — in ONE call, because a
# harness may reap a tmux server between calls. Half blocks under tmux, so the frame is text.
#
#   office-drive.sh STEP...      each STEP is tmux send-keys arguments: "/" "'108'" "Enter" "M-Enter" ("ctrl+]" is C-])
#                                or click:TEXT[@DX,DY] — a left click on the first screen cell where TEXT starts (+DX columns,
#                                +DY rows): aim at what the screen shows, never at a measured coordinate; or wait:TEXT — no keys; waits until the screen shows TEXT (30 s at most)
#
# TLON_URL picks the server (default the service's 127.0.0.1:4040; `server:dev` is :4041).
# OFFICE_COLS/OFFICE_ROWS size the window (150x60), OFFICE_WAIT the settle per step (1.5 s),
# OFFICE_TAIL how many bottom rows to print (20; the detail pane and foot live there).
# OFFICE_KEEP=1 keeps the drive's throwaway config and state and prints where (`kept: DIR`), so a check
# can read back what the drive saved (home.json, looks.json, …: DIR/config/tlon/).
# OFFICE_SANDBOX=1 starts the TUI with --sandbox: the made-up world, where the toy's keys (e, f, d) and its
# events run; a scratch release has neither, and no server is needed (TLON_URL is ignored).
# OFFICE_WIDE=1 draws the wide room (the door, the bathroom, Argos — it is otherwise only there under kitty
# graphics, which tmux swallows) in half blocks at the scale the window allows, and sizes the window 280x75
# unless OFFICE_COLS/OFFICE_ROWS say otherwise. OFFICE_TEXT=1 prints every row of the screen with the
# pixels dropped, so a room's labels and balloons ("Ding dong!", "Pizza! …") read as lines.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sock="office-drive-$$"
state="$(mktemp -d)"
own="$sock-own"
t() { tmux -L "$sock" "$@"; }
# tmux leaves its socket file behind when its server dies
# the TUI's own tmux (docs, the dump, games) is the drive's too, never the operator's `tlon-office`
trap 't kill-server 2>/dev/null; tmux -L "$own" kill-server 2>/dev/null; rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/"{"$sock","$own"}; rm -rf "${XDG_RUNTIME_DIR:-/tmp}/$own"; if [ -n "${OFFICE_KEEP:-}" ]; then echo "kept: $state"; else rm -rf "$state"; fi' EXIT

# the TUI's config is a copy of the operator's in the throwaway: the drive looks like their office, and
# whatever it writes (pets, the store, the hall, looks, souls) lands in the copy, never in their files
cfg="$state/config"
mkdir -p "$cfg"
src="${XDG_CONFIG_HOME:-$HOME/.config}/tlon"
[ -d "$src" ] && cp -r "$src" "$cfg/tlon"

wide="${OFFICE_WIDE:-}"
if [ -n "$wide" ]; then dcols=280 drows=75; else dcols=150 drows=60; fi
t new-session -d -x "${OFFICE_COLS:-$dcols}" -y "${OFFICE_ROWS:-$drows}" \
  "cd '$root/office' && unset TLON_HALL TLON_HOME TLON_LOOKS TLON_PALETTE TLON_PETS TLON_SOULS && TLON_OFFICE_TMUX='$own' TLON_URL='${TLON_URL:-http://127.0.0.1:4040}' OFFICE_WIDE='$wide' OFFICE_GRAPHICS=blocks MISE_TRUSTED_CONFIG_PATHS='$root' XDG_STATE_HOME='$state' XDG_CONFIG_HOME='$cfg' bun tui/main.ts ${OFFICE_SANDBOX:+--sandbox} 2>'$state/err'"
sleep 3
for step in "$@"; do
  case "$step" in
    wait:*) for _ in $(seq 150); do t capture-pane -p -t 0 | grep -qF -- "${step#wait:}" && break; sleep 0.2; done ;;
    click:*)
      spec="${step#click:}"; want="${spec%%@*}"; off=0,0; [ "$spec" != "$want" ] && off="${spec#*@}"
      pos="$(t capture-pane -p -t 0 | python3 -I -c 'import sys; w,o=sys.argv[1],sys.argv[2].split(","); L=sys.stdin.read().split("\n")
for r,l in enumerate(L):
    c=l.find(w)
    if c>=0: print(c+1+int(o[0]), r+1+int(o[1])); break' "$want" "$off")"
      if [ -z "$pos" ]; then echo "=== no such text on screen: $want"; else set -- $pos; t send-keys -t 0 -l $'\033[<0;'"$1;$2"$'M\033[<0;'"$1;$2"$'m'; sleep "${OFFICE_WAIT:-1.5}"; fi ;;
    # ctrl+X, as the office's own hints spell a key, is tmux's C-X; typed as is it is six letters
    ctrl+*) t send-keys -t 0 "C-${step#ctrl+}"; sleep "${OFFICE_WAIT:-1.5}" ;;
    *) eval "t send-keys -t 0 $step"; sleep "${OFFICE_WAIT:-1.5}" ;;
  esac
  echo "=== after: $step"
  if [ -n "${OFFICE_TEXT:-}" ]; then t capture-pane -p -t 0 | sed -E 's/[▀▄█ ]+/ /g' | grep -E '[[:alnum:]]'
  else t capture-pane -p -t 0 | tail -n "${OFFICE_TAIL:-20}"; fi
done
[ -s "$state/err" ] && { echo "=== stderr"; cat "$state/err"; }
exit 0
