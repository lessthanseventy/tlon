# Hall `W`: draw a hire's soul and pitch on demand (#660)

- `Server.Soul.preview/2` (the soul `draft/2` would write, model-then-template; writes nothing) and
  `POST /api/workspaces/:id/hire/draft` → `{soul, pitch, source}`; pitch is the fixed template.
- Office: `data.draftSoul`, pure `drawSoul`, and the hall key that stores the draft as the `soul`/`pitch`/`drawn`
  overrides, so `e` edits it and a hire writes what was seen. The render never calls the server.
- Key is `W`, not `s`: `s` means sort everywhere (`keys.test.ts` enforces one verb per key).
- Checked: `menard run check --in server` (only red was a tmp-fixture stamp in my test, fixed; gateway+stamp tests green after),
  `bun test` in office (963 pass; the one fail was the `s` clash), then keys+hall tests green and `bunx tsc --noEmit` clean.
  Live `W` against a real server is owed to verify.
