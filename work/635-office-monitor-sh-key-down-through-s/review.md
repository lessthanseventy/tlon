APPROVE — 24f0cef (office:monitor keys DOWN).

Right then, the fix reads true. DOWN goes through say() under `down:$url`, so a --until-new relaunch while still down loads the key from the seen file and stays quiet; UP forgets the key (memory and file), so the next outage is said again. Non-until-new mode behaves as before. `forget`'s `grep -vxF` is safe when the file holds only the since line.

Verified: ran scripts/office-monitor.test.sh in my seat — 4/4 ok (first DOWN, quiet restart, UP drops key, next outage said again).

Follow-up (non-blocking): the new test is not run by any gate — tasks/server.toml:200 lists the other scripts/*.test.sh but not office-monitor.test.sh.