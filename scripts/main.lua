-- WarAversionCN (UncivCN 5.0.1.4)
-- War Aversion system using Variables.json + GlobalUniques.unitUniques + O(1) Combat Hook.
-- Engine contract: every hook receives a single argument `ctx`.

local T1 = 24
local T2 = 48
local T3 = 72
local T4 = 96
local DIVISOR = 6
local STEP_PCT = 2
local WAR_TURN_DELTA = 1
local PEACE_TURN_DELTA = -1
local UNIT_LOST_DELTA = 2
local ENEMY_KILLED_DELTA = -1
local CITY_CONQUERED_DELTA = -15
local NOTIFY_ENABLED = true

local function getTier(val)
    if val >= T4 then return 4 end
    if val >= T3 then return 3 end
    if val >= T2 then return 2 end
    if val >= T1 then return 1 end
    return 0
end

local function applyDelta(civ, delta)
    if civ == nil or not civ.isMajorCiv or delta == 0 then
        return
    end
    local prev = civ.getVariable("WarAversion")
    local prevTier = getTier(prev)
    civ.addVariable("WarAversion", delta)
    if NOTIFY_ENABLED then
        local curr = civ.getVariable("WarAversion")
        local currTier = getTier(curr)
        if currTier > prevTier then
            civ.addNotification("War Aversion reached Tier " .. tostring(currTier) .. " (" .. tostring(curr) .. "): escalating civil penalties active.")
        elseif currTier < prevTier then
            civ.addNotification("War Aversion eased to Tier " .. tostring(currTier) .. " (" .. tostring(curr) .. ").")
        end
    end
end

-- Fires once per civ turn start via GlobalUniques.json
function onTurnStart(ctx)
    local civ = ctx.civ
    if not civ.isMajorCiv then
        return true
    end
    if ctx.evaluateConditional("when at war") then
        applyDelta(civ, WAR_TURN_DELTA)
    else
        applyDelta(civ, PEACE_TURN_DELTA)
    end
    return true
end

-- Fires on non-civilian combat defeat via GlobalUniques.unitUniques (<upon being defeated>)
-- Handles both friendly loss (+2) and enemy kill (-1) with zero disband false positives.
function onUnitDefeated(ctx)
    local loser = ctx.civ
    local killer = ctx.otherCiv
    if loser ~= nil and loser.isMajorCiv then
        applyDelta(loser, UNIT_LOST_DELTA)
    end
    if killer ~= nil and killer.isMajorCiv and (loser == nil or killer.id ~= loser.id) then
        applyDelta(killer, ENEMY_KILLED_DELTA)
    end
    return true
end

-- Fires upon capturing a city via GlobalUniques.json (<upon conquering a city>)
function onCityConquered(ctx)
    local civ = ctx.civ
    if civ.isMajorCiv then
        applyDelta(civ, CITY_CONQUERED_DELTA)
    end
    return true
end

-- Pure O(1) combat hot-path hook (guarded by <when above [95] [WarAversion]>)
-- Replaces looped `for every` Strength evaluation with a single deterministic formula.
function modifyCombatStrength(ctx)
    local civ = ctx.civ
    if civ == nil or not civ.isMajorCiv then
        return nil
    end
    local wa = civ.getVariable("WarAversion")
    if wa < T4 then
        return nil
    end
    local penaltyFraction = (math.floor(wa / DIVISOR) * STEP_PCT) / 100.0
    local effectiveMod = math.max(0.25, ctx.modifier - penaltyFraction)
    return ctx.value * effectiveMod
end
