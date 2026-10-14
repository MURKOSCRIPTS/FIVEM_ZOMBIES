-- corlinks_zombies - client: menu, HUD, rounds, border, death/respawn, team blips
local QBCore = exports['qb-core']:GetCoreObject()

Z = { active = nil, downed = false, infected = false, round = nil, settings = { bars = true } }

function Z.buffPlayer()
    local ped = PlayerPedId()
    local mx = math.floor((Config.Player.MaxHealth or 200) * (Z.maxHealthBonus and Z.maxHealthBonus() or 1.0))
    SetEntityMaxHealth(ped, mx)
    SetEntityHealth(ped, mx)
    SetPedArmour(ped, Config.Player.Armour or 0)
    ClearPedBloodDamage(ped)
    SetRunSprintMultiplierForPlayer(PlayerId(), Z.baseSpeed and Z.baseSpeed() or math.min(1.49, Config.Player.Speed or 1.0))
    SetSwimMultiplierForPlayer(PlayerId(), math.min(1.49, Config.Player.Speed or 1.0))
end

function Z.setMutation(key)
    Z.mut = key
    ClearTimecycleModifier()
    local m = key and Config.Mutations.List[key]
    if m and m.timecycle then
        SetTimecycleModifier(m.timecycle)
        SetTimecycleModifierStrength(m.strength or 0.5)
    end
end

function Z.notify(msg, t)
    QBCore.Functions.Notify(msg, t or 'primary', 5000)
end
RegisterNetEvent('zdm:notify', function(msg, t) Z.notify(msg, t) end)

