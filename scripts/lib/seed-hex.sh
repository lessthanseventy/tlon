# Sourced by the gates (workline-verify.sh, check-main.sh, release-smoke.sh) for a Hex home of their own.
#
# Hex reads hex.config at every mix boot and rewrites it in place (File.write!: truncate, then write)
# when a fetch refreshes the hex.pm token, so a gate booting mix while any other mix on the machine
# rewrites the shared ~/.hex reads an empty or half-written config: it runs without its repos, or
# dies in Hex.start. A gate boots on a Hex home of its own, seeded with the user's config (repo keys,
# tokens) and registry cache; the package tarballs stay behind (128M, and /tmp has no reflinks) — a
# dep the copied deps/ lacks is fetched again.
seed_hex_home() { # src dest
  mkdir -p "$2"
  local f i
  for f in hex.config cache.ets; do
    [ -f "$1/$f" ] || continue
    # the copy can land mid-rewrite, empty: take it again, and never keep a blank one
    for i in 1 2 3 4 5; do
      cp "$1/$f" "$2/$f" && [ -s "$2/$f" ] && break
      rm -f "$2/$f"; sleep 0.2
    done
  done
  return 0
}
