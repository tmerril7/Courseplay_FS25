# Feature: fast getaway — full chaser exits to the AutoDrive network at full speed

**Status:** IMPLEMENTED 2026-07-19, needs in-game verification.
**Supersedes:** BUG-chaser-fullreturn-weird-path.md (the drive-back-to-start weirdness).

## Problem (Travis, observed in-game)
When a chaser fills up it:
1. pauses/creeps — reverses 15 m from the harvester at `reverseSpeed` (default **5 km/h**,
   ~11 s), stalling the follower chaser's takeover,
2. stops dead while the pathfinder plans (`WAITING_FOR_PATHFINDER`, speed 0),
3. drives a often-weird course **back to the job start position** at `fieldSpeed`
   (default 20 km/h) — even when the unload destination is the opposite direction,
4. only there stops the CP job so AutoDrive can take over — and AD then does its own
   stop-and-replan (`ExitFieldTask`) if the start position is >30 m from the network.

## Key insight (from mapping both mods)
AD does **not** need the vehicle at the start position. `onCpFull` →
`AutoDrive:handleCPFieldWorker` (AD ExternalInterface.lua:474) starts the vehicle's AD
mode **from wherever it physically is**. And if the vehicle is **≤30 m from the waypoint
network**, `PickupAndDeliverMode` STATE_INIT skips `ExitFieldTask` entirely and
`UnloadAtDestinationTask:setUp` goes straight to `drivePathModule:setPathTo(destination)`
— no planning stop, immediate on-graph driving. The whole drive-back-to-start is CP-side
legacy. (`getIsCpActive()` is already false when the event fires — Giants `AIJob.stop`
runs before `raiseEvent` in `CpAIJob:stop`, CpAIJob.lua:159-161 — so AD won't take the
`STATE_EXIT_FIELD` branch on us.)

## Design
When the trailer is full (and no field-unload / auger-wagon / Giants-unload configured),
CP now plans a **getaway course** directly to the first waypoint of the exact on-graph
route AD will drive to its unload destination, drives it at **full speed** (cruise
control max, not fieldSpeed), and stops the CP job ~1.5 vehicle lengths short of that
waypoint, aligned with the route direction. AD takes over seamlessly and rolls straight
onto the road.

Getaway target computation (all read from AD cross-mod via the `FS25_AutoDrive` mod
environment — same access pattern as `Courseplay.lua:123` — wrapped in pcall, any
failure ⇒ legacy behavior):
- Eligibility mirror of AD's `handleCPFieldWorker` gates: `vehicle.ad.stateModule` not
  active, `getStartHelper()` true, `getUsedHelper() == ADStateModule.HELPER_CP`, mode ∈
  `AutoDrive.modesToStartFromCP` (2/4/5), `getSecondWayPoint()` valid. If AD wouldn't
  take over, we must NOT strand the vehicle at the field edge ⇒ legacy.
- `closestId = vehicle:getClosestWayPoint()` (AD vehicle method, Specialization.lua:75)
  then `route = ADGraphManager:pathFromTo(closestId, secondWayPoint)` (on-graph
  Dijkstra, respects one-way edges).
- Goal pose = `route[1]` position, heading `route[1]→route[2]` via
  `MathUtil.getYRotationFromDirection`. Already ≤20 m from network ⇒ skip pathfinding,
  hand off on the spot. >500 m from network ⇒ legacy (pathfinder range sanity).
- CP pathfind with the same context as the old drive-back (default off-field penalty +
  fruit avoidance + existing retry ladder that relaxes penalties), goal zOffset
  −1.5×vehicle length so we stop short of the road, NO appended straight segment.
  Give-up cascade: getaway fails ⇒ legacy inverted-start pathfind ⇒ hand off in place.

## Changes (all in AIDriveStrategyUnloadCombine.lua)
1. New state `DRIVING_TO_GETAWAY_WHEN_FULL`, driven at `getCruiseControlMaxSpeed()`
   (full throttle; no curve slow-down exists in this strategy — watch in-game).
2. `startUnloadingTrailers()` trailer branch tries `startGetawayToAutoDrive()` before
   the inverted-start-marker legacy path.
3. `findAutoDriveGetawayTarget()` (pcall-guarded AD queries), `startGetawayToAutoDrive()`,
   `onPathfindingDoneToGetaway()`, `onPathfindingFailedToGetaway()` (falls back to
   legacy instead of stopping the job), arrival branch in `onLastWaypointPassed` →
   `onTrailerFull()` (unchanged handoff: `stopCurrentAIJob(AIMessageErrorIsFull)`).
4. Peel-off reverse (`MOVING_BACK_WITH_TRAILER_FULL`) now `min(2×reverseSpeed, 12)`
   km/h instead of `reverseSpeed` — halves the "pause" before the follower can take
   the pipe. Other reverse states untouched.

## Interactions checked
- 2-chaser convoy: `releaseCombine()` still fires before the reverse, so the follower
  is called immediately; faster reverse + immediate hard acceleration clears the lane
  sooner. Return trip unchanged: AD unloads, drives back to first marker, hands to CP
  (`passToExternalMod_CP` needs <30 m to *first* marker — untouched), far-join staging
  re-engages.
- "Drive unload now" and the 85% idle threshold funnel through the same
  `startUnloadingTrailers()` ⇒ they get the getaway too.
- Giants unload (`useGiantsUnload`), field unload, auger wagons: excluded, legacy paths.
- Stock AD works (no AD-fork change needed). No AD installed / CP-only start / wrong AD
  mode ⇒ eligibility fails ⇒ exact legacy behavior.

## Known upstream-AD bug found while mapping (not fixed here)
`AutoDrive:GetClosestPointToLocation` (AD ExternalInterface.lua:96) has an inverted
guard (`getWayPointsCount() < 1` should be `>= 1`) — it always returns −1 on any real
map, so `GetPath`'s fallback never works. We don't use it (we use
`vehicle:getClosestWayPoint()`), but worth fixing in the AD fork someday.

## In-game verification checklist
- Chaser fills mid-field → reverses clear at ~10 km/h → accelerates hard on a course
  toward the road → CP job ends near the network → AD drives off immediately (no pause,
  no drive to start marker).
- Follower chaser takes the pipe noticeably sooner.
- Fallbacks: AD HUD mode ≠ pickup&deliver/load/unload ⇒ old drive-to-start behavior.
- Watch: cornering at full speed with a full trailer (tipping/skid), fences at the
  field boundary (pathfinder should route around; retry ladder relaxes penalties).
