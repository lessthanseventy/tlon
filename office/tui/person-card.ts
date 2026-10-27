// A person card's own lines (soul + persona), as data: closed, one dim line; open, the lot. Pure.
import { personaLines, type Persona } from "../kit/persona"
import { soulLines, soulNote, type Soul } from "../kit/souls"

export type CardLine = { tone: "dim" | "key" | "plain"; text: string }

export function personCard(soul: Soul | undefined, persona: Persona | null | undefined, width: number, open: boolean): CardLine[] {
  const parts = personaLines(persona, width)
  const sl = soul ? soulLines(soul) : []
  if (!open) {
    const first = persona?.backstory ?? sl[0]?.text.split("\n")[0]
    if (!first) return []
    const hint = " (space)"
    const room = Math.max(8, width - hint.length)
    return [{ tone: "dim", text: `${first.length > room ? `${first.slice(0, room - 1)}…` : first}${hint}` }]
  }
  return [
    ...(soul ? [{ tone: "dim" as const, text: "soul" }] : []),
    ...sl.flatMap(({ head, text }): CardLine[] => [
      ...(head ? [{ tone: "key" as const, text: head }] : []),
      ...(soulNote(head) ? [{ tone: "dim" as const, text: soulNote(head)! }] : []),
      ...text.split("\n").map((l) => ({ tone: "plain" as const, text: l })),
    ]),
    ...parts.map((text) => ({ tone: "dim" as const, text })),
  ]
}
