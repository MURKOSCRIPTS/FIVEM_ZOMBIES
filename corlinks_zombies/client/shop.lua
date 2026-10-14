-- corlinks_zombies - client: in-match shop (K) + bought abilities
Z.perks, Z.timed = {}, {}       -- whole-match perks / [id] = GetGameTimer() when it ends
local shopOpen = false

-- what the run speed should be right now (base, Stamin-Up, Sprint Boost)
function Z.baseSpeed()
    if not Z.active then return 1.0 end
    local sp = Config.Player.Speed or 1.0
    if Z.perks.staminup then sp = math.max(sp, 1.3) end
    if (Z.timed.sprint or 0) > GetGameTimer() then sp = 1.49 end
    return math.min(1.49, sp)
end

-- damage multiplier from abilities (used by pap.lua)
function Z.abilityDamage()
    local m = 1.0
    if Z.perks.doubletap then m = m * 1.5 end
    if (Z.timed.instakill or 0) > GetGameTimer() then m = m * 100.0 end
    return m
end

function Z.maxHealthBonus()
    return Z.perks.juggernog and 1.5 or 1.0
end

---------------------------------------------------------------------------
-- open / close
---------------------------------------------------------------------------
RegisterCommand('zdmshop', function()
    if not Z.active or not (Config.Shop and Config.Shop.Enabled) then return end
    if shopOpen then return end
    if Z.downed then return Z.notify('You can not shop while you are down.', 'error') end
    TriggerServerEvent('zdm:shopOpen')
end, false)
RegisterKeyMapping('zdmshop', 'Zombies: open the shop', 'keyboard', (Config.Shop and Config.Shop.Key) or 'K')

RegisterNetEvent('zdm:shopData', function(wallet, round, perks)
    if not Z.active then return end
    shopOpen = true
    local items = {}
    for _, it in ipairs(Config.Shop.Items) do
        items[#items + 1] = { id = it.id, cat = it.cat, label = it.label, price = it.price, round = it.round or 1,
                              kind = it.kind, desc = it.desc, secs = it.secs, item = it.item }
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ a = 'shop', items = items, wallet = wallet, round = round, perks = perks })
end)

RegisterNUICallback('shopBuy', function(d, cb)
    TriggerServerEvent('zdm:shopBuy', d.id)
    cb(1)
end)

RegisterNUICallback('shopClose', function(_, cb)
    shopOpen = false
    SetNuiFocus(false, false)
    cb(1)
end)

RegisterNetEvent('zdm:shopResult', function(ok, msg, wallet, id)
    SendNUIMessage({ a = 'shopResult', ok = ok, msg = msg, wallet = wallet, id = id })
end)

---------------------------------------------------------------------------
-- bodyguard
---------------------------------------------------------------------------
local guard, guardBlip = nil, nil

local function removeGuard()
    if guardBlip and DoesBlipExist(guardBlip) then RemoveBlip(guardBlip) end
    if guard and DoesEntityExist(guard) then SetEntityAsMissionEntity(guard, true, true); DeleteEntity(guard) end
    guard, guardBlip, Z.bodyguard = nil, nil, nil
end

local function loadPed(name)
    local h = GetHashKey(name)
    if not IsModelInCdimage(h) then return nil end
    RequestModel(h)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(h) and GetGameTimer() < t do Wait(20) end
    return HasModelLoaded(h) and h or nil
end

