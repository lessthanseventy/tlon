# Sourced by the gates that report a red run (workline-verify.sh, check-main.sh).
# The failing tests by name (ExUnit's "N) test … (Mod)" + its file:line, bun's "(fail) …" and the
# "error: …" before it that says why, read past mise's "[task] " line prefix): a long suite's last
# 400 bytes hold only its summary, or another task's interleaved compile output, and the lead would
# re-run it to learn what broke.
failures() {
  awk '{ sub(/^\[[^]]*\] /, "") }
       /^ +[0-9]+\) (test|doctest|property) / { sub(/^ +/, ""); h = $0; getline; sub(/^\[[^]]*\] /, ""); sub(/^ +/, ""); print h " — " $0; next }
       /^error: / { e = e $0 "\n"; next }
       /^\(fail\) / { printf "%s", e; e = ""; print }' | cut -c1-160 | iconv -c -f utf-8 -t utf-8 | head -n 10
}
