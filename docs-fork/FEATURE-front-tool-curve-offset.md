# Feature: front-mounted tool curve offset

**Status:** implemented on `fork/crash-fixes`, awaiting in-game verify (2026-07-16).

## Problem
A rigidly front-mounted work implement (front 3-point cutter / forage-harvester
pickup header) reaches well ahead of the tractor. The PurePursuitController keeps
the **tractor's direction node** on the course, not the header. A point a distance
`d` ahead of the steering reference rides a *wider* arc than the reference on any
curve, so the header swings to the **outside** of the row and misses crop through
headland corners and curved rows.

## Geometry
If the direction node follows a circle of radius `R`, a point `d` ahead of it (along
the heading) rides a circle of radius `sqrt(R² + d²)` — outside by `≈ d²/2R`. To put
that point back on a row of radius `r`, drive the direction node on radius
`sqrt(r² - d²)`, i.e. offset the course **inward** by `r - sqrt(r² - d²)`.

Sub-meter in practice: `d=5 m` gives ~0.13 m at r=100, ~1.1 m at r=12 (headland
corner). Near-zero on straight rows (large `r`), so it self-disables where not needed.

## Implementation
Mirrors the existing towed-implement `tightTurnOffset` path (an additive lateral
course offset), but in the **opposite** direction: a towed tool cuts *inside* so CP
steers the tractor outside; a front tool swings *outside* so we steer it inside.

- `scripts/ai/util/AIUtil.lua` — new `AIUtil.calculateFrontMountedOffset(vehicle,
  vehicleTurningRadius, frontMarkerDistance, course, previousOffset)`. Uses the
  course's calculated radius + waypoint angle-delta (turn direction), same smoothing
  (`(x + 4·prev)/5`) and NaN guards as `calculateTightTurnOffset`. Only acts when
  `frontMarkerDistance ≥ 0.5` (front-mounted; rear tools are negative) and the
  computed offset ≥ 0.05 m.
- `AIDriveStrategyFieldWorkCourse:calculateTightTurnOffset()` (per `onWaypointChange`)
  also sets `self.frontOverhangOffset`; zeroed outside WORKING /
  DRIVING_TO_WORK_START_WAYPOINT.
- `AIDriveStrategyCourse:updateFieldworkOffset()` adds `self.frontOverhangOffset` to
  the course offset (applied every tick in `getDriveData`).
- `self.frontOverhangOffset` initialised to 0 in the FieldWorkCourse constructor.

Automatic, no new setting. Applies to any front-mounted header (also helps combines
on curved rows). Logs under `CpDebug.DBG_TURN`.

## Refinement: track the header, not the vehicle (2026-07-16)
In-game the offset helped but the header still missed on gentle arcs *while following
the course* (not headland turns). Two causes, both fixed in
`AIUtil.calculateFrontMountedOffset`:
- **Systematic lag**: radius was read at the vehicle's current waypoint, but the header
  is `frontMarkerDistance` ahead — it enters a bend a whole overhang before the vehicle,
  so the correction arrived an overhang-length late. Now we read curvature at the
  waypoint ~`frontMarkerDistance` ahead (`getNextWaypointIxWithinDistance`), i.e. where
  the header actually is (feed-forward). Turn-direction (left/right) is also taken there.
- **Sluggish smoothing**: was `(offset + 4·prev)/5` (80% carryover, ~10 waypoints to
  converge) copied from the towed-tool offset. This correction is small and
  geometry-based, so smoothing is now `(2·offset + prev)/3` (~2-3 waypoints).

Still recomputed per `onWaypointChange`. If it's slightly late entering bends, add a
small anticipation to the look-ahead distance; if it wobbles, restore heavier smoothing.

## Root cause of "still rides wide" (2026-07-17) — the offset was being discarded
In-game diagnostic (`docs-fork/diagnose_frontmarker.lua`, run via `reload.xml` +
`cpLoadFile`) on an 8R with a 6.9 m front forage header on a ~19 m-radius curve showed:
- `frontMarkerDistance = 6.89` (overhang detected fine), `calculatedRadius ≈ 19`
  (real curvature reported), `frontOverhangOffset = 1.28` with the **correct sign**
  (front point measured 1.37 m to the outside; +1.28 = inside is the right pull-back).
- **but `APPLIED course offset X = 0.000`** — the computed offset never reached the course.

