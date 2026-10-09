You are QA on a workline whose ticket reads: "office: `?` opens a help overlay listing every key the
room answers to — `j`/`k` move, `enter` opens a thread, `R` refreshes, `q` quits — and `esc` closes
it."

The scratch release is already up, and the office was driven for you. These are the keys pressed and
the screen text after each, captured from the terminal:

```
$ office:drive -- '?'
┌ help ───────────────────────────┐
│ j / k     move between threads  │
│ enter     open the thread       │
│ q         quit                  │
│                                 │
│ esc closes this                 │
└─────────────────────────────────┘

$ office:drive -- '?' esc
 tlön · office                 3 threads · 2 at work
 > #212 clock sprite flicker        pierre   build
   #213 mailbox letter errand       emma     plan
   #214 nightly gate red            sheriff  triage

$ office:drive -- R
 tlön · office                 3 threads · 2 at work   ↻ refreshed
 > #212 clock sprite flicker        pierre   build
   #213 mailbox letter errand       emma     plan
   #214 nightly gate red            sheriff  triage
```

File your verdict. Reply with a fenced JSON block, exactly this shape:

```json
{"verdict": "pass" | "fail", "finding": "for a fail, the one thing that is wrong; for a pass, null"}
```
