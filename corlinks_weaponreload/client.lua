-- Corlinks auto reload: when your magazine hits 0 and you still have the ammo item, it reloads for you.
-- Works with ox_inventory (uses its own reload so ammo is taken from your inventory properly).
local ENABLED  = true
local COOLDOWN = 1200   -- ms between auto reload attempts
local last = 0

local function oxReload()
    -- 1) ox_inventory's own reload keybind (same as pressing R)
    ExecuteCommand('+reloadweapon')
    Wait(60)
    ExecuteCommand('-reloadweapon')
    Wait(400)
    local ped = PlayerPedId()
    local ok, clip = GetAmmoInClip(ped, GetSelectedPedWeapon(ped))
    if IsPedReloading(ped) or (ok and clip > 0) then return end
    -- 2) fallback: use the ammo item directly
    pcall(function()
        local cw = exports.ox_inventory:getCurrentWeapon()
        if not cw or not cw.ammo then return end
        local slots = exports.ox_inventory:Search('slots', cw.ammo)
        if slots and slots[1] then
            table.sort(slots, function(a, b) return (a.count or 0) < (b.count or 0) end)
            exports.ox_inventory:useSlot(slots[1].slot)
        end
    end)
end

CreateThread(function()
    while true do
        local sleep = 250
        if ENABLED then
            local ped = PlayerPedId()
            if IsPedArmed(ped, 4) and not IsPedDeadOrDying(ped, true) then
                sleep = 100
                local weapon = GetSelectedPedWeapon(ped)
                local ok, clip = GetAmmoInClip(ped, weapon)
                if ok and clip == 0 and not IsPedReloading(ped) and GetGameTimer() - last > COOLDOWN then
                    last = GetGameTimer()
                    oxReload()
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterCommand('gunreload', function()
    ENABLED = not ENABLED
    TriggerEvent('chat:addMessage', { args = { 'Auto reload', ENABLED and 'ON' or 'OFF' } })
end, false)
