-- corlinks_zombies - client: Pack-a-Punch (damage boost + knockback)
local P = Config.PackAPunch
local pap = nil -- { hash, melee }

RegisterNetEvent('zdm:pap', function(item, label, melee)
    if not item then
        pap = nil
        SetPlayerWeaponDamageModifier(PlayerId(), 1.0)
        SetPlayerMeleeWeaponDamageModifier(PlayerId(), 1.0)
        return
    end
    pap = { hash = GetHashKey(item), melee = melee }
    SendNUIMessage({ a = 'pap', label = label, melee = melee })
    Z.notify(('PACK-A-PUNCH! %s is in hotbar slot %d.'):format(label, P.Slot), 'success')
end)

function Z.clearPap()
    pap = nil
    SetPlayerWeaponDamageModifier(PlayerId(), 1.0)
    SetPlayerMeleeWeaponDamageModifier(PlayerId(), 1.0)
end

local function holding()
    return pap and GetSelectedPedWeapon(PlayerPedId()) == pap.hash
end

-- damage boost: every weapon hits harder in the lobby, Pack-a-Punch stacks on top
CreateThread(function()
    local was = false
    while true do
        if Z.active then
            local pid = PlayerId()
            local base = ((Config.Player and Config.Player.Damage) or 1.0) * (Z.abilityDamage and Z.abilityDamage() or 1.0) * (Z.boxDamage and Z.boxDamage() or 1.0)
            local gun, melee = base, base
            if holding() then
                if pap.melee then melee = base * P.MeleeDamage else gun = base * P.GunDamage end
            end
            SetPlayerWeaponDamageModifier(pid, gun)
            SetPlayerMeleeWeaponDamageModifier(pid, melee)
            was = true
            Wait(0)
        else
            if was then
                SetPlayerWeaponDamageModifier(PlayerId(), 1.0)
                SetPlayerMeleeWeaponDamageModifier(PlayerId(), 1.0)
                was = false
            end
            Wait(500)
        end
    end
end)

local function push(ped, v)
    if NetworkHasControlOfEntity(ped) then
        SetPedToRagdoll(ped, 2500, 2500, 0, false, false, false)
        SetEntityVelocity(ped, v.x, v.y, v.z)
        return nil
    end
    return { NetworkGetNetworkIdFromEntity(ped), v.x, v.y, v.z }
end

-- someone hit a zombie we control with a Pack-a-Punched weapon
RegisterNetEvent('zdm:knock', function(netId, vx, vy, vz)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if ped ~= 0 and DoesEntityExist(ped) and Entity(ped).state.zdm then
        SetPedToRagdoll(ped, 2500, 2500, 0, false, false, false)
        SetEntityVelocity(ped, vx, vy, vz)
    end
end)

local lastKnock = 0
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not Z.active or not pap then return end
    local victim, attacker = args[1], args[2]
    local me = PlayerPedId()
    if attacker ~= me or not DoesEntityExist(victim) or not IsEntityAPed(victim) or not Entity(victim).state.zdm then return end
    if not holding() then return end
    local now = GetGameTimer()
    if now - lastKnock < 120 then return end
    lastKnock = now

    local mp = GetEntityCoords(me)
    local remote = {}
    local function knock(ped, force, up)
        local p = GetEntityCoords(ped)
        local dx, dy = p.x - mp.x, p.y - mp.y
        local len = math.max(0.1, math.sqrt(dx * dx + dy * dy))
        local r = push(ped, vector3(dx / len * force, dy / len * force, up))
        if r then remote[#remote + 1] = r end
    end

    if pap.melee then
        local vp = GetEntityCoords(victim)
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and Entity(ped).state.zdm and #(GetEntityCoords(ped) - vp) <= P.MeleeRadius then
                knock(ped, P.MeleeKnockback, 5.0)
            end
        end
        if not IsPlayerFreeAiming(PlayerId()) then ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.1) end
        SendNUIMessage({ a = 'sfx', s = 'smash', k = 'brute', v = 1.0, p = 0.0 })
    else
        knock(victim, P.GunKnockback, 1.5)
    end
    if #remote > 0 then TriggerServerEvent('zdm:knock', remote) end
end)
