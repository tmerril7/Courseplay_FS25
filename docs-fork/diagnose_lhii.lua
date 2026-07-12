-- Courseplay fork diagnostic: why doesn't the LH II forage harvester enable fieldwork?
-- HOW TO RUN (in-game):
--   1. Attach the LH II + pickup header to the tractor, enter/select the tractor.
--   2. From the mod dir run:  reload.bat docs-fork\diagnose_lhii.lua
--      (that writes reload.xml next to it)
--   3. In the game console:   cpLoadFile
--   4. Read the output in the game log (log.txt) and paste it back.
--
-- It prints, for the current vehicle's whole attach tree, which of the
-- fieldwork-relevant specializations each unit has, plus the results of the
-- exact checks getCanStartCpFieldWork() uses.

local function log(fmt, ...)
    CpUtil.info('[LHII-DIAG] ' .. fmt, ...)
end

local v = CpUtil.getCurrentVehicle()
if v == nil then
    log('No current vehicle. Enter/select the tractor first.')
    return
end

-- Spec name -> global spec class (nil-safe: some may not exist)
local specsToCheck = {
    {'Combine',  Combine},
    {'Cutter',   Cutter},
    {'Pickup',   Pickup},
    {'ForageWagon', ForageWagon},
    {'Baler',    Baler},
    {'BaleLoader', BaleLoader},
    {'BaleWrapper', BaleWrapper},
    {'Mower',    Mower},
    {'Plow',     Plow},
    {'AIImplement', AIImplement},
    {'WorkArea', WorkArea},
}

local function specList(vehicle)
    local hits = {}
    for _, pair in ipairs(specsToCheck) do
        local name, cls = pair[1], pair[2]
        if cls and SpecializationUtil.hasSpecialization(cls, vehicle.specializations) then
            hits[#hits + 1] = name
        end
    end
    return #hits > 0 and table.concat(hits, ', ') or '(none of interest)'
end

local function nameOf(vehicle)
    return vehicle.getName and vehicle:getName() or (vehicle.configFileName or tostring(vehicle))
end

log('==== current vehicle: %s ====', nameOf(v))
log('root specs: %s', specList(v))

log('-- getAttachedImplements() (DEPTH 1 only; what hasImplementWithSpecialization sees) --')
for i, imp in ipairs(v:getAttachedImplements()) do
    log('  [%d] %s | specs: %s', i, nameOf(imp.object), specList(imp.object))
end

log('-- getChildVehicles() (FULL tree; what hasChildVehicleWithSpecialization sees) --')
for i, cv in ipairs(v:getChildVehicles()) do
    log('  {%d} %s | specs: %s', i, nameOf(cv), specList(cv))
end

log('-- the actual checks used by getCanStartCpFieldWork() --')
log('hasImplementWithSpecialization(Cutter)      [DEPTH1] = %s',
    tostring(Cutter and AIUtil.hasImplementWithSpecialization(v, Cutter)))
log('hasChildVehicleWithSpecialization(Cutter)   [FULL]   = %s',
    tostring(Cutter and AIUtil.hasChildVehicleWithSpecialization(v, Cutter)))
log('hasChildVehicleWithSpecialization(Combine)  [FULL]   = %s',
    tostring(Combine and AIUtil.hasChildVehicleWithSpecialization(v, Combine)))
log('hasChildVehicleWithSpecialization(ForageWagon)       = %s',
    tostring(ForageWagon and AIUtil.hasChildVehicleWithSpecialization(v, ForageWagon)))
log('hasCutterOnTrailerAttached                           = %s',
    tostring(AIUtil.hasCutterOnTrailerAttached(v)))
log('hasCutterAsTrailerAttached                           = %s',
    tostring(AIUtil.hasCutterAsTrailerAttached(v)))

log('-- outcomes --')
log('getCanStartFieldWork()   (Giants built-in) = %s',
    tostring(v.getCanStartFieldWork and v:getCanStartFieldWork()))
log('getCanStartCpFieldWork() (Courseplay)      = %s',
    tostring(v.getCanStartCpFieldWork and v:getCanStartCpFieldWork()))
log('==== end ====')
