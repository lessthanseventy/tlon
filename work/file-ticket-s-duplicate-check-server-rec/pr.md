Closes #713.

`Server.Recurrence`'s duplicate check refused titles over unrelated tickets and missed re-worded duplicates (#711 never matched #712). Two changes:

- **Tokenizer:** strip a trailing `/arity`, also index the parts of `a.b` / `a_b` compounds, stem `-s` / `-ing` / trailing `e`. `hand_to/4` now meets `hand_to`, `raising` meets `raise`, `leads` meets `lead`, so a re-wording shares its words without touching the threshold.
- **Cover (tickets only):** the shared words must be 40% of the smaller title's weight. With the tokenizer alone two of the thirteen refused titles still matched a look-alike (#462, #525); the cover clears them. Issue headlines skip it: they are 200 chars of prose that share few words by design (the sheriff's "worded twice" test).

Checked: `test/fixtures/recurrence_titles.tsv` is every title on the board (724); the new tests file them and assert #711 finds #712 and that the 13 titles quoted in the ticket find none of the tickets they were refused over (red on the old scorer: 8 failures). Existing true-positive tests pass. `menard run check --in server`: see below.
