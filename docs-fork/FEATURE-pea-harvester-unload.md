# Pea harvester (Oxbo EPD 540E) chaser support — straight-only unload

Date: 2026-07-25. Branch: fork/crash-fixes. Status: round 2 after first in-game test (2026-07-26).

## Round 1 in-game test results (Travis, 2026-07-26)

Worked: display tag switched to "CP: Unload Pea Harvester" while actively serving the Oxbo
(reverts to "CP: Unload Combine" while idle — expected, it keys on the active target); lane
approach + on-the-move unloading worked; stopped-full pull-back unload (pipe-in-fruit side) worked.

Problems → round 2 fixes (same file sections as round 1):
1. First engagement only happened after the harvester stopped full and called — moving rendezvous
   were being rejected on pipe-in-fruit rows and the call threshold (callUnloaderPercent) was too
   high for the small 3730 l bunker. FIX: `straightUnloadCallPercent=30` caps the effective call
   threshold (estimateDistanceUntilFull), and `findNextStraightUnloadRowIx()` rescues rejected/
   near-row-end rendezvous by scanning up to 3 rows ahead for a fruit-free row long enough
   (meet at rowStart+4 so the harvester can settle after the turn first).
2. Break-off didn't create enough separation; the harvester bumped the chaser during the turn.
   FIX: two-stage break-off (speed−8 outside 18 m of the row end, full stop inside
   `straightUnloadHoldOffDistance=18`), and at turn start the chaser now reverses 25 m with a
   +10 m dz exit margin (`startMovingBackFromCombine` grew courseLength/dzExit params,
   MOVING_BACK honors `dzExit`) instead of the default stop-in-place. If the trailer is above
   the full threshold it leaves via the normal full-trailer path instead.
3. (Grass convoy, unrelated to peas) full chaser reversed into the staged follower. FIX: both
   full-trailer exits (`changeToUnloadWhenTrailerFull`, `onUnloadingMovingCombineFinished`)
   skip the reverse and peel off forward straight into `startUnloadingTrailers()` (→ fast
   getaway) when `anotherUnloaderIsStagingBehind()` — solo chasers keep the old reverse.

## Problem

Two related failures when a CP chaser serves the Oxbo EPD 540E pea harvester:

1. **Chaser rams the harvester's back.** CP measures the pipe/discharge offset ONCE at vehicle
   load (`CpVehicleSettings:setPipeOffset` → `PipeController:measurePipeProperties`) by virtually
   unfolding the pipe. The EPD 540E's conveyor only deploys when a trailer is already inside its
   `trailerTrigger`; and even the *extended* discharge node sits at only **x = 2.68 m** left of
   centerline — inside the lane a 4.15 m-wide harvester + trailer need. Whatever gets measured,
   the chaser converges on a lane that overlaps the machine. The in-game unload works via a
   downward discharge raycast (`maxDistance="6"`, `useRaycastHitPosition`), so the trailer lane
   just needs its inner half under the discharge node — the correct lane is
   `halfHarvesterWidth (2.08) + halfTrailerWidth (~1.4) + clearance ≈ 3.8 m`.
2. **It can't unload through turns.** The conveyor retracts when the trailer leaves the trigger
   (`closePipeAfterUnload` already set) and only deploys in position, so unloading must happen on
   straight sections only; the chaser must be out of the way for headland turnarounds.

## Geometry facts (from game data, epd540E.xml / .i3d)

- width 4.15 m, working width 3.75 m, bunker 3730 l (pea), crawler harvester
- discharge node extended: x=+2.68 (left), z=+2.08, y=3.41 (root-relative)
- folded: x≈1.25; pipe = 45°→0° Z-rotation, animation "pipeAnimation", states num=2 unloading=2
- trailerTrigger at x=2.8 left — a trailer at the 3.8 m lane intersects it

## Changes

### config/VehicleConfigurations.xml
- New attribute `unloadOffsetZ` (FLOAT) — symmetric to existing `unloadOffsetX`, applied in
  `PipeController:measurePipeProperties` (which also now recomputes `pipeOnLeftSide` after overrides).
- New attribute `straightUnloadOnly` (BOOL) — marks harvesters that can only be unloaded beside on
  straights. **Behavior is gated entirely on this per-vehicle flag; all other harvesters unchanged.**
- `epd540E.xml` entry: added `unloadOffsetX="3.8"`, `straightUnloadOnly="true"`.

