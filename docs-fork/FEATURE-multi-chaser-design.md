# Feature design: 2-chaser convoy unloading a chopper/combine

**Goal (Travis):** Two combine-unloader chasers serving one harvester. A unloads under
the pipe; B follows close behind. When A fills and peels off to dump, B is already in
position and takes over seamlessly; A returns and now follows behind B. Cap at 2.

## Current architecture (confirmed)
- Combine has a SINGLE active slot `self.unloader` (CpTemporaryObject). `callUnloaderWhenNeeded`
  bails if it's filled, so only one chaser is ever assigned; the next is called only when
  the active one `releaseCombine()`s (fills/leaves).
- A chaser is passive: it targets a FIELD (`cpGetFieldPolygon`), and sits in `IDLE`
  (`setMaxSpeed(0)`, does nothing) until a combine's `findUnloader` picks it. `IDLE` chaser
  parks wherever it spawned -> the "wastes time far away" problem + slow handover.
- `activeUnloaders` (class registry) exists only for field-unload heap dedup, NOT convoy.
- No queue/convoy scaffolding for chasers. This is net-new behavior.

## Design: idle chaser STAGES behind the active chaser
Keep the combine's single active slot (the one under the pipe). Add a new "follower" mode
so a second, non-full chaser trails the active one instead of parking. Because it's already
close when the active one leaves, the existing `callUnloaderWhenNeeded` handover becomes
fast/seamless -- we mostly need to fix WHERE the waiting chaser waits.

### New state: FOLLOW_ACTIVE_UNLOADER (working name)
Entry (from IDLE, each check): if I'm not full AND there is an active CP harvester serving my
field (`AIDriveStrategyCombineCourse.isActiveCpCombine` + `isServingPosition`) AND that
harvester's active unloader (`combine:getCpDriveStrategy().unloader:get()`) is someone else
(not me), then enter FOLLOW_ACTIVE_UNLOADER targeting that harvester.

Behavior: follow the harvester's fieldwork course (reuse `setupFollowCourse`) at the same
side offset as the active chaser, but regulate speed to hold a target gap BEHIND the active
chaser (proximity sensor / distance-to-A), so B tucks in behind A. Do NOT try to get under
the pipe.

Exit: when the combine calls me (A released, `findUnloader` picks me) -> normal
DRIVING_TO_MOVING_COMBINE / UNLOADING_MOVING_COMBINE, already close = quick takeover. Or if
the harvester goes inactive / I'm sent to unload / I become full.

### Handover + role swap (largely emergent)
- A fills -> `changeToUnloadWhenTrailerFull` -> releaseCombine -> backs off -> dump/return.
- Combine slot frees -> `callUnloaderWhenNeeded` (our chopper branch) finds B (now close) ->
  B takes over.
- A returns empty -> IDLE -> sees B is now the active chaser -> stages behind B. Roles swapped.

## Incremental build (test each in-game)
1. **Staging only:** implement FOLLOW_ACTIVE_UNLOADER so B tucks in behind A and holds.
   Verify: start 2 chasers, B follows behind A instead of parking. (Biggest single win.)
2. **Handover:** verify A-full -> B-takeover is quick; tune gap so B doesn't block A's peel-off
   and slides into the pipe fast.
3. **Role swap:** verify A returns and stages behind B; repeat indefinitely.

## Risks / things to watch
- Collision/proximity between A and B (existing proximity controllers should help; tune gap).
- Don't let B block A's peel-off-to-dump path (A backs off when full).
- 2-cap: explicitly only one follower; a 3rd chaser stays IDLE (log it, don't silently drop).
- Interaction with the chopper deadlock detector (BUG-chaser-hard-start-deadlock.md) and the
  when-full return path (BUG-chaser-fullreturn-weird-path.md) -- both still open.
- Keep it chopper-and-tank-combine agnostic where possible, but test on the chopper rig.

## Status: IMPLEMENTED + verified in-game (2026-07-15)

Steps 1–3 all working: staging, handover, and role-swap (A fills → B takes over → A
re-stages behind B, repeating). Landed in AIDriveStrategyUnloadCombine.lua:

- **Staging (FOLLOW_ACTIVE_UNLOADER):** idle non-full chaser tucks in behind the active
  chaser instead of parking. `findActiveHarvesterToStageBehind` / `startStagingBehindActiveUnloader`
  / `stageBehindActiveUnloader`; 2-cap via `anotherUnloaderIsStagingBehind`; callable while
  staging via `isAllowedToBeCalled`.
- **Deadlock latch reset (fix):** `isInDeadlock` used a CpDelayedBoolean that latched true and
  was never reset across the MOVING_BACK→re-approach loop, so every handover re-tripped it in
  ~15 ms instead of 10 s. Fixed by resetting the latch at the top of `startCourseFollowingCombine`
  (the choke point every fresh takeover passes through). Deadlock trips: 32→0 in testing.
- **Anti-overtake gate (fix):** during a big turn B cut the inside of the corner and slingshot
  past A, parking in A's unload spot and jamming the convoy. B now measures progress along the
  HARVESTER's heading (project both chasers onto its direction node) and brakes if A isn't at
  least `overtakeMargin` (10 m) ahead — active during turns too. 27 guard saves, 0 jams in testing.
- **Self-heal (fix):** if B has actually overtaken and is jammed against a stuck A under a waiting
  harvester, B backs off 15 m (MOVING_BACK) and re-stages so A can reach the pipe. Safety net;
  never needed once the gate was in.

### Known limitation — re-engagement after full (NOT a convoy bug)
The re-stage-on-return cycle only closes automatically when a chaser empties WITHOUT ending its
CP job — i.e. auger-wagon self-unload or a field-unload position (both end in IDLE, where the
staging hook re-engages). A plain TRAILER chaser that fills drives back to its start position and
calls `onTrailerFull` → `stopCurrentAIJob` (base-mod behavior: hand off to AD/Giants/manual), so
it does not re-engage on return. To run the convoy continuously, use auger-wagon chasers with a
self-unload target, or set a field-unload position. See [[BUG-chaser-fullreturn-weird-path]].
</content>