local function spawnGuard()
    removeGuard()
    local B = Config.Shop.Bodyguard or {}
    local models = B.Models or {}
    local h = (#models > 0 and loadPed(models[math.random(#models)])) or loadPed('s_m_y_blackops_01')
    if not h then return Z.notify('Could not load the bodyguard model.', 'error') end
    local me = PlayerPedId()
    local p = GetOffsetFromEntityInWorldCoords(me, 1.5, -1.5, 0.0)
    guard = CreatePed(4, h, p.x, p.y, p.z, GetEntityHeading(me), true, true)
    SetModelAsNoLongerNeeded(h)
    if guard == 0 then guard = nil return end
    local w = GetGameTimer() + 1000
    while not NetworkGetEntityIsNetworked(guard) and GetGameTimer() < w do Wait(0) end
    SetEntityAsMissionEntity(guard, true, true)
    local team, zg = GetHashKey('ZDM_SURVIVORS'), GetHashKey('ZDM_ZOMBIE')
    SetPedRelationshipGroupHash(guard, team)
    SetRelationshipBetweenGroups(5, team, zg)
    SetRelationshipBetweenGroups(5, zg, team)
    SetRelationshipBetweenGroups(0, team, team)
    local wep = GetHashKey(B.Weapon or 'WEAPON_CARBINERIFLE')
    GiveWeaponToPed(guard, wep, 9999, false, true)
    SetPedInfiniteAmmo(guard, true, wep)
    SetPedAccuracy(guard, 75)
    SetPedCombatAbility(guard, 2)
    SetPedCombatRange(guard, 2)
    SetPedCombatAttributes(guard, 46, true)
    SetPedFleeAttributes(guard, 0, false)
    SetPedDropsWeaponsWhenDead(guard, false)
    SetEntityMaxHealth(guard, (B.Health or 1500) + 100)
    SetEntityHealth(guard, (B.Health or 1500) + 100)
    SetPedArmour(guard, 100)
    SetPedSuffersCriticalHits(guard, false)
    SetCanAttackFriendly(guard, false, false)
    guardBlip = AddBlipForEntity(guard)
    SetBlipSprite(guardBlip, 88); SetBlipColour(guardBlip, 3); SetBlipScale(guardBlip, 0.8)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Bodyguard'); EndTextCommandSetBlipName(guardBlip)
    Z.bodyguard = guard
    Z.notify('Your bodyguard has arrived!', 'success')
end

CreateThread(function()
    while true do
        if guard then
            if not Z.active or not DoesEntityExist(guard) then
                removeGuard()
            elseif IsPedDeadOrDying(guard, true) then
                Z.notify('Your bodyguard went down.', 'error')
                SetTimeout(4000, removeGuard)
                guard = nil
            else
                local me = PlayerPedId()
                local gp, mp = GetEntityCoords(guard), GetEntityCoords(me)
                if #(gp - mp) > 70.0 then
                    local p = GetOffsetFromEntityInWorldCoords(me, 1.5, -1.5, 0.0)
                    SetEntityCoords(guard, p.x, p.y, p.z, false, false, false, false)
                end
                if not IsPedInCombat(guard, 0) then
                    local best, bd = nil, 45.0
                    for _, z in ipairs(Z.cache or {}) do
                        if DoesEntityExist(z) and not IsPedDeadOrDying(z, true) then
                            local d = #(GetEntityCoords(z) - gp)
                            if d < bd then best, bd = z, d end
                        end
                    end
                    if best then
                        TaskCombatPed(guard, best, 0, 16)
                    elseif #(gp - mp) > 4.0 then
                        TaskFollowToOffsetOfEntity(guard, me, 1.5, -1.5, 0.0, 3.0, -1, 2.5, true)
                    end
                end
            end
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

---------------------------------------------------------------------------
-- abilities
---------------------------------------------------------------------------
local LABEL = {}
for _, it in ipairs((Config.Shop and Config.Shop.Items) or {}) do LABEL[it.id] = it.label end

RegisterNetEvent('zdm:ability', function(id, secs)
    if not Z.active then return end
    local ped = PlayerPedId()
    if id == 'armour' then
        SetPedArmour(ped, 100)
        return
    end
    if secs and secs > 0 then
        Z.timed[id] = GetGameTimer() + secs * 1000
    elseif id ~= 'nuke' then
        Z.perks[id] = true
    end
    if id == 'juggernog' then
        local mx = math.floor((Config.Player.MaxHealth or 200) * Z.maxHealthBonus())
        SetEntityMaxHealth(ped, mx)
        SetEntityHealth(ped, mx)
    elseif id == 'bodyguard' then
        CreateThread(spawnGuard)
    end
    SetRunSprintMultiplierForPlayer(PlayerId(), Z.baseSpeed())
    SendNUIMessage({ a = 'ability', id = id, label = LABEL[id] or id, secs = secs or 0 })
end)

-- timed effects tick
CreateThread(function()
    local wasGod, wasInf = false, false
    local lastSpeed = nil
    while true do
        if Z.active then
            local now, ped, pid = GetGameTimer(), PlayerPedId(), PlayerId()
            -- speed (Stamin-Up / Sprint Boost / expiry)
            local sp = Z.baseSpeed()
            if sp ~= lastSpeed then SetRunSprintMultiplierForPlayer(pid, sp); lastSpeed = sp end
            if (Z.timed.sprint or 0) > now then RestorePlayerStamina(pid, 1.0) end
            -- Iron Skin
            local god = (Z.timed.godmode or 0) > now
            if god then SetEntityInvincible(ped, true) elseif wasGod and not Z.downed then SetEntityInvincible(ped, false) end
            wasGod = god
            -- Bottomless Clip
            local inf = (Z.timed.infammo or 0) > now
            if inf or wasInf then SetPedInfiniteAmmoClip(ped, inf) end
            wasInf = inf
            -- Regeneration
            if (Z.timed.regen or 0) > now and not Z.downed then
                local mx = GetEntityMaxHealth(ped)
                local hp = GetEntityHealth(ped)
                if hp < mx then SetEntityHealth(ped, math.min(mx, hp + 3)) end
            end
            -- PhD Flopper: explosion proof
            if Z.perks.phd then SetEntityProofs(ped, false, false, true, false, false, false, false, false) end
            Wait(250)
        else
            if wasGod then SetEntityInvincible(PlayerPedId(), false) wasGod = false end
            if wasInf then SetPedInfiniteAmmoClip(PlayerPedId(), false) wasInf = false end
            lastSpeed = nil
            Wait(1000)
        end
    end
end)

-- everything bought ends with the match
function Z.resetAbilities()
    local ped = PlayerPedId()
    if Z.perks.phd then SetEntityProofs(ped, false, false, false, false, false, false, false, false) end
    Z.perks, Z.timed = {}, {}
    SetPedInfiniteAmmoClip(ped, false)
    removeGuard()
    SendNUIMessage({ a = 'abilityReset' })
    if shopOpen then shopOpen = false SetNuiFocus(false, false) SendNUIMessage({ a = 'shopClose' }) end
end

---------------------------------------------------------------------------
-- Nuke + Shrink Ray (sent to everyone in the match)
---------------------------------------------------------------------------
RegisterNetEvent('zdm:nuke', function(x, y, z, who)
    if not Z.active then return end
    local at = vector3(x, y, z)
    AnimpostfxPlay('DeathFailMPIn', 800, false)
    ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', 0.3)
    for _, ped in ipairs(Z.cache or {}) do
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) and not IsPedDeadOrDying(ped, true)
            and #(GetEntityCoords(ped) - at) < 70.0 then
            SetEntityHealth(ped, 0)
        end
    end
    SendNUIMessage({ a = 'feed', text = ('☢ %s dropped a NUKE!'):format(who or 'Someone'), cls = 'loot' })
end)

RegisterNetEvent('zdm:shrink', function(secs, who)
    if not Z.active then return end
    Z.shrinkUntil = GetGameTimer() + (secs or 20) * 1000
    SendNUIMessage({ a = 'feed', text = ('🔬 %s used the Shrink Ray!'):format(who or 'Someone'), cls = 'loot' })
end)

-- visual shrink: rescale every zombie's matrix each frame (looks only - hitboxes stay normal)
local shrunk = {}
CreateThread(function()
    while true do
        if Z.active and (Z.shrinkUntil or 0) > GetGameTimer() then
            local s = 0.45
            local mp = GetEntityCoords(PlayerPedId())
            for _, ped in ipairs(Z.cache or {}) do
                if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) and not IsPedRagdoll(ped)
                    and #(GetEntityCoords(ped) - mp) < 120.0 then
                    local fwd, right, up, pos = GetEntityMatrix(ped)
                    -- keep feet on the ground without sinking a bit more every frame
                    local trueZ = pos.z
                    if shrunk[ped] and math.abs(pos.z - shrunk[ped].set) < 0.01 then trueZ = shrunk[ped].z end
                    local z = trueZ - (1.0 - s) * 0.98
                    shrunk[ped] = { set = z, z = trueZ }
                    SetEntityMatrix(ped, fwd.x * s, fwd.y * s, fwd.z * s, right.x * s, right.y * s, right.z * s,
                        up.x * s, up.y * s, up.z * s, pos.x, pos.y, z)
                end
            end
            Wait(0)
        else
            if next(shrunk) then shrunk = {} end
            Wait(300)
        end
    end
end)