### AIDriveStrategyCombineCourse.lua
- Constants: `straightUnloadBreakOffDistance=35`, `straightUnloadMinRadius=70`,
  `straightUnloadLookAheadDistance=20`.
- `isStraightUnloadOnly()` — cached `g_vehicleConfigurations:getRecursively(vehicle,'straightUnloadOnly')`.
- `isSafeToUnloadOnStraight()` — false while turning / on temp course / `dToNextTurn < 35` /
  `getMinRadiusWithinDistance(ix,20) < 70`. Always true for normal harvesters.
- `isReadyToUnload()` — for straight-only harvesters uses `isSafeToUnloadOnStraight()` instead of the
  hard-coded `isCloseToNextTurn(10)`. Gates rendezvous/unload start.
- `findBestWaypointToUnloadOnUpDownRows()` — for straight-only, a rendezvous landing within
  35+30 m of the row end is pushed to `nextRowStartIx+2` (meet on the next straight) when the next
  row is long enough, instead of being squeezed in before the turn.

### AIDriveStrategyUnloadCombine.lua (unloadMovingCombine)
- **Break-off**: while unloading, when `not isSafeToUnloadOnStraight()` and combine not yet turning,
  ease off to `combine speed − 5 km/h` → chaser falls behind, leaves the trigger, conveyor retracts
  before the row end.
- **Turn**: when the straight-only harvester starts turning, go straight to
  `onUnloadingMovingCombineFinished()` (existing give-room machinery: `MOVING_BACK` /
  `MOVING_BACK_FOR_HEADLAND_TURN`) instead of parking beside it — the pea harvester will NOT hold
  in the turn (`shouldHoldInTurnManeuver` only holds while discharging).
- **Rejoin**: existing machinery — `MOVING_BACK` exits once the combine is ahead →
  `startWaitingForSomethingToDo` → combine calls again → rendezvous lands on the next straight
  (per the combine-side changes above).

### Display text
- `AIDriveStrategyUnloadCombine.getCustomJobDisplayText(vehicle)` (static): returns
  "CP: Unload Pea Harvester" when the vehicle's unloader strategy is serving a straight-only
  harvester whose fill type is PEA; nil otherwise (incl. MP clients → fallback).
- Used by `CpBaseHud` (selected-job button, the "CP: unload combine" text Travis sees) and
  `CpAIJobCombineUnloader:getDescription()` (AI worker list).
- New translation key `CP_job_peaHarvesterUnload` in MasterTranslations + all 27 translation files
  (en text everywhere, de translated — matches what the translations CI would generate).

## Tuning without rebuild

`unloadOffsetX/Z` can be hot-tuned in-game: put an override in
`Documents/My Games/FarmingSimulator2025/modSettings/FS25_Courseplay/vehicleConfigurations.xml`
(`<Vehicle name="epd540E.xml" unloadOffsetX="..."/>`), run console `cpVehicleConfigurationsReload`,
then re-attach/reload the vehicle (offset is re-measured on load/attach). Break-off distances are
constants in AIDriveStrategyCombineCourse for now.

## In-game verification checklist

1. Start EPD 540E on a pea field with CP fieldwork; chaser (tractor+trailer) on unloader job.
2. HUD on chaser shows "CP: Unload Pea Harvester" once it's serving the Oxbo.
3. Approach: chaser pulls into a lane ~3.8 m left of the harvester centerline — no contact,
   conveyor deploys when trailer arrives, peas land in trailer. If lateral is off, tune
   `unloadOffsetX` (bigger = further out); if fore/aft off, add `unloadOffsetZ`.
4. ~35 m before the row end the chaser drops back; conveyor retracts; harvester turns unhindered
   (chaser reverses/waits clear of the turn).
5. After the turn, chaser re-engages on the new row (pathfinds around, no crossing of the
   harvester's turn path) and resumes unloading on the straight.
6. Trailer full mid-row → normal full-trailer exit (fast getaway) unaffected.
7. Regression: a normal combine + chaser still behaves as before (flag off ⇒ no behavior change).

## Known limitations / later

- `Course:getDistanceFromLastTurn()` is dead upstream (enrichWaypointData writes `dFromLastTurn`
  onto the Course, not waypoints) — not needed by this design, but worth fixing someday.
- If the field is worked toward the pipe side, the chaser's hold-back spot can be on the next
  unharvested row; pipe-in-fruit logic prevents unload there but positioning may need polish.
- Break-off is distance-based, not speed-based; 35 m assumes ≤ ~12 km/h harvest speed.
- MP: custom HUD text falls back to the standard text on clients (unload target is server-only).
