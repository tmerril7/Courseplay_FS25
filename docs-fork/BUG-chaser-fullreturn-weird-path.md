# Bug (note, look later): chaser takes a weird/near-stuck path back when full

**Status:** ADDRESSED 2026-07-19 by FEATURE-fast-getaway.md — the full chaser now skips
the drive-back-to-start entirely when AutoDrive will take over, and drives a full-speed
getaway course to the AD network instead. The drive-back path remains only as fallback
(no AD, wrong AD mode, network too far, pathfinding failed). Original notes below.

## Symptom (Travis, observed in-game)
When the chaser trailer filled up, instead of a sensible route it took a **weird path
back to a "start position"** he didn't recognize (possibly the *start of the combine's
route*), and **nearly got stuck** on that path — the route looked unnecessary/bad.

## Likely mechanism
`AIDriveStrategyUnloadCombine` state `DRIVING_BACK_TO_START_POSITION_WHEN_FULL`
(decl ~line 147: "Drives to the start position with a trailer attached and gives
control to giants or AD there"). Set at ~line 2441 in the when-full handler. This is
the fallback the chaser uses when it's full and there is **no self-unload target**
(no trailer/heap to overload into, no AutoDrive handoff) and/or the `selfUnload`
vehicle setting isn't enabling an overload.

So on trailer-full the chaser pathfinds back to its recorded **start position** and
hands control back. Two things to check:
- Which "start position" it targets (the inverted goal / where the unloader was
  started) — it may be a poor/faraway spot, e.g. near the combine's route start.
- Why the pathfinder route there was bad / near-stuck (headland geometry, off-field
  penalty, reversing).

## To investigate later
- Confirm the `selfUnload` setting state during the test and whether a valid overload
  target (parked trailer/heap on the field) was available. If `selfUnload` was on but
  no target found, it falls through to drive-back-to-start — maybe the real fix is
  better self-unload target discovery, not the path back.
- Look at `getSelfUnloadTargetParameters` (~2472) and the drive-back-to-start target
  selection / pathfinding.
- Repro: fill the chaser with NO parked trailer/heap available on the field, watch the
  path it plots back.

Related: BUG-chaser-hard-start-deadlock.md, FEATURE-chopper-auto-unload.md (turn
drop-outs). All are chaser path/recovery robustness.
</content>
