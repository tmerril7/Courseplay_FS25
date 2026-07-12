# Feature: auto side-by-side chaser for choppers (no manual intervention)

**Goal:** When harvesting with an always-discharge chopper (e.g. front-mounted LH II
forage harvester) and a separate "combine unloader" chaser, the chaser should
automatically pull up alongside and follow — instead of driving straight at the
stopped harvester and deadlocking. Previously the user had to manually drive the
chaser behind the harvester and wait for discharge before enabling it.

## Root cause (verified via DBG_UNLOAD_COMBINE logging on the real rig)
A chopper (`alwaysNeedsUnloader()` true) **stops** the instant it has no trailer
under the pipe → `UNLOADING_ON_FIELD/WAITING_FOR_UNLOAD_ON_FIELD`, speed 0. Being
stopped, `callUnloaderWhenNeeded` took the `isWaitingForUnload()` → nil-waypoint
"come to my location" branch → the chaser used `DRIVING_TO_COMBINE` →
`onLastWaypointPassed` gate `isOkToStartUnloadingCombine()` (needs a clean
"behind AND aligned" pose) **never passes** for a front-mounted/auto-aim pipe →
chaser goes IDLE → the two deadlock on proximity ("runs into the combine").

`DRIVING_TO_MOVING_COMBINE` has no such pose gate — on arrival it unconditionally
`startCourseFollowingCombine()` (side-by-side). So the fix routes choppers through
the moving-combine path even though they're momentarily stopped.

## The fix (2 edits, chopper-only, verified in-game)
1. `AIDriveStrategyCombineCourse:callUnloaderWhenNeeded()` — when the harvester is a
   chopper and waiting, find the nearest idle unloader (combine-based distance, valid
   while stopped) and **call it with a rendezvous waypoint** at the current course
   position, so it takes the moving-combine follow path instead of "come to me".
2. `AIDriveStrategyUnloadCombine:driveToMovingCombine()` — the guard that bails when
   "combine is now stopped and waiting for unload" now **exempts choppers**
   (`alwaysNeedsUnloader()`), which are *always* stopped until the chaser arrives;
   otherwise it livelocked (call → bail → cancel → repeat every 3 s).

The chopper's existing resume logic (WAITING_FOR_UNLOAD_ON_FIELD, line ~385:
"now have a trailer under the pipe, can continue working") closes the loop once the
chaser is under the pipe.

## Verified behavior (in-game, 2026-07-12)
Chaser: `DRIVING_TO_MOVING_COMBINE` → waits out the combine's turn →
`UNLOADING_MOVING_COMBINE` (offset ~0, behind the rear-firing auto-aim pipe) →
chopper resumes `WORKING` at 15 km/h → chaser fills → `DRIVING_BACK... WHEN_FULL`.
No manual intervention, no crash, no deadlock.

## Debugging path that got wrong twice (lessons)
- Round 1: my first attempt called `findUnloader(nil, waypoint)`, but that path does
  arithmetic on a nil distance unless `waypointIxWhenCallUnloader` is set (it isn't
  when stopped) → runtime crash. Fixed by finding via the combine-based call and only
  calling with the waypoint.
- The clean `willWaitForUnloadToFinish` one-liner I first hypothesized would NOT have
  worked — the failure was upstream in the approach, not the stopped/moving decision.
  The live log corrected the theory.

## Known residual: stutter (TODO — smoothing)
While following, the chopper periodically flips to "no fillable trailer under the
pipe" and steps back a waypoint, then recovers. Self-corrects every time (acceptable)
but not perfectly smooth — the chaser doesn't hold a rock-steady position under the
front-mounted pipe. Candidate area: following offset / pipe-target tracking for
rear-firing auto-aim pipes. Not yet addressed.
</content>
