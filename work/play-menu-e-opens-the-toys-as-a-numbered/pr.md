# office: E opens a numbered play card; the seven play letters retire (#607)

`E` in the sandbox now opens a PLAY card: 1 event, 2 summon Gary, 3 doorbell, 4 fire drill, 5 treat, 6 night, 7 weather, 8 pet, 9 call over (6/7/9 need the sandbox world; with OFFICE_TOY_KEYS=1 off the sandbox it lists 1-5 and 8). D T F N W P C are unbound, which gives the letters back; every toy stays two keystrokes away. Gary gets his direct summon (row 2).

Closes #607.

Checked: keys.test (sandbox-play is `["E"]`, card:play rows 1-9) and sandbox.test; navigation.test updated to `E 5`; `mise run office:check`; drive walk replay (`E` lists the nine rows; `2` says "Gary's at the dumpster" in the wide room).