---------------------------------------------------------------------------
-- menu
---------------------------------------------------------------------------
local function uiData()
    local weapons = {}
    for _, w in ipairs(Config.Weapons) do
        weapons[#weapons + 1] = { item = w.item, label = w.label, cat = w.cat or 'Other', ammo = w.ammo and w.amount or nil,
                                  dmg = w.dmg or 2, rate = w.rate or 2, range = w.range or 2 }
    end
    local kit = {}
    for _, k in ipairs(Config.Kit) do kit[#kit + 1] = { item = k[1], label = k[3] or k[1], count = k[2] } end
    if Config.Lethals and Config.Lethals.Enabled then
        for _, e in ipairs(Config.Lethals.Start or {}) do kit[#kit + 1] = { item = e[1], label = e[4] or e[1], count = e[2] } end
    end
    local types = {}
    for key, t in pairs(Config.Types) do
        types[#types + 1] = { key = key, label = t.label, desc = t.desc, health = t.health, damage = t.damage,
                              speed = t.speed, sight = t.sight, color = t.color, weight = t.weight, from = (t.special == 'hound' and Config.DogRound and Config.DogRound.Every) or t.from or 1, special = t.special }
    end
    table.sort(types, function(a, b) if a.from ~= b.from then return a.from < b.from end return a.health < b.health end)
    local pap = {}
    for _, w in ipairs(Config.PackAPunch.Weapons) do pap[#pap + 1] = w.label end
    return {
        maxStart = Config.Match.MaxStartRound or 100,
        weapons = weapons, kit = kit, types = types, ranks = Config.Ranks,
        rounds = { base = Config.Rounds.Base, per = Config.Rounds.PerRound, runners = Config.Rounds.RunnersFrom,
                   brutes = Config.Rounds.BrutesFrom, pap = Config.PackAPunch.Round, papList = pap },
        border = Config.BorderRadius, leave = Config.LeaveCommand, cmd = Config.Command,
        slots = Config.SlotCategories, music = Config.MenuMusic, maxPlayers = Config.Match.MaxPlayers,
        rewards = Config.RoundRewards,
        mutations = (function() local l = {} for k, m in pairs(Config.Mutations.List) do l[#l + 1] = { key = k, label = m.label, desc = m.desc } end return l end)(),
        mutEvery = Config.Mutations.Every,
        exclusive = (function() local l = {} for _, e in ipairs(Config.Rewards.Items) do l[#l + 1] = { item = e[1], label = e[2] } end return l end)(),
        vipWeapons = (function() local l = {} for _, e in ipairs(Config.Rewards.VipWeapons) do l[#l + 1] = { item = e[1], label = e[2] } end return l end)(),
        me = GetPlayerServerId(PlayerId()),
        drops = Config.Airdrops.Interval, cars = Config.Vehicles.Count, hp = Config.Player.MaxHealth, dmgMult = Config.Player.Damage,
    }
end

RegisterCommand(Config.Command, function()
    if Z.active then
        return Z.notify(('You are already in a lobby. Type /%s to leave.'):format(Config.LeaveCommand))
    end
    SetNuiFocus(true, true)
    SendNUIMessage({ a = 'lobby', data = uiData() })
    TriggerServerEvent('zdm:browse')
    TriggerServerEvent('zdm:stats')
end, false)

RegisterCommand(Config.LeaveCommand, function()
    if Z.active then TriggerServerEvent('zdm:leave') end
end, false)

RegisterNetEvent('zdm:browse', function(maps) SendNUIMessage({ a = 'browse', maps = maps }) end)
RegisterNetEvent('zdm:stats', function(data) SendNUIMessage({ a = 'stats', data = data }) end)

local queued = false

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    if queued then TriggerServerEvent('zdm:queueLeave') end
    cb(1)
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('zdm:browse')
    TriggerServerEvent('zdm:stats')
    cb(1)
end)

RegisterNUICallback('solo', function(d, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('zdm:solo', d.map, d.primary, d.secondary, d.round)
    cb(1)
end)

RegisterNUICallback('queueJoin', function(d, cb)
    TriggerServerEvent('zdm:queueJoin', d.map, d.primary, d.secondary, d.round)
    cb(1)
end)
RegisterNUICallback('joinGame', function(d, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('zdm:joinGame', d.game, d.primary, d.secondary)
    cb(1)
end)
RegisterNUICallback('queueLeave', function(_, cb) TriggerServerEvent('zdm:queueLeave'); cb(1) end)
RegisterNUICallback('queueReady', function(d, cb) TriggerServerEvent('zdm:queueReady', d.on); cb(1) end)
RegisterNUICallback('queueStart', function(_, cb) TriggerServerEvent('zdm:queueStart'); cb(1) end)

-- matchmaking updates (data = nil when you left the queue; started = true when your game is starting)
RegisterNetEvent('zdm:queue', function(data, started)
    queued = data ~= nil
    SendNUIMessage({ a = 'queue', q = data, started = started })
    if started then SetNuiFocus(false, false) end
end)

RegisterNUICallback('settings', function(d, cb)
    Z.settings.bars = d.bars ~= false
    Z.settings.outline = d.outline ~= false
    cb(1)
end)

---------------------------------------------------------------------------
-- start / stop
---------------------------------------------------------------------------
local function teleport(c)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetPedCoordsKeepVehicle(ped, c.x, c.y, c.z)
    local t = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(0) end
end

RegisterNetEvent('zdm:start', function(i, solo)
    local m = Config.Maps[i]
    if not m then return end
    DoScreenFadeOut(500); Wait(600)
    Z.active = { map = i, center = m.center, label = m.label, radius = m.radius or Config.BorderRadius, direct = m.direct }
    Z.downed, Z.infected, Z.round, Z.out = false, false, nil, false
    if Z.resetAbilities then Z.resetAbilities() end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then TaskLeaveAnyVehicle(ped, 0, 16); Wait(300) end
    teleport(m.center)
    Z.buffPlayer()
    Z.setup()
    Wait(500); DoScreenFadeIn(800)
    SendNUIMessage({ a = 'hud', show = true, label = m.label, me = GetPlayerServerId(PlayerId()), leave = Config.LeaveCommand })
    Z.notify(('Welcome to %s. Survive the rounds! Keys 1 / 2 switch weapons. /%s to leave.'):format(m.label, Config.LeaveCommand), 'success')
end)

RegisterNetEvent('zdm:lives', function(left)
    Z.livesLeft = left
    SendNUIMessage({ a = 'lives', left = left })
    if left == 1 then Z.notify('You died! 1 life left - die again and you are OUT.', 'error') end
end)

RegisterNetEvent('zdm:board', function(board)
    if board.mode == 'out' then Z.out = true end
    SendNUIMessage({ a = 'board', board = board, me = GetPlayerServerId(PlayerId()) })
end)

RegisterNetEvent('zdm:stop', function(back)
    local was = Z.active
    if Z.resetAbilities then Z.resetAbilities() end
    Z.active, Z.round = nil, nil
    Z.downed, Z.infected, Z.out, Z.livesLeft = false, false, false, nil
    Z.cleanup()
    if Z.clearPap then Z.clearPap() end
    if Z.cleanupExtras then Z.cleanupExtras() end
    SendNUIMessage({ a = 'hud', show = false })
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    SetSwimMultiplierForPlayer(PlayerId(), 1.0)
    Z.setMutation(nil)
    SetEntityMaxHealth(ped, 200)
    if GetEntityHealth(ped) > 200 then SetEntityHealth(ped, 200) end
    if back then
        DoScreenFadeOut(500); Wait(600)
        if IsEntityDead(ped) then NetworkResurrectLocalPlayer(back.x, back.y, back.z, 0.0, true, false) end
        teleport(back)
        SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
        Wait(300); DoScreenFadeIn(800)
    end
    if was then Z.notify('You left the zombie lobby. Your inventory is back.', 'success') end
end)

---------------------------------------------------------------------------
-- lobby state (every second) + rounds
---------------------------------------------------------------------------
local blips = {}

RegisterNetEvent('zdm:state', function(st)
    if not Z.active then return end
    Z.round = st
    SendNUIMessage({ a = 'state', st = st })
    local keep, me = {}, GetPlayerServerId(PlayerId())
    for _, p in ipairs(st.list or {}) do
        if p.id ~= me then
            local pl = GetPlayerFromServerId(p.id)
            if pl ~= -1 then
                local ped = GetPlayerPed(pl)
                keep[p.id] = true
                if not blips[p.id] or not DoesBlipExist(blips[p.id]) or GetBlipInfoIdEntityIndex(blips[p.id]) ~= ped then
                    if blips[p.id] and DoesBlipExist(blips[p.id]) then RemoveBlip(blips[p.id]) end
                    local b = AddBlipForEntity(ped)
                    SetBlipSprite(b, 1); SetBlipColour(b, 27); SetBlipScale(b, 0.85)
                    ShowHeadingIndicatorOnBlip(b, true)
                    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Teammate: ' .. p.name); EndTextCommandSetBlipName(b)
                    blips[p.id] = b
                end
            end
        end
    end
    for id, b in pairs(blips) do
        if not keep[id] then
            if DoesBlipExist(b) then RemoveBlip(b) end
            blips[id] = nil
        end
    end
end)

function Z.clearBlips()
    for id, b in pairs(blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
        blips[id] = nil
    end
end

RegisterNetEvent('zdm:round', function(kind, round, n, reward, mut)
    if not Z.active then return end
    local M = mut and Config.Mutations.List[mut]
    SendNUIMessage({ a = 'round', kind = kind, round = round, n = n, reward = reward, mut = M and { label = M.label, desc = M.desc, key = mut } or nil })
    if kind == 'start' then Z.setMutation(mut) else Z.setMutation(nil) end
    if kind == 'over' then
        Z.cleanup()
        if Z.clearPap then Z.clearPap() end
        Z.notify(('GAME OVER - you survived %d round%s.'):format(math.max(0, round - 1), round - 1 == 1 and '' or 's'), 'error')
    elseif kind == 'clear' then
        if reward and reward > 0 then
            Z.notify(('Round %d cleared! +$%s to your bank. Next round in %ds.'):format(round, tostring(reward), n), 'success')
        else
            Z.notify(('Round %d cleared! Ammo resupplied. Next round in %ds.'):format(round, n), 'success')
        end
    end
end)

RegisterNetEvent('zdm:loot', function(items) SendNUIMessage({ a = 'loot', items = items }) end)

RegisterNetEvent('zdm:reward', function(kind, label, extra)
    SendNUIMessage({ a = 'reward', kind = kind, label = label, extra = extra })
    if kind == 'car' then
        Z.notify(('You won a VIP car: %s! It is in your garage (plate %s).'):format(label, tostring(extra)), 'success')
    else
        Z.notify(('You won: %s! You keep it when you leave.'):format(label), 'success')
    end
end)

---------------------------------------------------------------------------
-- downed / respawn
---------------------------------------------------------------------------
function Z.down()
    if Z.downed or not Z.active then return end
    Z.downed = true
    local ped = PlayerPedId()
    SetEntityInvincible(ped, true)
    SetPedToRagdoll(ped, 8000, 8000, 0, false, false, false)
    AnimpostfxPlay('DeathFailOut', 0, false)
    SendNUIMessage({ a = 'dead', secs = Config.RespawnSeconds, lives = Z.livesLeft })
    TriggerServerEvent('zdm:died')
    CreateThread(function()
        Wait(Config.RespawnSeconds * 1000)
        if Z.out then return end -- no lives left: stay down, scoreboard is showing
        AnimpostfxStop('DeathFailOut')
        if not Z.active then Z.downed = false return end
        DoScreenFadeOut(400); Wait(450)
        local c = Z.active.center
        local p = PlayerPedId()
        if IsEntityDead(p) then
            NetworkResurrectLocalPlayer(c.x, c.y, c.z, 0.0, true, false)
            p = PlayerPedId()
        end
        ClearPedTasksImmediately(p)
        teleport(c)
        Z.buffPlayer()
        Z.cure()
        SetEntityInvincible(p, false)
        Z.downed = false
        TriggerServerEvent('zdm:alive')
        SendNUIMessage({ a = 'alive' })
        Wait(300); DoScreenFadeIn(600)
    end)
end

CreateThread(function()
    while true do
        if Z.active and not Z.downed then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or GetEntityHealth(ped) <= 110 then Z.down() end
            Wait(150)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- infection
---------------------------------------------------------------------------
local infHits, infLast, infNeed = 0, 0, nil

local function rollNeed()
    local c = Config.Infection
    local n = math.random(c.HitsMin or 3, c.HitsMax or 4)
    if Z.mut == 'toxic' then n = n - 1 end
    return math.max(1, n)
end

-- called on every zombie hit: infects only after enough hits close together
function Z.infectHit()
    if Z.infected then return end
    local now = GetGameTimer()
    if now - infLast > (Config.Infection.Window or 45000) then infHits = 0; infNeed = nil end
    infLast = now
    infNeed = infNeed or rollNeed()
    infHits = infHits + 1
    if infHits >= infNeed then Z.infect() end
end

function Z.infect()
    if Z.infected then return end
    infHits, infNeed = 0, nil
    Z.infected = true
    SendNUIMessage({ a = 'infected', on = true })
    Z.notify("You've been infected! Use a Z-Antidote.", 'error')
end

function Z.cure()
    Z.infected = false
    infHits, infNeed = 0, nil
    SendNUIMessage({ a = 'infected', on = false })
end

CreateThread(function()
    while true do
        Wait(Config.Infection.Tick)
        if Z.active and Z.infected and not Z.downed then
            local ped = PlayerPedId()
            local hp = GetEntityHealth(ped) - Config.Infection.Damage
            if hp <= 110 then Z.down() else SetEntityHealth(ped, hp) end
            if not IsPlayerFreeAiming(PlayerId()) then ShakeGameplayCam('DRUNK_SHAKE', Config.Infection.Shake or 0.08) end
        end
    end
end)

---------------------------------------------------------------------------
-- border
---------------------------------------------------------------------------
local nearEdge, warned = false, false

-- the zone is a square: this far from the centre on X and Y
local function edgeDist(p, c)
    return math.max(math.abs(p.x - c.x), math.abs(p.y - c.y))
end
Z.edgeDist = edgeDist

CreateThread(function()
    while true do
        if Z.active then
            local c = Z.active.center
            local p = GetEntityCoords(PlayerPedId())
            local d = edgeDist(p, c)
            local RAD = Z.active.radius or Config.BorderRadius
            nearEdge = d > RAD - math.min(260.0, RAD * 0.5)
            if d > RAD and not Z.downed then
                DoScreenFadeOut(250); Wait(300)
                teleport(c)
                Wait(200); DoScreenFadeIn(500)
                Z.notify('You cannot leave the area!', 'error')
            end
            local warn = d > (Z.active.radius and Z.active.radius ~= Config.BorderRadius and RAD - 25.0 or Config.BorderWarning)
            if warn or warned then
                SendNUIMessage({ a = 'border', show = warn, left = math.max(0, math.floor(RAD - d)) })
                warned = warn
            end
            Wait(250)
        else
            nearEdge = false
            Wait(1000)
        end
    end
end)

-- the visible wall: four glowing walls with a neon grid, seen from both sides
local function quad(a, b, c2, d, r, g, bl, al)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c2.x, c2.y, c2.z, r, g, bl, al)
    DrawPoly(a.x, a.y, a.z, c2.x, c2.y, c2.z, d.x, d.y, d.z, r, g, bl, al)
    DrawPoly(c2.x, c2.y, c2.z, b.x, b.y, b.z, a.x, a.y, a.z, r, g, bl, al)
    DrawPoly(d.x, d.y, d.z, c2.x, c2.y, c2.z, a.x, a.y, a.z, r, g, bl, al)
end

CreateThread(function()
    while true do
        if Z.active and nearEdge then
            local c, R = Z.active.center, Z.active.radius or Config.BorderRadius
            local W = Config.BorderWall or {}
            local col = W.color or { 168, 85, 247 }
            local al = W.alpha or 55
            local z0, z1 = c.z - 60.0, c.z + (W.height or 140.0)
            local corners = { vector2(c.x - R, c.y - R), vector2(c.x + R, c.y - R), vector2(c.x + R, c.y + R), vector2(c.x - R, c.y + R) }
            local pz = GetEntityCoords(PlayerPedId()).z
            for i = 1, 4 do
                local p1, p2 = corners[i], corners[i % 4 + 1]
                quad(vector3(p1.x, p1.y, z0), vector3(p2.x, p2.y, z0), vector3(p2.x, p2.y, z1), vector3(p1.x, p1.y, z1), col[1], col[2], col[3], al)
                -- neon grid lines around the player's height
                for k = -2, 6 do
                    local lz = math.floor(pz / 8.0) * 8.0 + k * 8.0
                    if lz > z0 and lz < z1 then
                        DrawLine(p1.x, p1.y, lz, p2.x, p2.y, lz, col[1], col[2], col[3], 160)
                    end
                end
                DrawLine(p1.x, p1.y, z0, p1.x, p1.y, z1, 255, 255, 255, 200)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- cleanup on resource stop
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if Z.active then
        Z.cleanup()
        SetEntityInvincible(PlayerPedId(), false)
    end
end)

---------------------------------------------------------------------------
-- my health bar (zombie style) + low health warning
---------------------------------------------------------------------------
CreateThread(function()
    local lastHp, lastAr = -1, -1
    while true do
        if Z.active then
            local ped = PlayerPedId()
            local max = math.max(1, GetEntityMaxHealth(ped) - 110)
            local hp = math.max(0, math.min(100, math.floor((GetEntityHealth(ped) - 110) / max * 100 + 0.5)))
            local ar = GetPedArmour(ped)
            if hp ~= lastHp or ar ~= lastAr then
                SendNUIMessage({ a = 'me', hp = hp, ar = ar, down = Z.downed })
                lastHp, lastAr = hp, ar
            end
            Wait(150)
        else
            lastHp, lastAr = -1, -1
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- steady aim: no camera shake while aiming in a game
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        if Z.active and Config.SteadyAim and IsPlayerFreeAiming(PlayerId()) then
            if IsGameplayCamShaking() then StopGameplayCamShaking(true) end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

---------------------------------------------------------------------------
-- no friendly fire inside a match (back to normal PvP when you leave)
---------------------------------------------------------------------------
local ffOff = false
local TEAM = GetHashKey('ZDM_SURVIVORS')
CreateThread(function()
    AddRelationshipGroup('ZDM_SURVIVORS')
    SetRelationshipBetweenGroups(0, TEAM, TEAM)
    while true do
        if Z.active and not Config.FriendlyFire then
            local pid, ped = PlayerId(), PlayerPedId()
            NetworkSetFriendlyFireOption(false)
            SetCanAttackFriendly(ped, false, false)
            SetPedRelationshipGroupHash(ped, TEAM)
            for _, p in ipairs(GetActivePlayers()) do
                if p ~= pid then
                    local other = GetPlayerPed(p)
                    if other ~= 0 then
                        SetEntityCanBeDamagedByRelationshipGroup(ped, false, TEAM)
                        SetPedRelationshipGroupHash(other, TEAM)
                    end
                end
            end
            ffOff = true
            Wait(500)
        else
            if ffOff then
                ffOff = false
                local ped = PlayerPedId()
                NetworkSetFriendlyFireOption(true)
                SetCanAttackFriendly(ped, true, false)
                SetEntityCanBeDamagedByRelationshipGroup(ped, true, TEAM)
                SetPedRelationshipGroupHash(ped, GetHashKey('PLAYER'))
            end
            Wait(1000)
        end
    end
end)
