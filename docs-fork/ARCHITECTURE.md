# Courseplay FS25 — Architecture Digest

> Working notes for the `tmerril7/Courseplay_FS25` fork. Not upstream files.
> Written 2026-07-11. Based on fork synced to upstream v8.1.0.3 (0 ahead / 0 behind).

## What it is
A ~70K-LOC Lua mod for Farming Simulator 25 that auto-drives farm vehicles:
generates field-coverage courses, plans drivable paths, and steers vehicles
through fieldwork, harvesting, unloading, baling, and silo work. GPL v3.
Multiplayer supported. Runs on the Giants engine (no filesystem/modules; heavy
global namespace, XML-driven config).

## Entry point (`Courseplay.lua`)
- `g_Courseplay = Courseplay()` + `addModEventListener`. Giants calls
  `loadMap/update/draw/mouseEvent/keyEvent/deleteMap`.
- `Courseplay.register(typeManager)` is prepended to `TypeManager.finalizeTypes`
  — iterates every vehicle type and attaches CP specializations. **Runs
  synchronously over all types** (explicit "make async" TODO — startup cost).
- Global state: `g_Courseplay.globalSettings`, `g_customFieldManager`,
  `g_assignedCoursesManager`, `g_bunkerSiloManager`, `g_triggerManager`, etc.

## Subsystem map (LOC)
| Subsystem | LOC | Role |
|---|---|---|
| `scripts/ai` | 27K | Driving brain: strategies, jobs, tasks, controllers, turns |
| `scripts/courseGenerator` | 12K | Field boundary → coverage course (+ genetic optimizer) |
| `scripts/gui` | 8K | In-game menu, HUD, world plots |
| `scripts/pathfinder` | 5.7K | Hybrid A*, Dubins, Reeds-Shepp path planning |
| `scripts/specializations` | 5K | Hooks CP onto Giants vehicle types |
| `scripts/geometry`,`field`,`silo`,`trigger`,`editor` | ~6K | Support |

---

## 1. AI driving subsystem (`scripts/ai`)
**Control flow:** User starts CP → **Job** (`CpAIJob` extends Giants `AIJob`)
runs an ordered list of **Tasks** (`CpAITask*`). Each Task on `start()` spins up a
**Strategy** and stores it on the vehicle's cp spec. Giants calls the vehicle's
`getDriveData(dt,vX,vY,vZ)` each tick → `AIDriveStrategyCourse:getDriveData`
returns a goal point + speed from the **PurePursuitController** (`ppc`) → wheels turn.

- **Job → [Task, Task, …] → Strategy.** Job = user-configured work unit (owns
  `CpJobParameters`, availability checks, course gen). Tasks = sequential phases
  (state-machine skeleton). Strategy = per-frame brain.
- **Strategies** (all `CpObject`, root `AIDriveStrategyCourse`): FieldWorkCourse
  (till/sow/spray), CombineCourse (harvest + self-unload), PlowCourse,
  VineFieldWorkCourse, UnloadCombine (chase & unload combines), FindBales,
  BunkerSilo (compact/level), SiloLoader / ShovelSiloLoader, DriveToFieldWorkStart,
  AttachHeader.
- **Controllers** (`ai/controllers`, all extend `ImplementController`): abstract
  one implement — Combine, Cutter, Pipe, ForageWagon, Sowing, Baler, BaleLoader,
  BaleWrapper, Plow, Leveler, Sprayer, Shovel, Trailer, Motor, Foldable, autoloaders.
  Strategy raises `raiseControllerEvent`.
- **Turns** (`ai/turns`): `AITurn` base → KTurn, CourseTurn (→ CombineHeadlandTurn,
  CombinePocketHeadlandTurn, RecoveryTurn, VineTurn), FinishRowOnly. `TurnContext`
  computes geometry, `TurnManeuver`/`Corner` build paths. Reversing a towed
  implement/trailer: `AIReverseDriver` (uses an implement reference node in the PPC).

**Read first:** `strategies/AIDriveStrategyCourse.lua`, `jobs/CpAIJob.lua`,
`tasks/CpAITaskFieldWork.lua`, `PurePursuitController.lua`, `turns/AITurn.lua` + `TurnContext.lua`.

---

