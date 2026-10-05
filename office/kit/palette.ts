// The office's colours, by role. Every sprite and floor reads ROLE at draw time, so a surface with
// its own theme (the desktop shell) hands its roles in with useRoles and the room follows it; the
// TUI keeps these defaults.
export const ROLE = {
  alarm: "#FF6969",
  assistant: "#B98AFF",
  attention: "#F06CB4",
  body: "#FFB000",
  borderInactive: "#7A5500",
  builder: "#33FF00",
  edge: "#2A2A2A",
  fieldInk: "#0A0A0A",
  ground: "#000000",
  inactive: "#B8994C",
  key: "#33C7FF",
  live: "#33FF00",
  meta: "#B4A5D6",
  panel: "#0D0D0D",
  planner: "#F06CB4",
  prose: "#C7C7C7",
  raised: "#1A1A1A",
  reviewer: "#FFB000",
  structure: "#B5651D",
  surveyor: "#33C7FF",
}
export type Role = keyof typeof ROLE
/** take a surface's own theme: its value for each role this palette has */
export function useRoles(roles: Partial<Record<Role, string>>) { Object.assign(ROLE, roles) }

/** `t` of the way from `base` to `c`: shades between two roles, so they follow a theme switch */
export function tint(c: string, base: string, t: number) {
  const h = (x: string, i: number) => parseInt(x.slice(i, i + 2), 16)
  return "#" + [1, 3, 5].map((i) => Math.round(h(base, i) + (h(c, i) - h(base, i)) * t).toString(16).padStart(2, "0")).join("")
}
// a theme switch brings new hex strings, so the cache keys on the string itself
const rgbs = new Map<string, number[]>()
export function rgb(c: string): number[] {
  let v = rgbs.get(c)
  if (!v) rgbs.set(c, (v = [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16))))
  return v
}

/** WCAG relative luminance of an #rrggbb colour */
export function luminance(c: string): number {
  const [r, g, b] = rgb(c).map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4 })
  return 0.2126 * r! + 0.7152 * g! + 0.0722 * b!
}
/** WCAG contrast ratio between two colours (1 to 21); text needs 4.5 (AA), large text 3 */
export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi! + 0.05) / (lo! + 0.05)
}
