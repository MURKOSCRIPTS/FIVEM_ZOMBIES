-- corlinks_zombies - client: survivor vehicles + airdrops

---------------------------------------------------------------------------
-- survivor vehicles (spawned by the game's host, everyone sees the blips)
---------------------------------------------------------------------------
local function loadModel(name)
    local h = GetHashKey(name)
    if not IsModelInCdimage(h) or not IsModelAVehicle(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 6000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(h) and h or nil
end

RegisterNetEvent('zdm:cars', function(count, models)
    if not Z.active then
        local t = GetGameTimer() + 8000
        while not Z.active and GetGameTimer() < t do Wait(200) end
        if not Z.active then return end
    end
    Wait(1500)
    local c = Z.active.center
    local mapCfg = Config.Maps[Z.active.map] or {}
    if mapCfg.boats then
        -- water map: survivor boats on the water around the centre
        local B = mapCfg.boats
        local hs = {}
        for _, m in ipairs(B.models or {}) do local h = loadModel(m) if h then hs[#hs + 1] = h end end
        if #hs == 0 then return end
        local placed, R = {}, Z.active.radius or Config.BorderRadius
        for n = 1, (B.count or 4) do
            local h = hs[(n - 1) % #hs + 1]
            for _ = 1, 25 do
                local a, r = math.random() * math.pi * 2, 45.0 + math.random() * math.max(20.0, R - 80.0)
                local x, y = c.x + math.cos(a) * r, c.y + math.sin(a) * r
                local wet, wz = GetWaterHeight(x, y, c.z + 20.0)
                local far = true
                for _, p in ipairs(placed) do if #(p - vector3(x, y, wz or 0.0)) < 20.0 then far = false end end
                if wet and far and Z.edgeDist(vector3(x, y, 0.0), c) < R - 25.0 then
                    local veh = CreateVehicle(h, x, y, wz + 0.5, math.random() * 360.0, true, false)
                    if veh ~= 0 then
                        local w = GetGameTimer() + 1000
                        while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < w do Wait(0) end
                        SetEntityAsMissionEntity(veh, true, true)
                        SetVehicleNumberPlateText(veh, ('SURVIV%d'):format(n))
                        SetVehicleDoorsLocked(veh, 1)
                        SetBoatAnchor(veh, true)
                        SetVehicleFuelLevel(veh, 100.0)
                        Entity(veh).state:set('fuel', 100, true)
                        Entity(veh).state:set('zdm_car', true, true)
                        placed[#placed + 1] = vector3(x, y, wz)
                        break
                    end
                end
            end
        end
        for _, h in ipairs(hs) do SetModelAsNoLongerNeeded(h) end
        return
    end
    local usable = {}
    for _, m in ipairs(models or {}) do
        local h = loadModel(m)
        if h then usable[#usable + 1] = h end
    end
    if #usable == 0 then return end
    local placed = {}
    for n = 1, count do
        local h = usable[(n - 1) % #usable + 1]
        for _ = 1, 12 do
            local a, r = math.random() * math.pi * 2, 35.0 + math.random() * 160.0
            local x, y = c.x + math.cos(a) * r, c.y + math.sin(a) * r
            local found, pos, heading = GetClosestVehicleNodeWithHeading(x, y, c.z, 1, 3.0, 0)
            local far = true
            for _, p in ipairs(placed) do if #(p - pos) < 25.0 then far = false end end
            if found and far and Z.edgeDist(pos, c) < (Z.active.radius or Config.BorderRadius) - 40.0 then
                local veh = CreateVehicle(h, pos.x, pos.y, pos.z + 0.5, heading, true, false)
                if veh ~= 0 then
                    local wait = GetGameTimer() + 1000
                    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < wait do Wait(0) end
                    SetEntityAsMissionEntity(veh, true, true)
                    SetVehicleOnGroundProperly(veh)
                    SetVehicleNumberPlateText(veh, ('SURVIV%d'):format(n))
                    SetVehicleDoorsLocked(veh, 1)
                    SetVehicleStrong(veh, true)
                    SetVehicleModKit(veh, 0)
                    SetVehicleMod(veh, 16, GetNumVehicleMods(veh, 16) - 1, false) -- armour
                    SetVehicleMod(veh, 11, GetNumVehicleMods(veh, 11) - 1, false) -- engine
                    SetVehicleFuelLevel(veh, 100.0)
                    Entity(veh).state:set('fuel', 100, true)
                    Entity(veh).state:set('zdm_car', true, true)
                    placed[#placed + 1] = pos
                    break
                end
            end
        end
    end
    for _, h in ipairs(usable) do SetModelAsNoLongerNeeded(h) end
end)

local carBlips, keyed = {}, {}
CreateThread(function()
    while true do
        if Z.active then
            local me = PlayerPedId()
            local mp = GetEntityCoords(me)
            local seen = {}
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if Entity(veh).state.zdm_car then
                    seen[veh] = true
                    if not carBlips[veh] or not DoesBlipExist(carBlips[veh]) then
                        local b = AddBlipForEntity(veh)
                        SetBlipSprite(b, 225); SetBlipColour(b, 2); SetBlipScale(b, 0.8)
                        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Survivor Vehicle'); EndTextCommandSetBlipName(b)
                        carBlips[veh] = b
                    end
                    -- keys for anyone who walks up to it
                    local plate = GetVehicleNumberPlateText(veh)
                    if not keyed[plate] and #(GetEntityCoords(veh) - mp) < 6.0 then
                        keyed[plate] = true
                        TriggerEvent('vehiclekeys:client:SetOwner', plate)
                        TriggerEvent('qb-vehiclekeys:client:AddKeys', plate)
                    end
                end
            end
            for veh, b in pairs(carBlips) do
                if not seen[veh] then
                    if DoesBlipExist(b) then RemoveBlip(b) end
                    carBlips[veh] = nil
                end
            end
            Wait(1500)
        else
            if next(carBlips) then
                for veh, b in pairs(carBlips) do if DoesBlipExist(b) then RemoveBlip(b) end carBlips[veh] = nil end
                keyed = {}
            end
            Wait(1500)
        end
    end
end)

function Z.cleanupExtras()
    Z.stopYachtKeeper = true
    -- only local stuff: the server removes the game's vehicles/crates when the game ends
    for _, d in pairs(Z.drops or {}) do
        if d.blip and DoesBlipExist(d.blip) then RemoveBlip(d.blip) end
    end
    Z.drops = {}
    for veh, b in pairs(carBlips) do if DoesBlipExist(b) then RemoveBlip(b) end carBlips[veh] = nil end
    keyed = {}
end

---------------------------------------------------------------------------
-- airdrops
---------------------------------------------------------------------------
Z.drops = {}
local CRATE, CHUTE = 'prop_mil_crate_01', 'p_cargo_chute_s'

local function loadObj(name)
    local h = GetHashKey(name)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(h) and h or nil
end

local function groundZ(x, y, guess)
    RequestCollisionAtCoord(x, y, guess)
    for _ = 1, 30 do
        local ok, z = GetGroundZFor_3dCoord(x, y, guess + 150.0, false)
        if ok then return z end
        Wait(50)
    end
    return guess
end

RegisterNetEvent('zdm:drop', function(drop, isHost)
    if not Z.active then return end
    local d = { id = drop.id, x = drop.x, y = drop.y, z = drop.z, landed = false }
    Z.drops[d.id] = d
    local b = AddBlipForCoord(d.x, d.y, d.z)
    SetBlipSprite(b, 94); SetBlipColour(b, 27); SetBlipScale(b, 1.0); SetBlipAsShortRange(b, false)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Supply Drop'); EndTextCommandSetBlipName(b)
    d.blip = b
    SendNUIMessage({ a = 'drop' })
    if not isHost then return end

    CreateThread(function()
        local crate, chute = loadObj(CRATE), loadObj(CHUTE)
        if not crate then return end
        local gz = groundZ(d.x, d.y, d.z)
        local z = gz + 140.0
        local obj = CreateObject(crate, d.x, d.y, z, true, true, false)
        local wait = GetGameTimer() + 1000
        while not NetworkGetEntityIsNetworked(obj) and GetGameTimer() < wait do Wait(0) end
        SetEntityAsMissionEntity(obj, true, true)
        FreezeEntityPosition(obj, true)
        SetEntityLodDist(obj, 1000)
        Entity(obj).state:set('zdm_drop', d.id, true)
        local ch
        if chute then
            ch = CreateObject(chute, d.x, d.y, z + 2.5, true, true, false)
            SetEntityLodDist(ch, 1000)
            AttachEntityToEntity(ch, obj, 0, 0.0, 0.0, 0.2, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        end
        d.obj, d.chute = obj, ch
        local last = GetGameTimer()
        while DoesEntityExist(obj) and z > gz + 0.05 do
            local now = GetGameTimer()
            z = math.max(gz, z - 7.0 * (now - last) / 1000.0)
            last = now
            SetEntityCoordsNoOffset(obj, d.x, d.y, z, false, false, false)
            SetEntityRotation(obj, 0.0, 0.0, (now / 40.0) % 360.0, 2, true)
            Wait(0)
        end
        if ch and DoesEntityExist(ch) then DeleteEntity(ch) end
        if DoesEntityExist(obj) then
            PlaceObjectOnGroundProperly(obj)
            TriggerServerEvent('zdm:dropLanded', d.id, GetEntityCoords(obj).z)
        end
    end)
end)

RegisterNetEvent('zdm:dropLanded', function(id, z)
    local d = Z.drops[id]
    if not d then return end
    d.landed, d.z = true, z
    if d.blip and DoesBlipExist(d.blip) then SetBlipCoords(d.blip, d.x, d.y, z) end
end)

RegisterNetEvent('zdm:dropGone', function(id, who, label)
    local d = Z.drops[id]
    if d then
        if d.blip and DoesBlipExist(d.blip) then RemoveBlip(d.blip) end
        if d.obj and DoesEntityExist(d.obj) then SetEntityAsMissionEntity(d.obj, true, true); DeleteEntity(d.obj) end
        if d.chute and DoesEntityExist(d.chute) then DeleteEntity(d.chute) end
        Z.drops[id] = nil
    end
    for _, obj in ipairs(GetGamePool('CObject')) do
        if Entity(obj).state.zdm_drop == id and NetworkHasControlOfEntity(obj) then DeleteEntity(obj) end
    end
    if who then SendNUIMessage({ a = 'feed', text = ('%s opened a supply drop: %s'):format(who, label or '?'), cls = 'loot' }) end
end)

-- light beam + "press E" on landed drops
CreateThread(function()
    local claiming = 0
    while true do
        if Z.active and next(Z.drops) then
            local mp = GetEntityCoords(PlayerPedId())
            for id, d in pairs(Z.drops) do
                if d.landed then
                    DrawMarker(1, d.x, d.y, d.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.9, 0.9, 300.0, 192, 132, 252, 110, false, false, 2, false, nil, nil, false)
                    DrawMarker(1, d.x, d.y, d.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.25, 0.25, 300.0, 255, 255, 255, 180, false, false, 2, false, nil, nil, false)
                    local dist = #(vector2(mp.x, mp.y) - vector2(d.x, d.y))
                    if dist < 3.0 and math.abs(mp.z - d.z) < 4.0 then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName('~INPUT_CONTEXT~ Open supply drop')
                        EndTextCommandDisplayHelp(0, false, false, -1)
                        if IsControlJustPressed(0, 38) and GetGameTimer() > claiming then
                            claiming = GetGameTimer() + 1500
                            TriggerServerEvent('zdm:claim', id)
                        end
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- cars as shelter: they never explode or burn, zombies just wreck them
---------------------------------------------------------------------------
local V = Config.Vehicles

local function protect(veh)
    SetEntityProofs(veh, false, true, true, false, false, false, false, false) -- fire + explosion proof
    SetVehicleExplodesOnHighExplosionDamage(veh, false)
    SetDisableVehicleEngineFires(veh, true)
    SetDisableVehiclePetrolTankFires(veh, true)
    SetDisableVehiclePetrolTankDamage(veh, true)
    SetVehicleCanLeakOil(veh, false)
    SetVehicleCanLeakPetrol(veh, false)
    if GetVehiclePetrolTankHealth(veh) < 1000.0 then SetVehiclePetrolTankHealth(veh, 1000.0) end
    if GetVehicleEngineHealth(veh) < (V.EngineFloor or 0.0) then SetVehicleEngineHealth(veh, V.EngineFloor or 0.0) end
    if GetVehicleBodyHealth(veh) < 50.0 then SetVehicleBodyHealth(veh, 50.0) end
    if IsEntityOnFire(veh) then StopEntityFire(veh) end
end

-- called by zombies.lua when a zombie hits you while you're in a vehicle
function Z.hitCar(veh, zped, kind)
    if not NetworkHasControlOfEntity(veh) then NetworkRequestControlOfEntity(veh) end
    local mult = (kind == 'brute' and 2.0) or 1.0
    local body = math.max(50.0, GetVehicleBodyHealth(veh) - (V.HitBody or 35.0) * mult)
    local eng  = math.max(V.EngineFloor or 0.0, GetVehicleEngineHealth(veh) - (V.HitEngine or 22.0) * mult)
    SetVehicleBodyHealth(veh, body)
    SetVehicleEngineHealth(veh, eng)
    -- dents + broken glass on the side the zombie is on
    local off = GetOffsetFromEntityGivenWorldCoords(veh, GetEntityCoords(zped))
    SetVehicleDamage(veh, off.x * 0.6, off.y * 0.6, 0.2, 180.0 * mult, 120.0, true)
    if math.random() < 0.25 then SmashVehicleWindow(veh, math.random(0, 7)) end
    if eng <= 0.0 then SetVehicleEngineOn(veh, false, true, true); SetVehicleUndriveable(veh, true) end
    ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.03)
    SendNUIMessage({ a = 'sfx', s = 'bite', k = kind, v = 0.6, p = 0.0 })
    protect(veh)
end

-- keep every car in the game world from exploding (bloaters, gunfire, crashes)
CreateThread(function()
    while true do
        if Z.active and V.Shelter then
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if NetworkHasControlOfEntity(veh) then protect(veh) end
            end
            Wait(250)
        else
            Wait(1500)
        end
    end
end)

---------------------------------------------------------------------------
-- yachts: always there, can't be destroyed, zombies climb aboard
---------------------------------------------------------------------------
Z.yachts = {}
local keeper = false
local yachtBlips = {}

RegisterNetEvent('zdm:yachtKeeper', function(on) keeper = on and true or false; Z.stopYachtKeeper = false end)

local function yachtsHere()
    local Y = Config.Yachts
    return Y and Y.Enabled and Z.active and Y.Maps[Z.active.map]
end

local function lockYacht(veh, spot)
    SetEntityInvincible(veh, true)
    SetEntityProofs(veh, true, true, true, true, true, true, true, true)
    SetVehicleCanBeVisiblyDamaged(veh, false)
    SetVehicleExplodesOnHighExplosionDamage(veh, false)
    SetVehicleEngineHealth(veh, 1000.0); SetVehicleBodyHealth(veh, 1000.0); SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleUndriveable(veh, true)
    SetVehicleDoorsLocked(veh, 1)
    SetBoatAnchor(veh, true)
    SetBoatFrozenWhenAnchored(veh, true)
    if spot and #(GetEntityCoords(veh) - vector3(spot[1], spot[2], Config.Yachts.Z)) > 6.0 then
        SetEntityCoords(veh, spot[1], spot[2], Config.Yachts.Z, false, false, false, false)
        SetEntityHeading(veh, spot[3])
    end
    FreezeEntityPosition(veh, true) -- a solid deck to stand and fight on
end

-- the keeper (game host) makes sure every spot has its yacht
CreateThread(function()
    while true do
        Wait(3000)
        if Z.stopYachtKeeper then keeper, Z.stopYachtKeeper = false, false end
        if yachtsHere() and keeper then
            local Y = Config.Yachts
            local have = {}
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                local i = Entity(veh).state.zdm_yacht
                if i then
                    if have[i] then DeleteEntity(veh) else have[i] = veh end
                end
            end
            for i, spot in ipairs(Y.Spots) do
                local veh = have[i]
                if not veh or not DoesEntityExist(veh) then
                    local h = loadModel(Y.Model)
                    if h then
                        veh = CreateVehicle(h, spot[1], spot[2], Y.Z, spot[3], true, false)
                        if veh ~= 0 then
                            local w = GetGameTimer() + 1000
                            while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < w do Wait(0) end
                            SetEntityAsMissionEntity(veh, true, true)
                            SetVehicleNumberPlateText(veh, ('YACHT%d'):format(i))
                            Entity(veh).state:set('zdm_yacht', i, true)
                            lockYacht(veh, spot)
                        end
                        SetModelAsNoLongerNeeded(h)
                    else
                        print(('[corlinks_zombies] yacht model %s not found'):format(Y.Model))
                        break
                    end
                elseif NetworkHasControlOfEntity(veh) then
                    lockYacht(veh, spot)
                end
            end
        end
    end
end)

-- everyone: keep the list for the zombie AI, protect the ones we control, blips
CreateThread(function()
    while true do
        if yachtsHere() then
            local list, seen = {}, {}
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                local i = Entity(veh).state.zdm_yacht
                if i then
                    list[#list + 1] = veh
                    seen[veh] = true
                    if NetworkHasControlOfEntity(veh) then
                        SetEntityInvincible(veh, true)
                        if not IsEntityPositionFrozen(veh) then FreezeEntityPosition(veh, true) end
                    end
                    if Config.Yachts.Blip and (not yachtBlips[veh] or not DoesBlipExist(yachtBlips[veh])) then
                        local b = AddBlipForEntity(veh)
                        SetBlipSprite(b, 455); SetBlipColour(b, 3); SetBlipScale(b, 0.7)
                        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Yacht'); EndTextCommandSetBlipName(b)
                        yachtBlips[veh] = b
                    end
                end
            end
            for veh, b in pairs(yachtBlips) do
                if not seen[veh] then if DoesBlipExist(b) then RemoveBlip(b) end yachtBlips[veh] = nil end
            end
            Z.yachts = list
            Wait(1000)
        else
            if next(yachtBlips) then
                for veh, b in pairs(yachtBlips) do if DoesBlipExist(b) then RemoveBlip(b) end yachtBlips[veh] = nil end
            end
            Z.yachts = {}
            Wait(1500)
        end
    end
end)
