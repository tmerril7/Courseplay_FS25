# Courseplay FS25 Fork — Improvement Opportunities

> Candidate directions for `tmerril7/Courseplay_FS25`. Written 2026-07-11.
> Fork is in sync with upstream v8.1.0.3.

## Context that shapes strategy
- **Upstream has stalled**: 27 commits/mo (Dec 2025) → ~2-3/mo now. Open issue
  #1290 "Will there ever be new updates to CP?". 157 open issues. This is a
  mature, high-quality codebase whose maintainers have largely moved on — a good
  fork target: lots of low-hanging fruit, little merge-conflict churn.
- **GPL v3** — any distributed fork must stay GPLv3 (fine, just a constraint).
- **Tested surface is narrow** — course gen + pathfinder + math have unit tests;
  the 27K-LOC AI layer has none. Regressions there are invisible until in-game.
- **11 `TODO_25`** = unfinished FS25-port stubs; **167** total TODO/FIXME/HACK.

## Improvement themes (ranked by impact ÷ effort)

### A. Bug-fix crashes (highest value, lowest risk, best "make it mine")
Nil-index crashes that hard-stop the game or a driver — self-contained, testable,
directly help players:
- #1241 `CpCourseManager.lua:370: attempt to index nil with 'delete'` — blocks
  savegame load entirely.
- #1227 `attempt to index nil with 'spec_cpAIBunkerSiloWorker'`.
- #1230 `UnloadCombine calls a missing method`.
- #1236 auger wagon crashes into combine's folded grain pipe / header edge
  (collision geometry).
Each is a scoped fix + ideally a regression case. Great first PRs to build fluency.

### B. Finish the FS25 port stubs (`TODO_25`)
Re-enable features disabled during the FS24→25 port:
- **CpGamePadHud** registration disabled (`Courseplay.lua:284`) — controller UI.
- **Side-unloading** disabled (`CpJobParameters:331`).
- **LevelerController shield logic** disabled (`LevelerController.lua:230`).
- **SowingMachineController fruit-check** — FS25 growthSystem lacks
  `canFruitBePlanted`; needs a new API path.
- **APalletAutoLoaderController:101** breaks multi-trailer fieldwork.
Higher effort (need to learn FS25 engine APIs) but each restores a real feature.

### C. Field boundary / course-generation quality
Recurring player pain and where the "AI cleaned up my field edge" community
threads point (#1291):
- **FieldScanner has no island detection** (TODO) and fragile probe tracing;
  comments say logic should move into the course generator.
- Headland/corner quality: #1277 (overlapping headland passes), #1278 (corner
  radius too small), #1266 (headland differs by cw/ccw direction).
- `Center.lua`/`Headland.lua` island handling is the most error-prone axis
  ("everything is backwards" comments recur).
This is deep work but the highest-leverage *feature* differentiation.

### D. Multiplayer robustness
- #1247 general MP issues, #1256 can't connect 2 vehicles on 1 course.
- Settings sync is stringly-typed dirty-flag events — fragile, hard to reason about.
An audit of the `events/` layer + reproducing the 2-vehicle case could fix a class
of bugs.

### E. New features requested by players (differentiation)
- #1293 / #1244 baling windrows work mode; #1286 seeder support; #1250 wheel
  loader unload into conveyor.
- These make the fork visibly "yours" but are the largest builds.

### F.0 IslandTest + CI coverage — ✅ DONE (2026-07-11, `fork/crash-fixes`)
`IslandTest.lua:18` expected 9900 island vertices; `Island.findIslands` returns
10201. Investigated (docs-fork diagnostic): the 10201 is CORRECT — a clean 101×101
inclusive 1 m grid over the |x|,|z|≤50 island, bbox exactly [-50,50]², all points
off-field, zero duplicates. The 9900 was a STALE expectation from commit 4c1e8fc3,
pre-dating later island-detection fixes (ae1df08e, f635d22f) that changed grid
alignment to include both boundary rows. Fixed by updating the test expectation +
comment (NOT the code — forcing 9900 would drop legitimate island coverage).

