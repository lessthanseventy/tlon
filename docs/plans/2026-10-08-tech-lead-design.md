# The tech lead — design

**2026-10-08**, Andrew + Uqbar.

## The problem

"Lead" meant the bench's first builder: the default addressee, given the second executive desk,
with a builder's brief and no duty beyond building. The room labelled it "(lead)", which reads as
a second boss under tertius. Meanwhile nobody owned the work itself, and on 2026-10-08 that gap
was where things broke: a workline duplicated what main already had (#199), one had no spec (#198),
two branches edited the same lines and bounced the merge queue (#194 against #167), a junior on a
small model was handed a migration (#197), and builders' technical questions went straight to
the operator.

## The split

- **tertius = flow.** Intake, staffing, the inbox, seats, schedules: who does what, when. He
  never reads code closely and never writes it.
- **The tech lead = coherence.** The bench's lead (`Server.Coworker.lead/1`, unchanged: its
  first builder) is the tech lead. Before a workline is staffed, he reads it: is it already on
  origin/main, does it overlap a workline in flight (same files), what grade does it need, does it
  need a spec first. He answers builders' technical questions so only scope and taste reach the
  operator, and holds back worklines that would collide. He builds only greybeard work, and only
  when nothing waits on his judgment.
- **The operator = scope, priority, taste.**

## The pieces

1. The lead's brief: `Server.Profiles.instantiate/2` appends the tech-lead duties to the seat
   that is its workspace's lead.
2. tertius's brief: before staffing a workline he asks the tech lead for his read (a post on the
   lobby naming him) and staffs by it; the ticket still carries its source's own words.
3. The room's desk reads "(tech lead)".

Swapped in after #197 (hronir's epics migration) passes verify, so it isn't handed off mid-way.
