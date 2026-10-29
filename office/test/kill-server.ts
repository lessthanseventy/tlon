import { rmSync } from "node:fs"

// tmux does not unlink its socket on kill-server, so the path is read from tmux before the kill:
// TMUX_TMPDIR in process.env is not what a Bun.spawnSync'd tmux necessarily saw.
export const killServer = (name: string) => {
  const path = new TextDecoder().decode(Bun.spawnSync(["tmux", "-L", name, "display", "-p", "#{socket_path}"]).stdout).trim()
  Bun.spawnSync(["tmux", "-L", name, "kill-server"])
  if (path) rmSync(path, { force: true })
}
