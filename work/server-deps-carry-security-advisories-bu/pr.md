Bump server deps with security advisories: bandit 1.12.5→1.14.0 (EEF-CVE-2026-105659, -105660, -109584), plug_crypto 2.2.0→2.2.1 (EEF-CVE-2026-105963), thousand_island 1.5.0→1.6.0 (bandit's dep). `server/mix.lock` only.

Closes ticket #624.

Checked: `mix deps.get | grep VULNERABLE` printed nothing (was 2 hits before); `mix hex.audit` → "No retired or security advisory packages found". server:check and release:smoke run via run_task on this head (bandit is a minor bump).
