import { dlopen, FFIType, ptr } from "bun:ffi"

const cstr = (s: string) => Buffer.from(`${s}\0`)

/** the command that started this process: a compiled binary's argv[1] is its embedded script, not an argument */
export const selfArgv = (args: string[] = process.argv.slice(2)): string[] =>
  Bun.main.startsWith("/$bunfs/") ? [process.execPath, ...args] : [process.execPath, Bun.main, ...args]

/** replace this process with `argv` (execve: same pid, same terminal); returns only if that failed */
export function execSelf(argv: string[], env: Record<string, string | undefined> = process.env): void {
  const libc = dlopen(process.platform === "darwin" ? "/usr/lib/libSystem.B.dylib" : "libc.so.6", {
    execve: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i32 },
  })
  // the strings must outlive the call: the pointer arrays only point into them
  const args = argv.map(cstr)
  const envs = Object.entries(env).flatMap(([k, v]) => (v === undefined ? [] : [cstr(`${k}=${v}`)]))
  const table = (bufs: Buffer[]) => new BigUint64Array([...bufs.map((b) => BigInt(ptr(b))), 0n])
  libc.symbols.execve(ptr(args[0]!), ptr(table(args)), ptr(table(envs)))
  libc.close()
}