Root cause of the drift: CI's `unit-test.yml` ran a hand-maintained list that
omitted IslandTest.lua and VectorTest.lua (and duplicated SliderTest.lua). Rewrote
the run step to auto-discover every `*Test.lua` in each test dir, so new tests are
always picked up and the list can't drift again. All 23 suites now green in CI-shape.

### F. Code health (enabler, not user-facing)
- Make `Courseplay.register` async (explicit TODO) — cuts startup cost over all
  vehicle types.
- Extend the unit-test harness (mocks already exist in `scripts/test/`) to cover
  more of the pure-logic layers, esp. course generator edge cases + a first AI
  strategy test scaffold. Lowers regression risk for everything above.
- Replace/wrap the stringly-typed settings + `raiseCallback` dispatch with
  something checkable (long-term).

## Suggested first move
Pick **2-3 crash bugs from theme A**, reproduce, fix, and add regression tests.
Low risk, fast feedback, teaches the codebase, and produces mergeable/publishable
PRs — the fastest way to make the fork genuinely yours while staying rebaseable on
upstream. Then decide between a quality push (C) or a headline feature (E).

## Decisions made (2026-07-11)
- **Goal:** personal improvements, kept **rebaseable on upstream** (work on
  branches, don't diverge `main`).
- **First target:** crash bug fixes + regression tests.
- Working branch: `fork/crash-fixes`.

## ⚠️ Critical triage caveat
Current `main` (= our fork) is **23 commits AHEAD of the released `8.1.0.3` tag**
(release 2025-12-14, main HEAD later). Bug reporters run 8.1.0.3, so **many
reported crashes are already fixed** in the code we have. ALWAYS check
`git log --oneline 8.1.0.3..HEAD -- <file>` and inspect current HEAD before
"fixing" anything.
- **#1241** (`CpCourseManager.lua:370` nil delete) — **ALREADY FIXED** by commit
  f4093e8d (2025-12-31, onPreDelete guard). Do not touch.
- **#1227** (`spec_cpAIBunkerSiloWorker` nil index) — **ALREADY FIXED** by commit
  8b20d0a9 (bunker silo only). Do not touch bunker silo.
- **#1236** (auger wagon collides w/ combine) — BEHAVIORAL (proximity sensors
  can't see folded pipe/header). Not a Lua crash. Deferred — tuning-heavy.

## Fixes applied on `fork/crash-fixes` (2026-07-11)
Triage found the #1227 race fix (8b20d0a9) was applied to the bunker-silo spec
ONLY; four sibling specs still had the identical racy alias clobber. Applied the
conservative core of that fix to all four:
- `CpAIFieldWorker.lua` — dropped redundant `self.spec_cpAIFieldWorker =` clobber.
- `CpAIBaleFinder.lua` — onLoad reads full-name key into local, no short-alias write.
- `CpAICombineUnloader.lua` — same.
- `CpAISiloLoaderWorker.lua` — same.
Each stops `onLoad` writing the engine-created short alias (which a load/reload
race can nil, crashing external readers like `CpJobParameters`). Other functions
still read the (now un-clobbered) engine alias → strictly better, no regression.
More conservative than upstream (didn't convert every internal read to getSpec).

Also fixed **#1230** latent bug: `AIDriveStrategyUnloadCombine:updateCombineStatus`
called `getCpDriveStrategy():isReversing()` — a method the combine strategy lacks.
Swapped to `AIUtil.isReversing(self.combineToUnload)`. NOTE: that function is
currently dead code (no caller), so this is latent hardening, not a reproduced
live crash. Did NOT reproduce #1230's actual runtime error in HEAD.

⚠️ **Not runtime-verified** — no local Lua interpreter; the real test is loading
the mod in-game (esp. an MP join). Verify before relying on it.
</content>
