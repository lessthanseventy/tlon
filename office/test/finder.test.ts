import { describe, expect, test } from "bun:test"
import { rank } from "../tui/fuzzy"
import { ticketPicks } from "../tui/finder"

describe("finder: tickets", () => {
  const tickets = [
    { id: 15, workspace_id: 1, project_id: null, title: "Finder can't find tickets", priority: "normal" },
    { id: 16, workspace_id: 1, project_id: null, title: "Unrelated thing", priority: "normal" },
  ]
  const wsName = () => "tlon"
  test("a title query lists the ticket", () => {
    const picks = ticketPicks(tickets, wsName, () => {})
    const hit = rank("finder tickets", picks, (p) => p.text)
    expect(hit.map((p) => p.text)).toEqual(["ticket #15 Finder can't find tickets tlon"])
  })
  test("Enter runs the pick, which opens the ticket's card", () => {
    const opened: number[] = []
    const picks = ticketPicks(tickets, wsName, (id) => opened.push(id))
    picks.find((p) => p.text.startsWith("ticket #15"))!.run()
    expect(opened).toEqual([15])
  })
})
