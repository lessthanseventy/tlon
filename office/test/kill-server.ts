import { rmSync } from "node:fs"

// tmux does not unlink its socket on kill-server, so the path is read from tmux before the kill:
// TMUX_TMPDIR in process.env is not what a Bun.spawnSync'd tmux necessarily saw.
// A server whose last pane exited answers nothing, so the path is then built from TMUX_TMPDIR: that
// is where tmux leaves the dead socket file behind.
export const killServer = (name: string) => {
  const path = new TextDecoder().decode(Bun.spawnSync(["tmux", "-L", name, "display", "-p", "#{socket_path}"]).stdout).trim()
    || `${process.env.TMUX_TMPDIR || "/tmp"}/tmux-${process.getuid!()}/${name}`
  Bun.spawnSync(["tmux", "-L", name, "kill-server"])
  rmSync(path, { force: true })
}
