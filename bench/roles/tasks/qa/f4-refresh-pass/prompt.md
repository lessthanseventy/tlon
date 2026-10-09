You are QA on a workline whose ticket reads: "office: `R` refreshes the room from the server at once
(threads opened or closed since show up) and the header shows `↻ refreshed` for two seconds, then the
mark goes away."

The scratch release is already up, and the office was driven for you. Between the first and second
capture, a new thread (#216) was opened on the server from another shell. These are the keys pressed
and the screen text after each, captured from the terminal:

```
$ office:drive -- ''
 tlön · office                 2 threads · 2 at work
 > #214 nightly gate red            sheriff  triage
   #215 badge initials              pierre   review

$ office:drive -- R
 tlön · office                 3 threads · 2 at work   ↻ refreshed
 > #214 nightly gate red            sheriff  triage
   #215 badge initials              pierre   review
   #216 archive sort order          zunz     plan 

$ office:drive -- R (wait 3s)
 tlön · office                 3 threads · 2 at work
 > #214 nightly gate red            sheriff  triage
   #215 badge initials              pierre   review
   #216 archive sort order          zunz     plan 
```

File your verdict. Reply with a fenced JSON block, exactly this shape:

```json
{"verdict": "pass" | "fail", "finding": "for a fail, the one thing that is wrong; for a pass, null"}
```
