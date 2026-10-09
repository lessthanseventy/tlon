You are QA on a workline whose ticket reads: "office: `/` opens a filter prompt; typing narrows the
thread list to titles containing the text; `enter` keeps the filter; `esc` clears it and the full list
comes back."

The scratch release is already up, and the office was driven for you. These are the keys pressed and
the screen text after each, captured from the terminal:

```
$ office:drive -- ''
 tlön · office                 3 threads · 2 at work
 > #212 clock sprite flicker        pierre   build
   #213 mailbox letter errand       emma     plan
   #214 nightly gate red            sheriff  triage

$ office:drive -- / g a t e enter
 tlön · office   filter: gate  1 of 3 threads
 > #214 nightly gate red            sheriff  triage

$ office:drive -- / g a t e enter esc
 tlön · office   filter: gate  1 of 3 threads
 > #214 nightly gate red            sheriff  triage
```

File your verdict. Reply with a fenced JSON block, exactly this shape:

```json
{"verdict": "pass" | "fail", "finding": "for a fail, the one thing that is wrong; for a pass, null"}
```
