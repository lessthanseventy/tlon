release-smoke picks a free port, never epmd's 4369

The smoke's computed port (`4100 + $$ % 800`) could land on 4369, Erlang's epmd. epmd accepts TCP but
answers no HTTP, so the `curl` guard passed it and the node booted on the taken port. `smoke_pick_port`
(scripts/lib/smoke-build.sh) now steps past 4369, 4040 and any port with a listener (`ss -Hltn`, or a
`/dev/tcp` connect where ss is missing). The pick runs before `db=` derives from the port. An explicit
`TLON_SMOKE_PORT` stays the operator's and is not stepped.

Closes ticket #687.

Checked: three new cases in `scripts/release-smoke.test.sh` (free base → itself; 4369 → 4370; 4040 → 4041;
a base held by a live `elixir -e :gen_tcp.listen` → base+1) went red first (`smoke_port_taken` / `smoke_pick_port`:
command not found), then green. `bash scripts/release-smoke.test.sh` exits 0 with 13 ok lines.
