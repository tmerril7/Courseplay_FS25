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

## Round 3 (2026-07-26, second test round feedback)

1. Grass: the follower-gated peel-off wasn't enough (follower can be in DRIVING_TO_STAGE, and a
   chopper stops immediately anyway when the full chaser leaves — reversing NEVER helps there).
   FIX: peel off forward whenever the harvester `alwaysNeedsUnloader()` (chopper) OR a follower
   is staged. Combines with a hopper and no follower still reverse.
2. Label flickered between pea/combine while the harvester's bunker continually bottomed out
   during on-the-move unload: `getFillType()` reads UNKNOWN on an empty fill unit. FIX:
   `getCustomJobDisplayText` latches the last non-UNKNOWN fill type per unloader strategy
   (`straightUnloadTargetFillType`).
3. Approach loop-around froze with the tractor's nose in the harvester's path (mutual proximity
   stop: harvester stops for us, we stop for it → jam until blocking timeout). FIX:
   `ignoreProximityObject` now ignores the target combine during the last 40 m of the
   DRIVING_TO_MOVING_COMBINE approach course (straight-unload-only targets only) so the chaser
   completes the loop until parallel — ending up ahead of the harvester is fine, it pipes out
   and the chaser picks up the pace alongside.
4. After unloading a stopped/pulled-back harvester, the chaser reversed (MOVING_BACK) — jams
   with a pivoting-front-axle (dolly) trailer. FIX: new `startMovingPastCombine()` — forward
   course parallel to the harvester, offset `width/2 + workWidth/2 + 2` to our side, via the
   existing MOVING_AWAY_FROM_OTHER_VEHICLE state (runs until laterally clear + out of the
   harvester's proximity, so its path back into the cut line is free). Straight-unload-only
   targets only; other combines keep the reverse.

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

## Round 4 (2026-07-26, from log.txt after a near-collision + jam)

Log showed the exact chain: with the bunker already over the eager 30% call threshold,
`callUnloaderWhenNeeded` computed **my ETE 0.0 s** — the meeting point degenerated to the
harvester's current position and the "too close" fallback pushed it only 25 m ahead. The chaser's
alignment loop crossed right in front of the moving harvester (braked 8.4→0, stopped at 1.5 m),
after 7 s of blocking the harvester's `requestToMoveOutOfWay` ABORTED the chaser's approach, and
the escape course ("not head on, not same direction" → straight ahead) drove the chaser along the
harvester's own path at reverse speed, "Still in proximity" for 22 s, rendezvous cancelled, repeat.

Fixes (straight-unload-only scoped unless noted):
1. `straightUnloadMinMeetDistance=50` — `findBestWaypointToUnloadOnUpDownRows` never returns a
   meet closer than 50 m ahead of the harvester; the ETE-pushed meet in `callUnloaderWhenNeeded`
   is re-validated through `findBestWaypointToUnload` (vanilla intentionally skips that).
2. `straightUnloadCallEteMargin=20` (vs vanilla 5) — call the unloader up to 20 s before the
   harvester's own ETE: arriving early, parking parallel in the lane and waiting is desired.
3. `isFinishingApproachToStraightUnloadHarvester()` (last 40 m of DRIVING_TO_MOVING_COMBINE):
   shared window for the proximity-ignore, plus NEW: `hold(2000)` the harvester while within
   30 m so it waits for the loop to finish, and `onBlockingVehicle` declines the abort in this
   window (we're already resolving it).
4. Escape courses: when angled ("not head on, not same direction") in front of a straight-only
   harvester, `onBlockingVehicle` now builds the parallel-with-xOffset course instead of straight
   ahead (straight ahead = down the harvester's path forever). `moveAwayFromOtherVehicle` drives
   forward escapes at field speed instead of reverse speed (general change, all unloaders).

## Round 5 (2026-07-26, stall diagnosed from log)

Deadlock: harvester fills to ~95% in the unbuffered last 35 m of the row (the break off makes this
COMMON), does the vanilla stop-at-row-end-and-wait (`WAITING_FOR_UNLOAD_BEFORE_STARTING_NEXT_ROW`),
calls the chaser — which arrives and is rejected: `isSafeToUnloadOnStraight` said "row end within
35 m" even though the harvester is STOPPED there waiting. Chaser goes IDLE 1.2 m from the target;
re-calls then fail ("no pathfinding needed" + same broken readiness check) while the failed call
keeps the chaser registered, so the harvester logs "already has an unloader assigned" forever.
FIX: `isSafeToUnloadOnStraight` returns true whenever the harvester is in `UNLOADING_ON_FIELD`
(stopped/maneuvering to be unloaded in place) — the break off distance only applies on the move.

## Round 6 (2026-07-26, screenshot + log: head-on staging + angled trailer)

1. **Cross-row meets are structurally unsafe — removed.** Log showed the near-row-end push
   repeatedly moving the meet to wp 2157 on the NEXT row. Geometry: on the next row (opposite
   direction) the chaser's unload lane — the pipe side, i.e. the just-cut side — IS the
   harvester's CURRENT row. A chaser pre-staged there parks head-on in the harvester's path by
   construction (screenshot confirmed). `findNextStraightUnloadRowIx` deleted; straight-only
   meets are now strictly same-row: `isTurnBetween(current, meet)` → nil, near-row-end → nil.
   After each turn, the 3 s call loop establishes a mid-row meet on the new row within seconds
   (same-row staging is safe: the lane there is the PREVIOUS row, already cut).
2. **Trailer left angled across the lane when staged early.** The chaser parked as soon as the
   tractor reached the wait point; the trailer was still angled from the alignment loop, standing
   in the harvester's path. FIX: approach-course extension is 3× (30 m) for straight-only
   targets, and the "combine is late" wait only stops when `isTrailerStraight(10°)` (new helper,
   trailer vs tractor heading dot product) — otherwise creeps at 5 km/h along the lane until the
   rig is straight (hard stop 2 m before course end regardless).

## Round 7 (2026-07-26) — pulled-back escape direction + v8.2.0.0 beta

The forward escape after a pulled-back unload pulled far enough ahead but turned the WRONG WAY:
side was chosen by "which side is the trailer on" = the pipe side (left) = exactly the corridor
the pulled-back harvester (backed out right, away from the pipe) drives through to cut back in.
FIX: `startMovingPastCombine` now parks IN LINE with the harvester's current backed-out position
(xOffset 0 relative to its direction node, minDz raised to 20): straight ahead on the harvested
ground, so the harvester pulls around on the pipe side to resume. Generalizes for any pipe side
since a pull-back is always away from the pipe.

Mod version bumped to **8.2.0.0** — Travis declared this the solid-beta cut.

## Round 8 (2026-07-26, log review before beta test)

1. **Missed opportunistic unloads.** Log: below 30% fill, the meeting point is estimated from the
   fill rate and lands beyond the row end (often clamped to the course's LAST waypoint, 2402) →
   rejected by the same-row rule; when fill crossed 30% mid-row the harvester was already inside
   the 115 m end zone (50 min-meet + 65 runway) → whole row's window missed → harvester filled →
   back-out stopped unload. FIX: `straightUnloadCallPercent` 30 → **15**. At/above 15% the seed is
   the current waypoint (negative liters-until-call → `getNextWaypointIxWithinDistance` returns
   the next wp immediately), so the call is attempted right at the start of every unloadable row.
2. **"Combine to unload lost during unload" wedge (upstream bug).** When the assigned harvester's
   driver goes away mid-approach (job stopped/finished), `hasToWaitForAssignedCombine()` parks the
   chaser at speed 0 and logs forever — upstream's recovery block is an empty stub. Seen in the
   log spamming every 5 s until the job was manually restarted (matches the wedge seen once in
   the convoy work too). FIX: 5 s grace (`combineLostTimer`, allows stop/restart transitions per
   the upstream comment), then `releaseCombine()` + `startWaitingForSomethingToDo()`.

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
