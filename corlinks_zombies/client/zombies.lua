-- corlinks_zombies - client: zombie spawning (round tickets), AI, damage, sounds, health bars, kill credit
local TYPES = Config.Types
local ZGROUP = nil
local ATK_DICT, ATK_ANIM = 'melee@unarmed@streamed_variations', 'plyr_takedown_front_slap'

local cache = {}      -- every live zombie ped this client can see
local bars = {}       -- zombies to draw a health bar on
local climbing = {}  -- [ped] = time it started hanging on a yacht hull
local progress = {}  -- [ped] = { best = closest distance so far, t = when it last improved }
local lodSet = {}    -- [ped] = true once its draw distance was raised
local crumbOf = {}   -- [zombiePed] = { target, i }  (trail following on custom maps)
local tasked = {}     -- [ped] = { mode, t, target }   (AI on zombies we control)
local lastHit = {}    -- [ped] = time this zombie can hit us again
local counted = {}    -- [ped] = true once its death was handled for kill credit
local reported = {}   -- [ped] = true once we told the server it died (as owner)
local deadAt = {}     -- [ped] = time it died (for cleanup)
local silenced = {}   -- [ped] = true once its normal GTA voice is off
local nextGroan = {}  -- [ped] = time of its next groan
local huntBlips = {}  -- [ped] = blip
local rage = {}       -- [ped] = time until it is in a frenzy (screamers)
local exploded = {}   -- [ped] = true once a bloater went off
local screamed = {}   -- [ped] = true once a screamer screamed
local abilityCd = {}  -- [ped] = time the jumper / volatile can use its ability again

local function speedFor(ped, t, now)
    local sp = t.speed
    if Z.mut == 'bloodmoon' then sp = math.max(sp, 2.0) end
    if rage[ped] and now < rage[ped] then sp = math.min(2.3, sp * 1.3) end
    return sp
end

local function bloat(ped)
    if exploded[ped] then return end
    exploded[ped] = true
    local p = GetEntityCoords(ped)
    AddExplosion(p.x, p.y, p.z, 0, 0.45, true, false, 1.0)       -- hurts nearby zombies and players
    AddExplosion(p.x, p.y, p.z - 0.5, 21, 0.0, false, false, 0.0) -- toxic gas cloud
    if not IsPedDeadOrDying(ped, true) then SetEntityHealth(ped, 0) end
end

local function zType(ped)
    local s = Entity(ped).state.zdm
    return s and TYPES[s] and s or nil
end

local function zId(ped) return Entity(ped).state.zdm_id end

---------------------------------------------------------------------------
-- setup / cleanup
---------------------------------------------------------------------------
function Z.setup()
    local _, h = AddRelationshipGroup('ZDM_ZOMBIE')
    ZGROUP = h
    SetRelationshipBetweenGroups(5, h, GetHashKey('PLAYER'))
    SetRelationshipBetweenGroups(5, GetHashKey('PLAYER'), h)
    RequestAnimDict(ATK_DICT)
    for _, t in pairs(TYPES) do
        if t.clipset then RequestAnimSet(t.clipset) end
    end
end

