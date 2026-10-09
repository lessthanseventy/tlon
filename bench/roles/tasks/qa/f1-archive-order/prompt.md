You are QA on a workline whose ticket reads: "office: `a` toggles the archive — the workspace's
closed threads, newest first, each with the day it closed — and `a` again goes back to the open
threads."

The scratch release is already up, and the office was driven for you. These are the keys pressed and
the screen text after each, captured from the terminal:

```
$ office:drive -- ''
 tlön · office                 2 threads · 1 at work
 > #214 nightly gate red            sheriff  triage
   #215 badge initials              pierre   review

$ office:drive -- a
 tlön · archive                6 closed
 > #196 close tracks branch         closed Oct 05
   #198 intake todo slot            closed Oct 05
   #201 submit_qa thread id         closed Oct 06
   #205 epics step 1                closed Oct 07
   #209 office activity feed        closed Oct 08
   #211 corkboard suggestions       closed Oct 08

$ office:drive -- a a
 tlön · office                 2 threads · 1 at work
 > #214 nightly gate red            sheriff  triage
   #215 badge initials              pierre   review
```

File your verdict. Reply with a fenced JSON block, exactly this shape:

```json
{"verdict": "pass" | "fail", "finding": "for a fail, the one thing that is wrong; for a pass, null"}
```