Cause: a forage harvester runs `AIDriveStrategyCombineCourse`, which **overrides**
`updateFieldworkOffset` (line 322) and did not include the `frontOverhangOffset` term
(the base-class version at `AIDriveStrategyCourse.lua:680` had it, but the override
shadows it). So all the earlier geometry work was correct — it was simply thrown away
for this vehicle class. Fix: add `+ (self.frontOverhangOffset or 0)` to the fieldwork
branch of the combine override (`AIDriveStrategyCombineCourse.lua:327`). Left the
self-unload branch and the plow override alone (offset is 0 there anyway).

Lesson: `updateFieldworkOffset` is overridden per strategy (Combine, Plow) — any new
course-offset term must be added to every override, not just the base.

## Refinement: heading-change over the span, not single-point radius (2026-07-17)
With the combine fix the offset applied and centred well mid-curve, but a single-point
curvature read (radius at the header waypoint) switched on/off almost as a step:
- **entry** — full offset slammed on while the vehicle was still ~overhang metres back on
  the straight, so it drifted inward and cut inside the corner;
- **exit** — offset dropped while the vehicle was still in the arc, so the header lost
  support and strayed outside just before the bend ended.

`calculateFrontMountedOffset` now derives the offset from the HEADING CHANGE across the
span between the vehicle (`currentIx`) and the front working point (`headerIx`, one
overhang ahead): `offset = frontMarkerDistance * dTheta / 2` (dTheta = signed heading
change over the span; equals the steady-state `d²/2R` on a constant arc). This ramps
naturally — at the entry only the front of the span is curved so it eases in; at the exit
only the rear is, so it eases out. The sign now falls out of `dTheta` directly (no
separate left/right flip). Predicts ~1.47 m for the logged case vs the ~1.37 m measured
as needed. If it reads slightly hot mid-curve, apply an empirical trim factor (<1.0) like
the towed-tool offset's 0.75.

## Verify in-game
Rsync → restart. Field with a front cutter/forage header on a field with curved rows
or tight headland corners. Watch the header track the row through curves instead of
riding past the outside edge. Enable turn debug (DBG_TURN) to see the offset values.

## Follow-up: wider turn radius for the row-to-row turn (2026-07-16)
In-row offset was confirmed "pretty good / lining up better", but a long front
overhang still enters the *new* row off-centre coming out of a headland turn. CP
already targets the header longitudinally (`vehicleAtTurnEndNode` pulled back by
`frontMarkerDistance`, `TurnContext.lua:82`) and appends a straight aligned lead-in
(`appendEndingTurnCourse`, `TurnContext.lua:379`), but that lead-in is only
`frontMarker − backMarker` long — ~0 for a thin front header — so the vehicle comes
off the arc essentially at the row and is still straightening (curvature 1/R → 0)
when the header, several metres ahead, reaches the crop. The long lever arm turns a
small come-off transient into a visible miss.

Travis chose **widen the turn radius** (of the two levers offered).

Implementation:
- `AIUtil.getFrontMountedTurnRadius(baseRadius, frontMarkerDistance)` — widens the arc
  to `sqrt(baseR² + frontMarker²)` (the radius the header itself rides), capped at
  `1.5 × baseR` so tight fields still turn. Returns `baseRadius` unchanged for
  rear/towed tools or `frontMarker < 0.5`.
- `AITurn:init` (`scripts/ai/turns/AITurn.lua:60`) sets `self.turningRadius` from it.
  This feeds every maneuver's geometry (KTurn, CourseTurn → Dubins/ReedsShepp/
  headland-corner/pathfinder). **`AITurn.canMakeKTurn`'s local radius (line 152) is
  deliberately left at the true vehicle radius** so the turn-*type* decision is
  unchanged — only the chosen turn's arc gets gentler.

Trade-off (accepted): a wider maneuver radius than the course generator reserved for
headlands can make `canTurnOnField` fail more often → more reversing/pathfinder turns
on shallow-headland fields. The sqrt + 1.5× cap keep the increase modest (e.g. base
6 m, 5 m overhang → 7.8 m).

## If tuning needed
- Too aggressive / wobbly: reduce by scaling `offset` (e.g. `0.9 *`) like the tow-bar
  code's empirical `0.75`, or raise the 0.05 m deadband.
- Want it optional: promote to a `VehicleSettingsSetup.xml` boolean
  (`frontToolCurveOffset`) gating the `calculateFrontMountedOffset` call.