---------------------------------------------------------------------------
-- Mystery Box: a wooden crate with yellow "?" next to every map's spawn
---------------------------------------------------------------------------
local MB = Config.MysteryBox or {}
local box, boxPos, spinning, boxBlip = nil, nil, false, nil
Z.boxWeapons = {}   -- [weapon hash] = damage multiplier

local function removeBox()
    if box and DoesEntityExist(box) then DeleteEntity(box) end
    if boxBlip and DoesBlipExist(boxBlip) then RemoveBlip(boxBlip) end
    box, boxPos, boxBlip = nil, nil, nil
end

local function placeBox()
    removeBox()
    if not (MB.Enabled and Z.active) then return end
    local m = Config.Maps[Z.active.map] or {}
    local c = m.box or (Z.active.center + (MB.Offset or vector3(4.0, 4.0, 0.0)))
    -- find the floor under that spot
    local h = StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z + 3.0, c.x, c.y, c.z - 10.0, 1 + 16, 0, 7)
    local _, hit, pos = GetShapeTestResult(h)
    local z = (hit == 1) and pos.z or c.z
    local model
    for _, name in ipairs(MB.Props or {}) do
        local hh = GetHashKey(name)
        if IsModelInCdimage(hh) then model = hh break end
    end
    if not model then return end
    RequestModel(model)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < t do Wait(20) end
    if not HasModelLoaded(model) then return end
    box = CreateObject(model, c.x, c.y, z, false, false, false) -- local only: every player has their own copy
    SetModelAsNoLongerNeeded(model)
    PlaceObjectOnGroundProperly(box)
    FreezeEntityPosition(box, true)
    SetEntityInvincible(box, true)
    boxPos = GetEntityCoords(box)
    local B = MB.Blip or {}
    boxBlip = AddBlipForCoord(boxPos.x, boxPos.y, boxPos.z)
    SetBlipSprite(boxBlip, B.Sprite or 66)
    SetBlipColour(boxBlip, B.Colour or 46)
    SetBlipScale(boxBlip, B.Scale or 0.85)
    SetBlipAsShortRange(boxBlip, false)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(B.Label or 'Mystery Box'); EndTextCommandSetBlipName(boxBlip)
