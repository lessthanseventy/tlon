No free reviewer is at the builder's grade (senior): this review was done by ulrikke at lead grade.

Verdict: approve.

Checked:
- `bun test test/terminal.test.ts` in office/: 6 pass, 0 fail (run by me in this review).
- The mapping in office/tui/terminal.ts: wheel press (button 64/65, no motion bit) becomes PPage/NPage, flushing pending hex first. Clicks, releases (`m`) and motion (bit 32) are consumed and dropped, so no mouse report reaches the pane as bytes or arrows. Non-mouse keys take the existing path unchanged.
- The test pins the three cases: wheel up, wheel down, and wheel between text bytes.

Not verified: a live drive of a zoomed pane (the builder notes no server in its sandbox). This is unverified and should be treated as open until someone drives it.

Follow-up (non-blocking): horizontal wheel buttons 66/67 also satisfy `b & 64` and are mapped to PPage/NPage, so a sideways wheel pages history. Either drop them or leave a test that says it is deliberate.