## 2. Course generator (`scripts/courseGenerator`)
Entry `CourseGeneratorInterface.lua` builds a `FieldworkContext` (working width,
turn radius, #headlands, row pattern, island handling) → constructs `FieldworkCourse`,
whose constructor runs the pipeline:
1. **Headlands** — offset the field `Polygon` inward N times → `Headland` objects;
   `HeadlandConnector` stitches them into one spiral path (outside→in or in→out).
2. **Center** (`Center.lua`, hardest file) — fill inside innermost headland with
   parallel `Row`s cut to boundary; non-convex fields/islands split into `Block`s.
3. **Row sequencing** — `RowPattern` (ALTERNATING/SKIP/SPIRAL/LANDS/RACETRACK).
4. **Block sequencing** — `genetic/BlockSequencer` uses `genetic/Genetic` (a GA)
   to optimize block visit order + entry corner, minimizing connecting-path length
   (Hameed/Bochtis field-coverage method).
5. `getPath()` concatenates headland + connecting paths + rows into one `Polyline`,
   each `Vertex` carrying `WaypointAttributes`.

**Variants** (subclass FieldworkCourse): TwoSided (narrow fields, headlands on 2
sides), Vine (rows from `VineScanner`), MultiVehicle (center at combined width,
offset per vehicle — author flags it "backwards", repeated TODOs).

**Field detection:** `FieldBoundaryDetector` (wraps Giants async API, returns field
+ islands), `FieldScanner` (legacy probe tracer, no island detection),
`VineScanner`, `CustomFieldManager` (persists user-drawn fields).

**Read first:** `FieldworkCourse.lua`, `Center.lua`, `geometry/Polygon.lua`/`Polyline.lua`,
`genetic/BlockSequencer.lua`.

---

## 3. Pathfinder (`scripts/pathfinder`)
`PathfinderInterface` implemented by: **HybridAStar** (core kinematically-drivable
`State3D` search respecting turn radius, coroutine-yielding, ~800 lines),
**AStar** (grid, fast, headingless), **Dubins**/**ReedsShepp** (+`ReedsSheppSolver`,
`AnalyticSolution` — analytic curve shots to close on goal), **JumpPointSearch**/
`GraphPathfinder`/`Dijkstra`. **HybridAStarWithAStarInTheMiddle** is what's used
in-game: fast A* in the middle, hybrid A* near the endpoints (drivable where it
matters, cheap elsewhere). `PathfinderConstraints` = per-node validity + penalty
(fruit/edge avoidance); `PathfinderCollisionDetector` = vehicle-shape overlap tests;
`PathfinderContext`/`PathfinderUtil` wire vehicle params.

**Read first:** `HybridAStarWithAStarInTheMiddle.lua`.

---

## 4. Specializations (`scripts/specializations`)
Standard Giants spec pattern (`registerFunctions/registerEventListeners/
registerOverwrittenFunctions`, hooking `onLoad/onUpdate/onReadStream/onWriteStream`).
- **CpAIImplement / CpAIWorker** — driver lifecycle base (`cpStartStopDriver`,
  `startCpWithStrategy`, `getCpDriveStrategy`). Everything extends this.
- **CpAIFieldWorker, CpAIBaleFinder, CpAICombineUnloader, CpAISiloLoaderWorker,
  CpAIBunkerSiloWorker** — concrete job specs.
- **CpCourseManager/CpCourseGenerator** — course storage & gen on the vehicle.
- **CpVehicleSettings, CpCourseGeneratorSettings** — per-vehicle setting containers.
- **CpHud, CpInfoTexts, CpShovelPositions** — UI/behavior. `CpGamePadHud` disabled (TODO 25).
Shop-config vehicles have CP specs stripped (`disableCpSpecsInShop`) to dodge onLoad crashes.

## 5. Settings — config-driven (`CpSettingsUtil.lua`)
Declared in `config/*SettingsSetup.xml` (Global/Vehicle/CourseGenerator/Hud), NOT
hardcoded. `loadSettingsFromSetup` parses the XML, instantiates setting classes by
`classType` (`AIParameterSettingList`, `AIParameterBooleanSetting`, …), populates
`class.settings`. Attributes: min/max/incremental, Values/Texts, unit,
`onChangeCallback`, `isUserSetting`, `isExpertModeOnly`, `isDisabled/isVisible`.
Also handles XML load/save, GUI binding, cloning. **Stringly-typed reflection** —
XML attribute names map to Lua callbacks/classes by string; no static checking.

## 6. GUI (`scripts/gui`)
- **Menu:** `CpInGameMenu` extends Giants `TabbedMenu`; layout from
  `config/gui/*`. Frames auto-build rows from settings tables.
- **HUD:** `CpBaseHud` composes swappable pages (`CpFieldworkHudPage`, …); picks by job type.
- **Plots:** world-overlay renderers (`CoursePlot`, `FieldPlot`, `BunkerSiloPlot`, `HeapPlot`).

## 7. Multiplayer sync (`scripts/events`)
Each `Event` subclass implements `writeStream/readStream/run` + static `sendEvent`.
Client → server → re-broadcast to other clients (excluding origin). Settings dirty
flags route through `VehicleSettingsEvent`, `GlobalSettingsEvent`, etc.
`VehicleUserSettingsEvent` persists per-user settings. Canonical pattern:
`events/VehicleSettingsEvent.lua`.

## Build / test / CI
- Tests: Lua 5.2.4 + `luaunit`, run in CI (`unit-test.yml`). Cover math, course
  generator, pathfinder graph. **AI subsystem untested** (needs engine).
- CI: `build-release.yml` (zips FS25_Courseplay.zip), `linter.yml`,
  `translations-update.yml`, `helpmenu-git-pages-update.yml`.
- Local iterate: `reload.bat` (in-game reload).
</content>
</invoke>
