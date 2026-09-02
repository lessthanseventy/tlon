import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { RECALL_CONFIG_PATH } from "./extension";

// The recall knobs (captureModel, captureEveryTurns, correctionDetection) are flake-owned:
// flake.nix writes the file and the extension reads it. If the two names drift, the flake's
// knobs are silently inert (the 2026-09 funes-recall.json vs server-recall.json miss).
test("the extension reads the recall config at the path flake.nix writes", () => {
  const flake = readFileSync(join(import.meta.dir, "../../../../flake.nix"), "utf-8");
  expect(flake).toContain(`home.file."${RECALL_CONFIG_PATH}"`);
});
