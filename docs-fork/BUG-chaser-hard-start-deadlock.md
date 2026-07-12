# Bug: chaser abandons the job from an awkward start position (chopper follow)

**Status:** OPEN — captured 2026-07-12, to fix later. Found while testing the
chopper auto-unload feature (see FEATURE-chopper-auto-unload.md).

## Symptom
Starting the combine-unloader chaser from a *difficult* position (wrong heading,
close to the harvester, already part-full) the chaser cannot recover: it reaches the
harvester, immediately gives up, and the harvester then waits forever
(`findUnloader: no idle unloader found`) because the chaser has stopped its job.

## Log evidence (front-mounted LH II chopper + AgroStar chaser)
```
AgroStar (fill 50.2%, d=16.8, same direction FALSE) -> called
  WAITING_FOR_PATHFINDER -> DRIVING_TO_MOVING_COMBINE
  "Close enough to moving combine, copy combine course and follow"
  UNLOADING_MOVING_COMBINE
  "Deadlock situation detected while unloading moving chopper."   <-- fires instantly
  Radium 255 back distance -11
  MOVING_BACK -> "Stop backing up"
  Rendezvous ... cancelled -> IDLE -> "CP combine unloader task stopped."
8R 410: WAITING_FOR_UNLOAD_ON_FIELD: "findUnloader: no idle unloader found"  (forever)
```

## Root cause
`AIDriveStrategyUnloadCombine:unloadMovingChopper()` (~line 707) calls
`isInDeadlock()` (~675):
```lua
return self.inDeadlock:get(
    combineStrategy:isWaitingForUnload() and AIUtil.isStopped(self.vehicle), 10000)
```
A `CpDelayedBoolean` that becomes true once *(harvester is waiting for unload) AND
(chaser is stopped)* has held continuously for 10 s. From an awkward start the chaser
spends the approach effectively stopped while the harvester is waiting, so that timer
is already elapsed the moment it enters `UNLOADING_MOVING_COMBINE` -> deadlock trips
immediately. The recovery (`startMovingBackFromCombine` -> `MOVING_BACK`) backs up a
couple of meters, then bails to IDLE and the whole unloader task stops instead of
re-approaching.

## Interaction with our feature (important)
Our chopper auto-unload change routes choppers into `UNLOADING_MOVING_COMBINE` *from a
stopped harvester* (by design). That makes the deadlock precondition — "harvester
waiting + chaser stopped" — the normal state right at engagement, so this 10 s timer
is far more likely to trip than before. The good/easy start positions work because the
chaser reaches the pipe and the harvester resumes before 10 s; a slow/awkward approach
crosses the threshold.

## Fix ideas (later)
- Don't count the initial engagement/approach as deadlock: reset `inDeadlock` (or
  gate it) while the chaser is still getting into position for the first time
  (e.g. until it has been under the pipe once, or until the harvester has resumed).
- Make the recovery re-approach (pathfind to the rendezvous again) instead of bailing
  to IDLE + stopping the task. Right now a single MOVING_BACK then giving up strands
  the harvester.
- Consider requiring the chaser to be reasonably aligned/behind before entering
  `UNLOADING_MOVING_COMBINE` for choppers (a light version of the pose gate we bypass),
  so a wrong-heading start does a proper re-approach first.

## Repro
Start the chaser from a position off to the side / facing away from the harvester,
part-full, within ~20 m. Easy/behind start positions do not trigger it.
</content>