local function clearHuntBlips()
    for ped, b in pairs(huntBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
        huntBlips[ped] = nil
    end
end

local function deleteZombie(ped)
    if DoesEntityExist(ped) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end
    if huntBlips[ped] and DoesBlipExist(huntBlips[ped]) then RemoveBlip(huntBlips[ped]) end
    climbing[ped], progress[ped], lodSet[ped], crumbOf[ped] = nil, nil, nil, nil
    tasked[ped], lastHit[ped], counted[ped], reported[ped], deadAt[ped], silenced[ped], nextGroan[ped], huntBlips[ped] =
        nil, nil, nil, nil, nil, nil, nil, nil
end

function Z.cleanup()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and Entity(ped).state.zdm and NetworkHasControlOfEntity(ped) then
            deleteZombie(ped)
        end
    end
    clearHuntBlips()
    cache, bars, tasked, lastHit, counted, reported, deadAt, silenced, nextGroan = {}, {}, {}, {}, {}, {}, {}, {}, {}
    rage, exploded, screamed = {}, {}, {}
    Z.cache = {}
    if Z.clearBlips then Z.clearBlips() end
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function lobbyPeds()
    -- everyone we can see is in our lobby (each map is its own private world)
    local list = {}
    for _, pl in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pl)
        -- Ghost ability: zombies ignore that player
        if p ~= 0 and DoesEntityExist(p) and not IsEntityDead(p) and not Player(GetPlayerServerId(pl)).state.zdm_ghost then list[#list + 1] = p end
    end
    return list
end

local function loadModel(name)
    local h = GetHashKey(name)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(h) and h or nil
end

-- floor under (x, y) close to height z (works inside custom MLOs where GTA has no ground data)
local function floorNear(x, y, z)
    local h = StartExpensiveSynchronousShapeTestLosProbe(x, y, z + 2.5, x, y, z - 4.0, 1 + 16, 0, 7)
    local _, hit, pos = GetShapeTestResult(h)
    if hit == 1 then return vector3(x, y, pos.z + 0.05) end
end

local function directSpot(from, minD, maxD, relaxed)
    local m = Config.Maps[Z.active.map] or {}
    local c = Z.active.center
    -- 1) the map's own spawn points, if it has any
    if m.spawns and #m.spawns > 0 then
        for _ = 1, 8 do
            local sp = m.spawns[math.random(#m.spawns)]
            if #(sp - from) > 12.0 and (relaxed or not IsSphereVisible(sp.x, sp.y, sp.z + 1.0, 1.0)) then return sp end
        end
        if relaxed then return m.spawns[math.random(#m.spawns)] end
    end
    -- 2) a spot on the same floor level as the player
    minD, maxD = math.min(minD, 18.0), math.min(maxD, 55.0)
    for _ = 1, 20 do
        local a = math.random() * math.pi * 2.0
        local d = minD + math.random() * (maxD - minD)
        local x, y = from.x + math.cos(a) * d, from.y + math.sin(a) * d
        if Z.edgeDist(vector3(x, y, 0.0), c) < (Z.active.radius or Config.BorderRadius) - 8.0 then
            local pos = floorNear(x, y, from.z)
            if pos then
                local wet, wz = GetWaterHeight(pos.x, pos.y, pos.z + 1.0)
                if wet and pos.z - wz < 1.5 then pos = nil end -- never on/in the water (yacht map)
            end
            if pos and (relaxed or not IsSphereVisible(pos.x, pos.y, pos.z + 1.0, 1.0)) then return pos end
        end
    end
end

local function findSpot(from, minD, maxD, relaxed)
    if Z.active.direct then
        local p = directSpot(from, minD, maxD, relaxed)
        if p or relaxed ~= nil then return p end
        return directSpot(from, minD, maxD, true)
    end
    local c = Z.active.center
    for _ = 1, 14 do
        local a = math.random() * math.pi * 2.0
        local d = minD + math.random() * (maxD - minD)
        local x, y = from.x + math.cos(a) * d, from.y + math.sin(a) * d
        if Z.edgeDist(vector3(x, y, 0.0), c) < (Z.active.radius or Config.BorderRadius) - 15.0 then
            local ok, pos = GetSafeCoordForPed(x, y, from.z, false, 16)
            if not ok then
                local found, z = GetGroundZFor_3dCoord(x, y, from.z + 60.0, false)
                if found then ok, pos = true, vector3(x, y, z) end
            end
            if ok then
                local wet, wz = GetWaterHeight(pos.x, pos.y, pos.z + 50.0)
                if wet and wz > pos.z then pos = vector3(pos.x, pos.y, wz) end -- open water: on the surface, not the seabed
            end
            if ok and math.abs(pos.z - from.z) < 45.0 and #(pos - from) > minD * 0.7
                and (relaxed or not IsSphereVisible(pos.x, pos.y, pos.z + 1.0, 1.2)) then
                return pos
            end
        end
    end
    -- tight maps (Grove): nothing hidden found - try again without the "out of sight" rule
    if relaxed == nil then return findSpot(from, minD, maxD, true) end
end

local function silence(ped)
    StopPedSpeaking(ped, true)
    DisablePedPainAudio(ped, true)
    StopCurrentPlayingAmbientSpeech(ped)
    silenced[ped] = true
end

local function spawnZombie(pos, tk)
    local t = TYPES[tk.type]
    local model = (t and t.models and loadModel(t.models[math.random(#t.models)])) or (t and t.model and loadModel(t.model)) or loadModel(Config.ZombieModels[math.random(#Config.ZombieModels)]) or loadModel(Config.ZombieFallback or 'u_m_y_zombie_01')
    if not model or not t then return false end
    local ped = CreatePed(t.special == 'hound' and 28 or 4, model, pos.x, pos.y, pos.z, math.random() * 360.0, true, true)
    if ped == 0 then return false end
    local wait = GetGameTimer() + 1000
    while not NetworkGetEntityIsNetworked(ped) and GetGameTimer() < wait do Wait(0) end
    SetModelAsNoLongerNeeded(model)
    SetEntityAsMissionEntity(ped, true, true)
    local vanilla = GetEntityModel(ped) == GetHashKey('u_m_y_zombie_01')
    if vanilla then
        SetPedRandomComponentVariation(ped, 0)
    else
        -- the mega pack keeps every zombie as a head variation: pick a valid one + skin
        local nd = GetNumberOfPedDrawableVariations(ped, 0)
        if nd > 1 then
            local d = math.random(0, nd - 1)
            local nt = GetNumberOfPedTextureVariations(ped, 0, d)
            if nt > 0 and IsPedComponentVariationValid(ped, 0, d, 0) then
                SetPedComponentVariation(ped, 0, d, math.random(0, nt - 1), 0)
            end
        end
    end
    if ZGROUP then SetPedRelationshipGroupHash(ped, ZGROUP) end
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedCanEvasiveDive(ped, false)
    SetPedDiesWhenInjured(ped, true)
    SetPedSuffersCriticalHits(ped, true)   -- headshots hurt
    SetPedConfigFlag(ped, 281, true)        -- no writhing on the floor
    SetPedDiesInWater(ped, false)           -- zombies swim after you
    SetPedDiesInstantlyInWater(ped, false)
    SetPedMaxTimeUnderwater(ped, 600.0)
    SetPedPathCanUseClimbovers(ped, true)
    SetPedCanPlayAmbientAnims(ped, false)
    silence(ped)                            -- zombies only make zombie noises
    RemoveAllPedWeapons(ped, true)
    local hp = tk.hp or t.health
    SetEntityMaxHealth(ped, hp + 100)
    SetEntityHealth(ped, hp + 100)
    SetPedArmour(ped, 0)
    if t.clipset and HasAnimSetLoaded(t.clipset) then SetPedMovementClipset(ped, t.clipset, 1.0) end
    if t.rate then SetPedMoveRateOverride(ped, t.rate) end
    if vanilla then -- blood decals on the pack's empty body parts can crash the game
        ApplyPedDamagePack(ped, 'BigHitByVehicle', 0.0, 9.0)
        ApplyPedDamagePack(ped, 'SCR_Dumpster', 0.0, 9.0)
    end
    local st = Entity(ped).state
    st:set('zdm', tk.type, true)
    st:set('zdm_id', tk.id, true)
    st:set('zdm_aggro', tk.hunt and true or false, true)
    if not tk.hunt then TaskWanderStandard(ped, 10.0, 10) end
    return true
end

---------------------------------------------------------------------------
-- cache refresh
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active then
            local list = {}
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not IsPedAPlayer(ped) and Entity(ped).state.zdm then
                    list[#list + 1] = ped
                    if not silenced[ped] then silence(ped) end
                    if not lodSet[ped] then
                        -- keep the full-detail zombie model at range (the pack's far-away LODs look broken)
                        lodSet[ped] = true
                        SetPedLodMultiplier(ped, Config.ZombieLod or 4.0)
                        SetEntityLodDist(ped, 400)
                    end
                end
            end
            cache = list
            Z.cache = list
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

-- tell the server which zombies we can still see (lost ones get recycled)
CreateThread(function()
    while true do
        Wait(4000)
        if Z.active then
            local ids = {}
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local id = zId(ped)
                    if id then ids[#ids + 1] = id end
                end
            end
            if #ids > 0 then TriggerServerEvent('zdm:seen', ids) end
        end
    end
end)

---------------------------------------------------------------------------
-- spawning: ask the server for this round's zombies, spawn them around me
---------------------------------------------------------------------------
CreateThread(function()
    local S = Config.Spawn
    while true do
        Wait(S.Interval)
        if Z.active and not Z.downed and Z.round and Z.round.phase == 'active' and Z.round.left > 0 then
            local mine = 0
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and not IsPedDeadOrDying(ped, true) then mine = mine + 1 end
            end
            local room = S.MaxPerPlayer - mine
            if room > 0 then TriggerServerEvent('zdm:want', room) end
        end
    end
end)

RegisterNetEvent('zdm:tickets', function(tickets)
    if not Z.active then
        for _, tk in ipairs(tickets) do TriggerServerEvent('zdm:lost', tk.id) end
        return
    end
    local S = Config.Spawn
    local me = GetEntityCoords(PlayerPedId())
    local used = {}
    for _, tk in ipairs(tickets) do
        -- every zombie gets its own spot, spread out around the player (no packs)
        local pos
        for _ = 1, 4 do
            local p = findSpot(me, S.MinDist, S.MaxDist)
            if p then
                local ok = true
                for _, u in ipairs(used) do if #(u - p) < 15.0 then ok = false break end end
                if ok then pos = p break end
                pos = pos or p
            end
        end
        if pos then used[#used + 1] = pos end
        if not (pos and Z.active and spawnZombie(pos, tk)) then
            TriggerServerEvent('zdm:lost', tk.id)
        end
        Wait(60)
    end
end)

---------------------------------------------------------------------------
-- water + yachts: swim straight at you, climb aboard
---------------------------------------------------------------------------

-- the yacht an entity is on (or right next to, with margin)
local function yachtAt(ent, margin)
    if not Z.yachts then return nil end
    local p = GetEntityCoords(ent)
    for _, y in ipairs(Z.yachts) do
        if DoesEntityExist(y) then
            local mn, mx = GetModelDimensions(GetEntityModel(y))
            local o = GetOffsetFromEntityGivenWorldCoords(y, p)
            if o.x > mn.x - margin and o.x < mx.x + margin and o.y > mn.y - margin and o.y < mx.y + margin
                and o.z > mn.z - 4.0 and o.z < mx.z + 3.0 then
                return y, o, mn, mx
            end
        end
    end
end

-- returns true if it handled this zombie this tick
local function waterChase(ped, target, t, td, now)
    local yacht = yachtAt(target, 0.0)
    local inWater = IsEntityInWater(ped) or IsPedSwimming(ped)
    if not yacht and not inWater and not IsEntityInWater(target) then climbing[ped] = nil return false end
    if td <= Config.AttackRange + 0.35 and not inWater then return false end -- close enough: normal attack
    -- climb onto the yacht
    if yacht and inWater then
        local y, o, mn, mx = yachtAt(ped, 3.0)
        if y == yacht then
            climbing[ped] = climbing[ped] or now
            if now - climbing[ped] > (Config.Yachts.ClimbSeconds or 1.2) * 1000 then
                climbing[ped] = nil
                local cx = math.max(mn.x + 1.0, math.min(mx.x - 1.0, o.x))
                local cy = math.max(mn.y + 1.5, math.min(mx.y - 1.5, o.y))
                local tz = GetEntityCoords(target).z
                local w = GetOffsetFromEntityInWorldCoords(yacht, cx, cy, 0.0)
                ClearPedTasksImmediately(ped)
                SetEntityCoords(ped, w.x, w.y, tz + 0.2, false, false, false, false)
                SetEntityHeading(ped, GetHeadingFromVector_2d(GetEntityCoords(target).x - w.x, GetEntityCoords(target).y - w.y))
                tasked[ped] = nil
                SendNUIMessage({ a = 'sfx', s = 'aggro', k = zType(ped) or 'walker', v = 0.7, p = 0.0 })
                return true
            end
            ClearPedTasks(ped) -- hanging on the side
            return true
        end
    end
    climbing[ped] = nil
    local tr = tasked[ped]
    if not tr or tr.mode ~= 'swim' or tr.target ~= target or now > tr.t then
        local tp = GetEntityCoords(target)
        TaskGoStraightToCoord(ped, tp.x, tp.y, tp.z, speedFor(ped, t, now), -1, 0.0, 0.5)
        tasked[ped] = { mode = 'swim', t = now + 800, target = target }
    end
    return true
end

---------------------------------------------------------------------------
-- stuck zombies: moved closer (out of sight) if they stop making progress
---------------------------------------------------------------------------

local function unstuck(ped, target, td, now)
    local U = Config.Unstuck
    if not U or not U.Enabled then return false end
    local pr = progress[ped]
    if not pr or td < pr.best - (U.MinProgress or 3.0) then
        progress[ped] = { best = td, t = now }
        return false
    end
    if td <= (U.MaxDist or 40.0) + 5.0 and HasEntityClearLosToEntity(target, ped, 17) then
        pr.t = now -- you can see it: don't teleport in front of you
        return false
    end
    if Z.active.direct and crumbOf[ped] then
        -- following your trail: it's progress as long as it keeps moving along it
        local here = GetEntityCoords(ped)
        if not pr.pos or #(here - pr.pos) > 3.0 then pr.pos, pr.t = here, now end
    end
    local wait = (Z.active.direct and (U.StuckSecondsCustom or 5) or (U.StuckSeconds or 9)) * 1000
    if now - pr.t < wait or climbing[ped] then return false end
    local tp = GetEntityCoords(target)
    for _ = 1, 6 do
        local spot = findSpot(tp, U.MinDist or 22.0, U.MaxDist or 40.0, false)
        if spot then
            ClearPedTasksImmediately(ped)
            SetEntityCoords(ped, spot.x, spot.y, spot.z, false, false, false, false)
            tasked[ped] = nil
            progress[ped] = { best = #(spot - tp), t = now }
            return true
        end
    end
    pr.t = now -- nowhere good right now, try again later
    return false
end

---------------------------------------------------------------------------
-- breadcrumb trails (custom MLO maps): every player's walked path, so zombies can
-- follow the exact route you took through doors, stairs and corridors
---------------------------------------------------------------------------
local trails = {}     -- [targetPed] = { n = newest index, first = oldest index, pts = { [i] = vec3 } }

local function losPoint(a, b)
    local h = StartExpensiveSynchronousShapeTestLosProbe(a.x, a.y, a.z + 0.6, b.x, b.y, b.z + 0.6, 1 + 16, 0, 4)
    local _, hit = GetShapeTestResult(h)
    return hit == 0
end

CreateThread(function()
    while true do
        if Z.active and Z.active.direct then
            for _, p in ipairs(lobbyPeds()) do
                local pos = GetEntityCoords(p)
                local tr = trails[p]
                if not tr then tr = { n = 0, first = 1, pts = {} }; trails[p] = tr end
                local last = tr.pts[tr.n]
                if not last or #(pos - last) > 1.6 then
                    tr.n = tr.n + 1
                    tr.pts[tr.n] = pos
                    while tr.n - tr.first > 160 do tr.pts[tr.first] = nil; tr.first = tr.first + 1 end
                end
            end
            Wait(200)
        else
            if next(trails) then trails = {} end
            Wait(1000)
        end
    end
end)

-- next point on the target's trail for this zombie (nil = no usable trail)
local function trailNext(ped, target, mp)
    local tr = trails[target]
    if not tr or tr.n == 0 then return nil end
    local c = crumbOf[ped]
    if c and c.target == target and tr.pts[c.i] then
        local pt = tr.pts[c.i]
        if #(mp - pt) < 1.7 then
            -- reached it: next crumb towards you, skipping ahead if a later one is in sight
            local nexti = math.min(tr.n, c.i + 1)
            for j = math.min(tr.n, c.i + 6), c.i + 2, -2 do
                if tr.pts[j] and losPoint(mp, tr.pts[j]) then nexti = j break end
            end
            c.i = nexti
        end
        return tr.pts[c.i]
    end
    -- the newest crumb it can see from where it stands
    local checks = 0
    for i = tr.n, math.max(tr.first, tr.n - 150), -4 do
        local pt = tr.pts[i]
        if pt and #(mp - pt) < 40.0 then
            checks = checks + 1
            if losPoint(mp, pt) then crumbOf[ped] = { target = target, i = i }; return pt end
            if checks >= 8 then break end
        end
    end
    -- nothing in sight: head for the closest crumb
    local best, bi = 1e9, nil
    for i = tr.first, tr.n, 3 do
        local pt = tr.pts[i]
        if pt then local d = #(mp - pt) if d < best then best, bi = d, i end end
    end
    if bi then crumbOf[ped] = { target = target, i = bi }; return tr.pts[bi] end
end

---------------------------------------------------------------------------
-- AI for the zombies this client controls
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active then
            local now = GetGameTimer()
            local targets = lobbyPeds()
            local hunt = Z.round and Z.round.hunt
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
                    if IsPedDeadOrDying(ped, true) then
                        if not reported[ped] then
                            reported[ped] = true
                            local id = zId(ped)
                            if id then TriggerServerEvent('zdm:zdead', id) end
                            if zType(ped) == 'bloater' then bloat(ped) end
                        end
                        deadAt[ped] = deadAt[ped] or now
                        if now - deadAt[ped] > 12000 then deleteZombie(ped) end
                    else
                        local key = zType(ped) or 'walker'
                        local t = TYPES[key]
                        local pos = GetEntityCoords(ped)
                        local target, td = nil, 1e9
                        for _, p in ipairs(targets) do
                            local d = #(GetEntityCoords(p) - pos)
                            if d < td then target, td = p, d end
                        end
                        if not target or td > Config.Spawn.DespawnDist then
                            local id = zId(ped)
                            if id then TriggerServerEvent('zdm:lost', id) end
                            deleteZombie(ped)
                        else
                            local st = Entity(ped).state
                            local aggro = hunt or st.zdm_aggro or td <= t.sight or (td < 90.0 and IsPedShooting(target)) or (rage[ped] and now < rage[ped])
                            if aggro and t.special == 'screamer' and not screamed[ped] and td <= t.sight then
                                screamed[ped] = true
                                ClearPedTasks(ped)
                                TaskPlayAnim(ped, ATK_DICT, ATK_ANIM, 8.0, -8.0, 1200, 0, 0.0, false, false, false)
                                TriggerServerEvent('zdm:scream', pos.x, pos.y, pos.z)
                            end
                            if aggro and t.special == 'bloater' and td <= 2.4 then
                                bloat(ped)
                                goto continue
                            end
                            -- special abilities
                            if aggro and t.special == 'jumper' and now > (abilityCd[ped] or 0) and not IsPedRagdoll(ped) then
                                local tp = GetEntityCoords(target)
                                local up = tp.z - pos.z
                                local flat = #(vector2(tp.x, tp.y) - vector2(pos.x, pos.y))
                                if up > (Config.Jumper.MinHeight or 1.6) and flat < (Config.Jumper.MaxRange or 14.0) and not IsPedInAnyVehicle(target, false) then
                                    abilityCd[ped] = now + (Config.Jumper.Cooldown or 3500)
                                    -- beast jump: enough lift to clear the height, carried forward onto the target
                                    local h = up + 2.2
                                    local vz = math.sqrt(2.0 * 9.81 * h)
                                    local tfl = vz / 9.81 + math.sqrt(2.0 * 2.2 / 9.81)
                                    local vx, vy = (tp.x - pos.x) / tfl, (tp.y - pos.y) / tfl
                                    ClearPedTasksImmediately(ped)
                                    SetPedCanRagdoll(ped, false)
                                    SetEntityVelocity(ped, vx, vy, vz)
                                    SetTimeout(2500, function() if DoesEntityExist(ped) then SetPedCanRagdoll(ped, true) end end)
                                    tasked[ped] = { mode = 'jump', t = now + 1400, target = target }
                                    SendNUIMessage({ a = 'sfx', s = 'aggro', k = 'runner', v = 0.6, p = 0.0 })
                                    goto continue
                                end
                            end
                            if tasked[ped] and tasked[ped].mode == 'jump' and now < tasked[ped].t then goto continue end
                            if aggro and t.special == 'volatile' and now > (abilityCd[ped] or 0) then
                                local V = Config.Volatile
                                if td >= (V.MinRange or 4.0) and td <= (V.MaxRange or 18.0) and HasEntityClearLosToEntity(ped, target, 17) then
                                    abilityCd[ped] = now + (V.Cooldown or 4500)
                                    ClearPedTasks(ped)
                                    TaskTurnPedToFaceEntity(ped, target, V.Windup or 650)
                                    tasked[ped] = { mode = 'spit', t = now + (V.Windup or 650) + 500, target = target }
                                    local victim = target
                                    SetTimeout(V.Windup or 650, function()
                                        if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) or not DoesEntityExist(victim) then return end
                                        local from = GetPedBoneCoords(ped, 31086, 0.15, 0.0, 0.0) -- mouth
                                        local to = GetEntityCoords(victim) -- aims where you are standing right now
                                        TriggerServerEvent('zdm:spit', from.x, from.y, from.z, to.x, to.y, to.z)
                                    end)
                                    goto continue
                                end
                            end
                            if tasked[ped] and tasked[ped].mode == 'spit' and now < tasked[ped].t then goto continue end
                            if aggro and td > Config.AttackRange + 2.0 and unstuck(ped, target, td, now) then
                                goto continue
                            end
                            if aggro and (Z.yachts and #Z.yachts > 0 or IsEntityInWater(ped) or IsEntityInWater(target)) and waterChase(ped, target, t, td, now) then
                                if not st.zdm_aggro then st:set('zdm_aggro', true, true) end
                                goto continue
                            end
                            if aggro then
                                if not st.zdm_aggro then st:set('zdm_aggro', true, true) end
                                local tr = tasked[ped]
                                if td <= Config.AttackRange + 0.35 + (IsPedInAnyVehicle(target, false) and 1.2 or 0.0) then
                                    if not tr or tr.mode ~= 'atk' or now > tr.t then
                                        TaskTurnPedToFaceEntity(ped, target, 200)
                                        if HasAnimDictLoaded(ATK_DICT) and t.special ~= 'hound' then
                                            TaskPlayAnim(ped, ATK_DICT, ATK_ANIM, 8.0, -8.0, 900, 0, 0.0, false, false, false)
                                        end
                                        tasked[ped] = { mode = 'atk', t = now + Config.AttackCooldown, target = target }
                                    end
                                elseif Z.active.direct then
                                    -- custom MLO maps: no GTA path data. If they can see you they come straight at you;
                                    -- if not, they follow the trail you walked (breadcrumbs), so they take the same route.
                                    local tr2 = tasked[ped]
                                    if not tr2 or tr2.mode ~= 'direct' or tr2.target ~= target or now > tr2.t then
                                        local mp2 = GetEntityCoords(ped)
                                        local tp = GetEntityCoords(target)
                                        local dest, crumb = tp, nil
                                        if td > 6.0 and not HasEntityClearLosToEntity(ped, target, 17) then
                                            crumb = trailNext(ped, target, mp2)
                                            if crumb then dest = crumb end
                                        else
                                            crumbOf[ped] = nil
                                        end
                                        local last = tr2 and tr2.mode == 'direct' and tr2.pos
                                        if last and #(mp2 - last) < 0.5 then
                                            -- blocked: step sideways (alternating sides), then carry on
                                            local dx, dy = dest.x - mp2.x, dest.y - mp2.y
                                            local l = math.max(0.01, math.sqrt(dx * dx + dy * dy))
                                            local side = (tr2.side or 1) * -1
                                            dest = vector3(mp2.x + (-dy / l) * 3.0 * side + (dx / l), mp2.y + (dx / l) * 3.0 * side + (dy / l), mp2.z)
                                            tasked[ped] = { mode = 'direct', t = now + 900, target = target, pos = mp2, side = side }
                                        else
                                            tasked[ped] = { mode = 'direct', t = now + (crumb and 450 or 650), target = target, pos = mp2, side = tr2 and tr2.side or 1 }
                                        end
                                        if t.clipset and HasAnimSetLoaded(t.clipset) then SetPedMovementClipset(ped, t.clipset, 1.0) end
                                        TaskGoStraightToCoord(ped, dest.x, dest.y, dest.z, speedFor(ped, t, now), -1, 0.0, 0.25)
                                    end
                                elseif not tr or tr.mode ~= 'chase' or tr.target ~= target or now > tr.t then
                                    if t.clipset and HasAnimSetLoaded(t.clipset) then SetPedMovementClipset(ped, t.clipset, 1.0) end
                                    TaskGoToEntity(ped, target, -1, 0.5, speedFor(ped, t, now), 1073741824, 0)
                                    tasked[ped] = { mode = 'chase', t = now + (rage[ped] and now < rage[ped] and 1200 or 2500), target = target }
                                end
                            end
                        end
                    end
                end
                ::continue::
            end
            Wait(300)
        else
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- zombies hitting me (handled by the victim so it's always fair)
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active and not Z.downed and not LocalPlayer.state.zdm_ghost then
            local me = PlayerPedId()
            local mp = GetEntityCoords(me)
            local now = GetGameTimer()
            local mult = Config.DamageMult * ((Z.round and Z.round.dmg) or 1.0)
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local inCar = IsPedInAnyVehicle(me, false)
                    if #(GetEntityCoords(ped) - mp) <= Config.AttackRange + (inCar and 1.2 or 0.0) and now > (lastHit[ped] or 0)
                        and (inCar or HasEntityClearLosToEntity(ped, me, 17)) then
                        lastHit[ped] = now + Config.AttackCooldown
                        local key = zType(ped) or 'walker'
                        local myVeh = GetVehiclePedIsIn(me, false)
                        if myVeh ~= 0 and Config.Vehicles.Shelter and Z.hitCar then
                            -- you're inside: the zombie batters the car, not you
                            Z.hitCar(myVeh, ped, key)
                            goto continue
                        end
                        local dmg = math.floor(TYPES[key].damage * mult)
                        local armour = GetPedArmour(me)
                        if armour > 0 then
                            local a = math.min(armour, math.floor(dmg * 0.6))
                            SetPedArmour(me, armour - a)
                            dmg = dmg - a
                        end
                        local hp = GetEntityHealth(me) - dmg
                        if hp <= 110 then
                            SetEntityHealth(me, 111)
                            Z.down()
                        else
                            SetEntityHealth(me, hp)
                        end
                        if not IsPlayerFreeAiming(PlayerId()) then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.06) end
                        if key == 'tank' and not Z.downed then
                            -- tank hit: you go flying
                            local zp = GetEntityCoords(ped)
                            local dir = mp - zp
                            local l = math.max(0.1, #dir)
                            SetPedToRagdoll(me, Config.Tank.Knockdown or 1600, Config.Tank.Knockdown or 1600, 0, false, false, false)
                            SetEntityVelocity(me, dir.x / l * 9.0, dir.y / l * 9.0, 4.5)
                            ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', 0.25)
                        end
                        SendNUIMessage({ a = 'hit' })
                        SendNUIMessage({ a = 'sfx', s = 'bite', k = key, v = 1.0, p = 0.0 })
                        Z.infectHit()
                        if Z.downed then break end
                        ::continue::
                    end
                end
            end
            Wait(100)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- kill credit + nearby count + last-zombies blips
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active then
            local me = PlayerPedId()
            local mp = GetEntityCoords(me)
            local hunt = Z.round and Z.round.hunt
            local near = 0
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) then
                    if IsPedDeadOrDying(ped, true) then
                        if huntBlips[ped] then
                            if DoesBlipExist(huntBlips[ped]) then RemoveBlip(huntBlips[ped]) end
                            huntBlips[ped] = nil
                        end
                        if not counted[ped] then
                            counted[ped] = true
                            local killer = GetPedSourceOfDeath(ped)
                            if killer == me or (Z.bodyguard and killer == Z.bodyguard) or (IsPedInAnyVehicle(me, false) and killer == GetVehiclePedIsIn(me, false)) then
                                local key = zType(ped) or 'walker'
                                local okb, bone = GetPedLastDamageBone(ped)
                                local cause = GetPedCauseOfDeath(ped)
                                local melee = cause == GetHashKey("WEAPON_UNARMED") or (cause ~= 0 and GetWeapontypeGroup(cause) == GetHashKey("GROUP_MELEE"))
                                TriggerServerEvent('zdm:kill', zId(ped), key, okb and bone == 31086, melee)
                                SendNUIMessage({ a = 'kill', label = TYPES[key].label })
                            end
                        end
                    else
                        if #(GetEntityCoords(ped) - mp) < 60.0 then near = near + 1 end
                        if hunt and not huntBlips[ped] then
                            local b = AddBlipForEntity(ped)
                            SetBlipSprite(b, 1); SetBlipColour(b, 1); SetBlipScale(b, 0.7)
                            BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Zombie'); EndTextCommandSetBlipName(b)
                            huntBlips[ped] = b
                        end
                    end
                end
            end
            if not hunt and next(huntBlips) then clearHuntBlips() end
            SendNUIMessage({ a = 'near', n = near })
            Wait(300)
        else
            if next(huntBlips) then clearHuntBlips() end
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- zombie noises: groans / screeches played in 3D (volume + left/right by position)
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active and #cache > 0 then
            local cam = GetGameplayCamCoord()
            local h = math.rad(GetGameplayCamRot(2).z)
            local rx, ry = math.cos(h), math.sin(h)
            local now = GetGameTimer()
            local range = Config.SoundRange or 38.0
            local sent = 0
            for _, ped in ipairs(cache) do
                if sent >= 3 then break end
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local p = GetEntityCoords(ped)
                    local d = #(p - cam)
                    if d < range then
                        local due = nextGroan[ped]
                        if not due then
                            nextGroan[ped] = now + math.random(400, 3500)
                        elseif now >= due then
                            local key = zType(ped) or 'walker'
                            local aggro = Entity(ped).state.zdm_aggro and true or false
                            local gap = (key == 'runner' and math.random(1800, 4200)) or (key == 'brute' and math.random(4000, 8000)) or math.random(2800, 6500)
                            if aggro then gap = math.floor(gap * 0.7) end
                            nextGroan[ped] = now + gap
                            local dx, dy = p.x - cam.x, p.y - cam.y
                            local len = math.sqrt(dx * dx + dy * dy)
                            local pan = len > 0.5 and ((dx * rx + dy * ry) / len) or 0.0
                            local vol = (1.0 - d / range) ^ 1.6
                            SendNUIMessage({ a = 'sfx', s = aggro and 'aggro' or 'groan', k = key, v = vol, p = pan })
                            sent = sent + 1
                        end
                    end
                end
            end
            Wait(200)
        else
            Wait(700)
        end
    end
end)

---------------------------------------------------------------------------
-- health bars above zombies
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active and Z.settings.bars ~= false then
            local me = PlayerPedId()
            local mp = GetEntityCoords(me)
            local list = {}
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true)
                    and #(GetEntityCoords(ped) - mp) < 40.0 and HasEntityClearLosToEntity(me, ped, 17) then
                    list[#list + 1] = ped
                end
            end
            bars = list
            Wait(250)
        else
            bars = {}
            Wait(1000)
        end
    end
end)

local function text(str, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(x, y)
end

CreateThread(function()
    while true do
        if Z.active and #bars > 0 then
            for _, ped in ipairs(bars) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    local hpos = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                    local on, sx, sy = GetScreenCoordFromWorldCoord(hpos.x, hpos.y, hpos.z + 0.42)
                    if on then
                        local t = TYPES[zType(ped) or 'walker']
                        local max = math.max(1, GetEntityMaxHealth(ped) - 100)
                        local hp = math.max(0, GetEntityHealth(ped) - 100)
                        local pct = math.min(1.0, hp / max)
                        local w = 0.05
                        local r, g, b = 34, 197, 94
                        if pct < 0.3 then r, g, b = 239, 68, 68 elseif pct < 0.6 then r, g, b = 250, 204, 21 end
                        DrawRect(sx, sy, w + 0.003, 0.011, 0, 0, 0, 180)
                        DrawRect(sx - w / 2 + (w * pct) / 2, sy, w * pct, 0.007, r, g, b, 235)
                        local c = t.color or { 255, 255, 255 }
                        text(('%s  %d'):format(t.label, hp), sx, sy - 0.03, 0.30, c[1], c[2], c[3])
                    end
                end
            end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

---------------------------------------------------------------------------
-- screamer: every zombie we control within 30m of the scream goes into a frenzy
---------------------------------------------------------------------------
RegisterNetEvent('zdm:scream', function(x, y, z)
    if not Z.active then return end
    local at = vector3(x, y, z)
    local now = GetGameTimer()
    for _, ped in ipairs(cache) do
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and #(GetEntityCoords(ped) - at) < 30.0 then
            rage[ped] = now + 8000
            tasked[ped] = nil
        end
    end
    local cam = GetGameplayCamCoord()
    local d = #(cam - at)
    if d < 120.0 then
        local h = math.rad(GetGameplayCamRot(2).z)
        local dx, dy = at.x - cam.x, at.y - cam.y
        local len = math.max(0.5, math.sqrt(dx * dx + dy * dy))
        SendNUIMessage({ a = 'sfx', s = 'scream', k = 'screamer', v = math.max(0.25, 1.0 - d / 120.0), p = (dx * math.cos(h) + dy * math.sin(h)) / len })
        SendNUIMessage({ a = 'feed', text = 'A Screamer called the horde!' })
    end
end)

---------------------------------------------------------------------------
-- Glow Horde mutation: every zombie shows on the minimap (outlines removed - they could crash the game)
---------------------------------------------------------------------------
local glowBlips = {}
CreateThread(function()
    while true do
        if Z.active and Z.mut == 'glow' then
            local seen = {}
            for _, ped in ipairs(cache) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
                    seen[ped] = true
                    if not glowBlips[ped] then
                        local b = AddBlipForEntity(ped)
                        SetBlipSprite(b, 1); SetBlipColour(b, 27); SetBlipScale(b, 0.6)
                        glowBlips[ped] = b
                    end
                end
            end
            for ped, b in pairs(glowBlips) do
                if not seen[ped] then
                    if DoesBlipExist(b) then RemoveBlip(b) end
                    glowBlips[ped] = nil
                end
            end
            Wait(500)
        else
            if next(glowBlips) then
                for ped, b in pairs(glowBlips) do if DoesBlipExist(b) then RemoveBlip(b) end glowBlips[ped] = nil end
            end
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- /zpedtest <1-4> : spawn ONE custom zombie in front of you, step by step,
-- to find what makes the zombie pack crash. Run them in order, outside a match.
--   1 = just the ped            2 = + random zombie look
--   3 = + zombie silence/audio  4 = + blood damage decals
---------------------------------------------------------------------------
RegisterCommand('zpedtest', function(_, args)
    local stage = tonumber(args[1]) or 1
    local name = args[2] or (Config.PackModels and Config.PackModels[1]) or 'ywr_zombies'
    local h = GetHashKey(name)
    if not IsModelInCdimage(h) then
        return print(('[zpedtest] %s is NOT streamed - is corlinks_zombie_peds started?'):format(name))
    end
    RequestModel(h)
    local t = GetGameTimer() + 15000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(50) end
    if not HasModelLoaded(h) then return print('[zpedtest] model did not load in 15s') end
    print(('[zpedtest] stage %d: creating %s ...'):format(stage, name))
    local me = PlayerPedId()
    local p = GetOffsetFromEntityInWorldCoords(me, 0.0, 3.0, 0.0)
    local ped = CreatePed(4, h, p.x, p.y, p.z, GetEntityHeading(me) + 180.0, false, false)
    SetModelAsNoLongerNeeded(h)
    print('[zpedtest] created, drawables in slot 0: ' .. GetNumberOfPedDrawableVariations(ped, 0))
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if stage >= 2 then
        Wait(500)
        local nd = GetNumberOfPedDrawableVariations(ped, 0)
        local d = math.random(0, math.max(0, nd - 1))
        local nt = GetNumberOfPedTextureVariations(ped, 0, d)
        print(('[zpedtest] look %d (skins %d)'):format(d, nt))
        if IsPedComponentVariationValid(ped, 0, d, 0) then
            SetPedComponentVariation(ped, 0, d, nt > 0 and math.random(0, nt - 1) or 0, 0)
        end
    end
    if stage >= 3 then
        Wait(500)
        print('[zpedtest] silence')
        StopPedSpeaking(ped, true)
        DisablePedPainAudio(ped, true)
        StopCurrentPlayingAmbientSpeech(ped)
    end
    if stage >= 4 then
        Wait(500)
        print('[zpedtest] blood decals')
        ApplyPedDamagePack(ped, 'BigHitByVehicle', 0.0, 9.0)
    end
    print('[zpedtest] stage ' .. stage .. ' OK - no crash. Ped removed in 20s.')
    SetTimeout(20000, function() if DoesEntityExist(ped) then DeleteEntity(ped) end end)
end, false)

---------------------------------------------------------------------------
-- hitmarker: white X on a hit, yellow on a headshot, red on a kill
---------------------------------------------------------------------------
local lastHm = 0
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not Z.active then return end
    local victim, attacker = args[1], args[2]
    if not victim or not DoesEntityExist(victim) or not IsEntityAPed(victim) or IsPedAPlayer(victim) then return end
    if not Entity(victim).state.zdm then return end
    local me = PlayerPedId()
    if attacker ~= me and not (IsPedInAnyVehicle(me, false) and attacker == GetVehiclePedIsIn(me, false)) then return end
    local now = GetGameTimer()
    local kill = args[6] == 1 or IsPedDeadOrDying(victim, true)
    if not kill and now - lastHm < 45 then return end
    lastHm = now
    if not kill then Z.hitCount = (Z.hitCount or 0) + 1 end
    local ok, bone = GetPedLastDamageBone(victim)
    SendNUIMessage({ a = 'hm', kill = kill, head = ok and bone == 31086 })
end)

-- send hits for points once a second (the server caps it)
CreateThread(function()
    while true do
        Wait(1000)
        if Z.active and (Z.hitCount or 0) > 0 then
            TriggerServerEvent('zdm:hits', Z.hitCount)
            Z.hitCount = 0
        end
    end
end)

RegisterNetEvent('zdm:points', function(pts, total, mult, why)
    SendNUIMessage({ a = 'pts', add = pts, total = total, mult = mult, why = why })
end)
RegisterNetEvent('zdm:mult', function(mult, streak)
    SendNUIMessage({ a = 'mult', mult = mult, streak = streak })
end)
RegisterNetEvent('zdm:paid', function(cash, pts)
    SendNUIMessage({ a = 'paid', cash = cash, pts = pts })
end)

RegisterNetEvent('zdm:maxammo', function()
    SendNUIMessage({ a = 'maxammo' })
end)

---------------------------------------------------------------------------
-- Volatile acid spit (relayed by the server to everyone in the game)
---------------------------------------------------------------------------
local function acidFx(x, y, z, scale)
    if not HasNamedPtfxAssetLoaded('core') then RequestNamedPtfxAsset('core') local w = GetGameTimer() + 1500 while not HasNamedPtfxAssetLoaded('core') and GetGameTimer() < w do Wait(0) end end
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('exp_grd_bzgas_smoke', x, y, z, 0.0, 0.0, 0.0, scale or 0.6, false, false, false)
end

RegisterNetEvent('zdm:spit', function(fx, fy, fz, tx, ty, tz)
    if not Z.active then return end
    local V = Config.Volatile
    local from, to = vector3(fx, fy, fz), vector3(tx, ty, tz + 0.2)
    local dist = #(to - from)
    local dur = math.max(150, math.floor(dist / (V.Speed or 22.0) * 1000))
    CreateThread(function()
        local start = GetGameTimer()
        while true do
            local k = (GetGameTimer() - start) / dur
            if k >= 1.0 then break end
            local p = from + (to - from) * k + vector3(0.0, 0.0, math.sin(k * math.pi) * dist * 0.08)
            DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.22, 0.22, 0.22, 132, 255, 40, 220, false, false, 2, false, nil, nil, false)
            DrawLightWithRange(p.x, p.y, p.z, 120, 255, 40, 2.5, 3.0)
            Wait(0)
        end
        acidFx(to.x, to.y, to.z - 0.2, 0.55)
        -- splash: hurts you if you are still standing where it landed
        local me = PlayerPedId()
        if not Z.downed and #(GetEntityCoords(me) - to) <= (V.Splash or 2.6) then
            local hp = GetEntityHealth(me) - (V.Damage or 22)
            if hp <= 110 then SetEntityHealth(me, 111) Z.down() else SetEntityHealth(me, hp) end
            SendNUIMessage({ a = 'hit' })
            SendNUIMessage({ a = 'feed', text = 'Hit by Volatile acid!', cls = 'loot' })
            if Z.infectHit then Z.infectHit() end
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.08)
        end
    end)
end)
