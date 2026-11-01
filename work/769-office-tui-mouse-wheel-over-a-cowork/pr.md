office TUI: the wheel over a zoomed coworker pane pages its view (closes #769)

Zoomed into a pane, the TUI forwarded every mouse report to it as raw bytes (`ESC[<64;c;rM`); the pane's app (Claude Code) read the wheel as Up/Down and cycled prompt history. `keyArgs` (office/tui/terminal.ts) now turns a wheel press into tmux's PPage/NPage and drops every other mouse report (clicks, releases, motion). Arrows and other keys are unchanged.

Checked: test/terminal.test.ts pins the mapping (red before, green after); `mise run office:check` exit 0 (968 pass at both frozen clocks). Live drive of a zoomed pane was not possible from the seat's sandbox (no server).
