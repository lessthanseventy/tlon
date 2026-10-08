// Build mode's engine: a home is tiles on a cell grid (`home.json`, read and written by the
// surface — see tui/home.ts), and build mode places, picks up, carries, rotates, removes and
// undoes them. Every tile this step is one cell with doors open on all four sides, so the floor's
// connectivity is just grid adjacency — the rule a drop must keep: the floor stays one piece, or
// the drop is refused.

export type HomeTileKind = "living" | "kitchen" | "bathroom" | "bedroom" | "street"
export const CATALOGUE: HomeTileKind[] = ["living", "kitchen", "bathroom", "bedroom", "street"]

export type Pt = [number, number]
export type HomeTile = { kind: HomeTileKind; at: Pt; rot?: 0 | 90 | 180 | 270 }
export type Home = { tiles: HomeTile[] }

const HISTORY_LIMIT = 10
const posKey = (p: Pt) => `${p[0]},${p[1]}`
const neighbors = ([x, y]: Pt): Pt[] => [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]]

/** the floor is in one piece: every tile reachable from the first, through a shared edge */
export function connected(tiles: HomeTile[]): boolean {
  if (tiles.length <= 1) return true
  const byPos = new Map(tiles.map((t) => [posKey(t.at), t]))
  const seen = new Set([posKey(tiles[0]!.at)])
  const stack: Pt[] = [tiles[0]!.at]
  while (stack.length) {
    for (const n of neighbors(stack.pop()!)) {
      const k = posKey(n)
      if (byPos.has(k) && !seen.has(k)) { seen.add(k); stack.push(n) }
    }
  }
  return seen.size === tiles.length
}

export function at(home: Home, p: Pt): HomeTile | undefined {
  return home.tiles.find((t) => t.at[0] === p[0] && t.at[1] === p[1])
}

/** would `tile` overlap another tile, or leave the floor in more than one piece? */
export function canPlace(home: Home, tile: HomeTile): boolean {
  const rest = home.tiles.filter((t) => t !== at(home, tile.at))
  if (rest.length !== home.tiles.length) return false // the cell is already taken
  return connected([...rest, tile])
}

export type Build = { home: Home; cursor: Pt; carrying: HomeTile | null; history: Home[]; refused: boolean; writes: number }

export function startBuild(home: Home): Build {
  return { home, cursor: [0, 0], carrying: null, history: [], refused: false, writes: 0 }
}

const remember = (b: Build): Home[] => [...b.history, b.home].slice(-HISTORY_LIMIT)

export function move(b: Build, dx: number, dy: number): Build {
  return { ...b, cursor: [b.cursor[0] + dx, b.cursor[1] + dy], refused: false }
}

export function pickUp(b: Build): Build {
  if (b.carrying) return b
  const tile = at(b.home, b.cursor)
  if (!tile) return b
  return { ...b, carrying: tile, home: { tiles: b.home.tiles.filter((t) => t !== tile) }, refused: false }
}

export function drop(b: Build): Build {
  if (!b.carrying) return b
  const tile: HomeTile = { ...b.carrying, at: b.cursor }
  if (!canPlace(b.home, tile)) return { ...b, refused: true }
  return { ...b, home: { tiles: [...b.home.tiles, tile] }, carrying: null, refused: false, history: remember(b), writes: b.writes + 1 }
}

/** cycles the catalogue onto the cursor's cell: empty → the first kind, a tile there → its successor */
export function place(b: Build): Build {
  if (b.carrying) return b
  const existing = at(b.home, b.cursor)
  const kind = CATALOGUE[existing ? (CATALOGUE.indexOf(existing.kind) + 1) % CATALOGUE.length : 0]!
  const tile: HomeTile = existing?.rot ? { kind, at: b.cursor, rot: existing.rot } : { kind, at: b.cursor }
  const without = { tiles: b.home.tiles.filter((t) => t !== existing) }
  if (!canPlace(without, tile)) return { ...b, refused: true }
  return { ...b, home: { tiles: [...without.tiles, tile] }, refused: false, history: remember(b), writes: b.writes + 1 }
}

export function remove(b: Build): Build {
  if (b.carrying) return b
  const tile = at(b.home, b.cursor)
  if (!tile) return b
  const rest = b.home.tiles.filter((t) => t !== tile)
  if (!connected(rest)) return { ...b, refused: true }
  return { ...b, home: { tiles: rest }, refused: false, history: remember(b), writes: b.writes + 1 }
}

export function rotate(b: Build): Build {
  if (b.carrying) return b
  const tile = at(b.home, b.cursor)
  if (!tile) return b
  const rot = (((tile.rot ?? 0) + 90) % 360) as HomeTile["rot"]
  return { ...b, home: { tiles: b.home.tiles.map((t) => (t === tile ? { ...t, rot } : t)) }, history: remember(b), writes: b.writes + 1 }
}

export function undo(b: Build): Build {
  if (b.carrying) return b
  if (!b.history.length) return b
  return { ...b, home: b.history[b.history.length - 1]!, history: b.history.slice(0, -1), writes: b.writes + 1 }
}