end

-- spawn / remove with the match
CreateThread(function()
    local lastMap
    while true do
        if Z.active and MB.Enabled then
            if lastMap ~= Z.active.map or not (box and DoesEntityExist(box)) then
                Wait(2500)
                if Z.active then placeBox(); lastMap = Z.active.map end
            end
            Wait(1000)
        else
            if box then removeBox() end
            lastMap = nil
            Wait(1000)
        end
    end
end)

-- the look (two yellow "?" on the lid + glow) and the E prompt
CreateThread(function()
    while true do
        if Z.active and box and boxPos then
            local mp = GetEntityCoords(PlayerPedId())
            local d = #(mp - boxPos)
            if d < 80.0 then
                local mn, mx = GetModelDimensions(GetEntityModel(box))
                local top = boxPos.z + (mx.z - mn.z) * 0.5 + 0.02
                local now = GetGameTimer()
                local pulse = 0.5 + 0.5 * math.sin(now / 350.0)
                -- golden light beam into the sky (CoD style)
                DrawMarker(1, boxPos.x, boxPos.y, boxPos.z - 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.55, 0.55, 60.0, 250, 204, 21, math.floor(40 + 30 * pulse), false, false, 2, false, nil, nil, false)
                DrawMarker(1, boxPos.x, boxPos.y, boxPos.z - 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.18, 0.18, 60.0, 255, 255, 220, math.floor(90 + 60 * pulse), false, false, 2, false, nil, nil, false)
                -- glowing ring on the floor
                DrawMarker(25, boxPos.x, boxPos.y, boxPos.z - (mx.z - mn.z) * 0.5 + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.4, 2.4, 1.0, 250, 204, 21, math.floor(90 + 80 * pulse), false, false, 2, false, nil, nil, false)
                -- one big spinning, bobbing "?" above the crate
                DrawMarker(32, boxPos.x, boxPos.y, top + 0.55 + math.sin(now / 420.0) * 0.08, 0.0, 0.0, 0.0, 0.0, 0.0, (now / 8.0) % 360.0, 0.42, 0.42, 0.42, 250, 204, 21, 235, false, false, 2, false, nil, nil, false)
                DrawLightWithRange(boxPos.x, boxPos.y, top + 0.8, 250, 204, 21, 5.0, 2.0 + pulse)
                if d < 12.0 then
                    -- floating label
                    local onScreen, sx, sy = World3dToScreen2d(boxPos.x, boxPos.y, top + 1.15)
                    if onScreen then
                        SetTextFont(4); SetTextScale(0.0, 0.42); SetTextColour(250, 204, 21, 255); SetTextCentre(true); SetTextOutline()
                        BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName('MYSTERY BOX'); EndTextCommandDisplayText(sx, sy)
                        SetTextFont(4); SetTextScale(0.0, 0.32); SetTextColour(255, 255, 255, 230); SetTextCentre(true); SetTextOutline()
                        BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('%d points'):format(MB.Price or 950)); EndTextCommandDisplayText(sx, sy + 0.028)
                    end
                end
                if d < 2.2 and not spinning then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(('~INPUT_CONTEXT~ Mystery Box  ~y~%d points~s~'):format(MB.Price or 950))
                    EndTextCommandDisplayHelp(0, false, false, -1)
                    if IsControlJustPressed(0, 38) and not Z.downed then
                        spinning = true
                        TriggerServerEvent('zdm:boxOpen')
                        SetTimeout(1500, function() if spinning and not Z.boxSpinActive then spinning = false end end)
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('zdm:boxSpin', function(reel, result, vip, secs)
    Z.boxSpinActive = true
    spinning = true
    SendNUIMessage({ a = 'boxSpin', reel = reel, result = result, vip = vip, secs = secs })
    SetTimeout(math.floor((secs or 4) * 1000) + 600, function() spinning = false; Z.boxSpinActive = false end)
end)

RegisterNetEvent('zdm:boxGot', function(item, label, vip)
    Z.boxWeapons[GetHashKey(item)] = vip and (MB.VipDamage or 2.5) or (MB.BaseDamage or 1.3)
    Z.notify(('Mystery Box: %s%s'):format(label, vip and ' (VIP - insane damage!)' or ''), 'success')
end)

-- box guns hit harder while you hold them (used by pap.lua)
function Z.boxDamage()
    local w = GetSelectedPedWeapon(PlayerPedId())
    return Z.boxWeapons[w] or 1.0
end

local oldReset = Z.resetAbilities
function Z.resetAbilities()
    if oldReset then oldReset() end
    Z.boxWeapons = {}
end
