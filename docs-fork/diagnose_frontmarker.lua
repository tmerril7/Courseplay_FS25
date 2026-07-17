-- Front-mounted tool curve-tracking diagnostic.
-- HOW TO RUN (in-game):
--   1. Start CP fieldwork with the front cutter/forage header.
--   2. While the vehicle is FOLLOWING A CURVE (mid-arc, implement down, working), open the
--      console and run:  cpLoadFile
--   3. Run it a few times across the curve. Paste the [FMDIAG] lines from log.txt back.
--
-- It answers: is the front overhang detected (frontMarkerDistance)? does the course report
-- real curvature there (radius / heading change)? what offset is applied? and how far is the
-- front working point actually off the row centerline (ground truth, signed)?

local function log(fmt, ...) CpUtil.info('[FMDIAG] ' .. fmt, ...) end

local v = CpUtil.getCurrentVehicle()
if not v then log('No current vehicle. Enter the tractor.'); return end
log('==== vehicle: %s ====', CpUtil.getName(v))

local strat = v.getCpDriveStrategy and v:getCpDriveStrategy() or nil
if not strat then log('No CP drive strategy. Start CP fieldwork first, run while driving a curve.'); return end
log('strategy state: %s', tostring(strat.state and strat.state.name or '?'))

local fm = strat.frontMarkerDistance
local bm = strat.backMarkerDistance
log('frontMarkerDistance = %s m, backMarkerDistance = %s m', tostring(fm), tostring(bm))

-- offsets currently applied to the course
local course = strat.course
if course then
    local ox, oz = course:getOffset()
    log('APPLIED course offset X = %.3f, Z = %.3f', ox or -1, oz or -1)
end
log('components: frontOverhangOffset=%s tightTurnOffset=%s aiOffsetX=%s toolOffsetX=%s turningRadius=%s',
    tostring(strat.frontOverhangOffset), tostring(strat.tightTurnOffset), tostring(strat.aiOffsetX),
    tostring(strat.settings and strat.settings.toolOffsetX and strat.settings.toolOffsetX:getValue()),
    tostring(strat.turningRadius))

if not (course and fm) then return end

local ix = course:getCurrentWaypointIx()
local hix = course:getNextWaypointIxWithinDistance(ix, fm) or ix
log('currentIx=%s  headerIx(%.1fm ahead)=%s  numWp=%s', tostring(ix), fm, tostring(hix),
    tostring(course:getNumberOfWaypoints()))
log('calculatedRadius: at current=%s  at header=%s',
    tostring(course:getCalculatedRadiusAtIx(ix)), tostring(course:getCalculatedRadiusAtIx(hix)))

-- heading change over the header span (large-scale curvature, robust to dense waypoints)
local a0 = course:getWaypointAngleDeg(ix)
local a1 = course:getWaypointAngleDeg(hix)
if a0 and a1 then
    local dThetaDeg = math.deg(CpMathUtil.getDeltaAngle(math.rad(a1), math.rad(a0)))
    log('heading change over %.1fm span = %.2f deg  (>0 right-hand curve, <0 left-hand)', fm, dThetaDeg)
    -- offset the robust method would apply: fm * dTheta / 2
    log('  -> offset from heading-change method = %.3f m', fm * math.rad(dThetaDeg) / 2)
end

-- GROUND TRUTH: where is the front working point vs the true row centerline?
local dirNode = v:getAIDirectionNode()
local hx, hy, hz = localToWorld(dirNode, 0, 0, fm)   -- point fm straight ahead of the vehicle
local n = course:getNumberOfWaypoints()
local bestIx, bestD2 = ix, math.huge
for i = math.max(1, ix - 6), math.min(n, ix + 20) do
    local wp = course.waypoints[i]
    if wp then
        local ddx, ddz = hx - wp.x, hz - wp.z
        local d2 = ddx * ddx + ddz * ddz
        if d2 < bestD2 then bestD2 = d2; bestIx = i end
    end
end
local wp = course.waypoints[bestIx]
-- signed lateral in the offsetX convention (+left): axis (-dz, dx)
local lat = (hx - wp.x) * (-wp.dz) + (hz - wp.z) * (wp.dx)
log('FRONT POINT vs row centerline: nearest wp %d, lateral = %.3f m  (>0 right of row, <0 left of row)', bestIx, lat)
log('  (distance to that wp = %.2f m)', math.sqrt(bestD2))

-- also the vehicle's own tracking error against the (offset) course it follows
if strat.ppc and strat.ppc.crossTrackError then
    log('PPC crossTrackError (direction node vs offset course) = %.3f m', strat.ppc.crossTrackError)
end
