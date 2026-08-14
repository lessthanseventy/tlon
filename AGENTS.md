# machine — boundaries for a session at the repo root

This repository is one person's whole machine: an installer, dotfiles, a desktop, and an AI stack, as
Nix-shaped modules under `modules/`. Read `docs/plans/2026-08-14-machine-v2-and-funes-design.md` before
reshaping anything here — it is the design and every decision behind it.

## The rules most likely to be broken by accident

- **Working inside `modules/funes/`? That module has its own law.** Read `modules/funes/AGENTS.md` and
  `modules/funes/docs/spec.md` first, and let them win. This root file governs the layer *around* the
  modules, not the modules' insides.
- **`funes` is a bounded module and the boundary is load-bearing.** It must never import up into machine
  config — no reading a `theme` variable, no assuming `desktop`, no path into `hosts/`. The reason is the
  cohesion model: the *same* `funes` runs on other machines, sovereign on each, talking only over its
  channel. A reach upward welds it to this box and breaks that. The unit that travels is `modules/funes/`.
- **Nix commands are the human's to run, via `!`.** On this machine the tool sandbox segfaults the `nix`
  binary (exit 139), and building a machine is a system change the human owns anyway. Author the flake
  and modules; ask the human to run `nix`/`home-manager`/`nixos-rebuild` and paste the output. A claim
  that a build works without a real pasted result is the one thing this repo cannot afford — same rule
  the `funes` spec was written to enforce.
- **A module is born when it has content.** Do not create empty placeholder directories to imply a
  structure that does not exist yet. The tree should not lie about what is built.
- **Adopt Nix gradually.** home-manager on Arch first, a disposable NixOS VM (`nixos-rebuild build-vm`)
  as the testbed, metal last. Do not propose replacing the OS as a first step.

## Verify

There is almost nothing to run yet. When there is, a claim that it works is backed by the command that
proved it — Nix commands by the human's pasted output, everything else by having run it here.
