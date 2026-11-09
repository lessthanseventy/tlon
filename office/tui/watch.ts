import { watch, type FSWatcher } from "node:fs"

/**
 * Calls `onChange` (debounced to `ms`) when anything in one of `dirs` changes. A directory, not a file,
 * is watched so an editor that replaces the file, or a link repointed, still shows. `ok` is false
 * when some directory could not be watched (missing, or a filesystem without inotify): the caller keeps polling then.
 */
export function watchDirs(dirs: string[], onChange: () => void, ms = 100): { ok: boolean; close: () => void } {
  const watchers: FSWatcher[] = []
  let timer: ReturnType<typeof setTimeout> | undefined, ok = true
  const fire = () => { clearTimeout(timer); timer = setTimeout(onChange, ms) }
  for (const d of new Set(dirs)) {
    try { watchers.push(watch(d, fire)) } catch { ok = false }
  }
  return { ok, close: () => { clearTimeout(timer); for (const w of watchers) w.close() } }
}
