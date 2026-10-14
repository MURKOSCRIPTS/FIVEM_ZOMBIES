-- corlinks_zombies - client: custom zombie items (used from ox_inventory)

local function heal(amount)
    local ped = PlayerPedId()
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + amount))
end

local function busy(label, ms, dict, clip)
    return lib.progressCircle({
        duration = ms, label = label, position = 'bottom', useWhileDead = false, canCancel = true,
        disable = { car = true, combat = true },
        anim = dict and { dict = dict, clip = clip } or nil,
    })
end

-- Field Medkit: full heal + stops bleeding
exports('medkit', function(data, slot)
    if Z.downed then return end
    if not busy('Using field medkit...', 4500, 'amb@medic@standing@tendtodead@idle_a', 'idle_a') then return end
    exports.ox_inventory:useItem(data, function(used)
        if not used then return end
        heal(200)
        ClearPedBloodDamage(PlayerPedId())
        lib.notify({ title = 'Field Medkit', description = 'Fully healed.', type = 'success' })
    end)
end)

-- Z-Antidote: cures infection + small heal
exports('antidote', function(data, slot)
    if Z.downed then return end
    if not busy('Injecting antidote...', 2500, 'mp_suicide', 'pill') then return end
    exports.ox_inventory:useItem(data, function(used)
        if not used then return end
        Z.cure()
        heal(25)
        lib.notify({ title = 'Z-Antidote', description = 'Infection cured.', type = 'success' })
    end)
end)

-- Adrenaline Shot: run faster with endless stamina for 20s
local adrenaline = false
exports('adrenaline', function(data, slot)
    if Z.downed or adrenaline then return end
    if not busy('Adrenaline...', 1500, 'mp_suicide', 'pill') then return end
    exports.ox_inventory:useItem(data, function(used)
        if not used then return end
        adrenaline = true
        local pid = PlayerId()
        SetRunSprintMultiplierForPlayer(pid, 1.49)
        AnimpostfxPlay('RaceTurbo', 0, true)
        lib.notify({ title = 'Adrenaline', description = '20 seconds of speed!', type = 'inform' })
        CreateThread(function()
            local stop = GetGameTimer() + 20000
            while GetGameTimer() < stop do
                RestorePlayerStamina(pid, 1.0)
                Wait(250)
            end
            SetRunSprintMultiplierForPlayer(pid, Z.active and (Z.baseSpeed and Z.baseSpeed() or math.min(1.49, Config.Player.Speed or 1.0)) or 1.0)
            AnimpostfxStop('RaceTurbo')
            adrenaline = false
        end)
    end)
end)
