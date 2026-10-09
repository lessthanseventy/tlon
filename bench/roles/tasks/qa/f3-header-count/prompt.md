You are QA on a workline whose ticket reads: "office: the header says how many open threads the
workspace has and how many of them are at work (a coworker on them in build, review or triage); a
thread at plan is open but not at work."

The scratch release is already up, and the office was driven for you. These are the keys pressed and
the screen text after each, captured from the terminal:

```
$ office:drive -- ''
 tlön · office                 4 threads · 2 at work
 > #212 clock sprite flicker        pierre   build
   #213 mailbox letter errand       emma     plan
   #214 nightly gate red            sheriff  triage

$ office:drive -- j j
 tlön · office                 4 threads · 2 at work
   #212 clock sprite flicker        pierre   build
   #213 mailbox letter errand       emma     plan
 > #214 nightly gate red            sheriff  triage

$ office:drive -- j j j
 tlön · office                 4 threads · 2 at work
   #212 clock sprite flicker        pierre   build
   #213 mailbox letter errand       emma     plan
 > #214 nightly gate red            sheriff  triage
```

File your verdict. Reply with a fenced JSON block, exactly this shape:

```json
{"verdict": "pass" | "fail", "finding": "for a fail, the one thing that is wrong; for a pass, null"}
```
