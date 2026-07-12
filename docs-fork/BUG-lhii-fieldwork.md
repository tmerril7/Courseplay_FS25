# Bug: LH II forage harvester doesn't enable Courseplay fieldwork

**Symptom (Travis):** With no implement, CP HUD offers tractor-only jobs (silo
compaction). Attaching the Lacotech LH II (forage-harvester front attachment that
takes a pickup header) does NOT enable the "load a course / run recorded job"
fieldwork option — CP behaves as if no compatible implement is attached.

## The decision path
HUD/course option appears only when `CpAIFieldWorker:getCanStartCpFieldWork()`
returns true (`scripts/specializations/CpAIFieldWorker.lua:266`). It checks a list
of specializations, else falls back to Giants' `getCanStartFieldWork()` (whose own
comment at line 278 says it "can't handle forage harvesters").

## Root-cause mechanism (confirmed in code)
Two AIUtil helpers differ in DEPTH:
- `hasImplementWithSpecialization(v, spec)` → `v:getAttachedImplements()` =
  **directly attached implements only (depth 1)**.
- `hasChildVehicleWithSpecialization(v, spec)` → `v:getChildVehicles()` =
  **entire attach tree (recursive)**.

Line 279 checks `Cutter` with the **shallow** helper, unlike its siblings
(Baler/ForageWagon/VineCutter/Plow/Mower/PushHandTool all use the recursive one).

Attach chain for the LH II:  **Tractor → LH II (harvester unit) → Pickup (header)**.
The pickup header is a **grandchild (depth 2)**. The shallow `Cutter` check only
sees the LH II (depth 1), which is not a Cutter, so it misses the pickup →
`getCanStartCpFieldWork()` returns false → no fieldwork option.

## Candidate fixes
- **A (targeted):** line 279 `hasImplementWithSpecialization(self, Cutter)` →
  `hasChildVehicleWithSpecialization(self, Cutter)`. Finds the grandchild pickup,
  aligns with sibling checks. Robust regardless of the LH II unit's own spec.
  Small false-positive risk: a tractor hauling a *loose* header on a trailer (no
  harvester) would then also show the fieldwork option (starting it does nothing
  harmful). Trailered-cutter-WITH-harvester is already treated as valid elsewhere.
- **B (precise):** add `hasChildVehicleWithSpecialization(self, Combine)` — forage
  harvesters carry the Combine spec, so this detects the mounted harvester unit
  without the loose-header false positive. Depends on the LH II actually having the
  Combine spec.

Likely best: A, or A+B. Needs the diagnostic to confirm which spec the pickup and
LH II carry, and at what depth.

## ✅ RESOLVED (2026-07-11) — fix A applied and verified in-game
In-game diagnostic (`docs-fork/diagnose_lhii.lua`) confirmed the attach tree and
specs exactly:
```
Tractor (8R 410) → LH II [Combine] → PICK UP 300 [Cutter]   (Cutter = grandchild)
hasImplementWithSpecialization(Cutter)    [DEPTH1] = false   ← the bug
hasChildVehicleWithSpecialization(Cutter) [FULL]   = true
getCanStartFieldWork() (Giants)                    = false
getCanStartCpFieldWork()  BEFORE fix               = false   ← symptom
getCanStartCpFieldWork()  AFTER fix                = true    ← fixed
```
Applied **fix A**: `CpAIFieldWorker.lua` line ~276, changed the `Cutter` check from
`hasImplementWithSpecialization` (depth-1) to `hasChildVehicleWithSpecialization`
(full tree). Chosen over B because it keys off the actual header being present and
makes the LH II behave identically to a self-propelled forage harvester (whose
header is a direct child). `getCanStartCpFieldWork` is a runtime HUD query, not a
load-time function, so no load-crash risk. Verified in-game: flag flipped to true,
no errors, fieldwork/course options appear in the HUD.

Minor known edge (accepted): recursive Cutter would also report fieldwork-capable
for a tractor hauling a loose header on a trailer with no harvester — rare,
harmless (starting it just does nothing useful).
</content>
