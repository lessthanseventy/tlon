import { execSelf, selfArgv } from "../../tui/exec"

// first run: say our pid and exec ourselves; the second says its pid and the env it was handed
if (process.argv[2] === "again") {
  console.log(`after ${process.pid} ${process.env.EXEC_SELF_MARK}`)
  process.exit(7)
}
console.log(`before ${process.pid}`)
execSelf(selfArgv(["again"]), { ...process.env, EXEC_SELF_MARK: "carried" })
console.log("exec failed")
process.exit(1)
