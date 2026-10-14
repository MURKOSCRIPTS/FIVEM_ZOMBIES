-- corlinks_zombies - server: games (instances), matchmaking, rounds, inventory save/restore, kills, loot, stats
local QBCore = exports['qb-core']:GetCoreObject()
local R = Config.Rounds

local games = {}      -- [gameId] = { id, map, solo, members = {[src]=true}, round, phase, remaining, alive, aliveN, gen, phaseEnd }
local players = {}    -- [src] = { game, map, kills, deaths, prim, sec, last, joined, down, pap }
local queues = {}     -- [map] = { list = { {src, prim, sec, ready} ... }, gen, startAt }
local nextGame, nextZid = 0, 0
local recentDead = {} -- [zid] = { time, game }
local pending, hasPending, destroyGame -- crash resume (defined further down)
for i in ipairs(Config.Maps) do queues[i] = { list = {}, gen = 0, startAt = 0 } end

local function citizenid(src)
    local P = QBCore.Functions.GetPlayer(src)
    return P and P.PlayerData.citizenid
end

local function charName(src)
    local P = QBCore.Functions.GetPlayer(src)
    local c = P and P.PlayerData.charinfo
    return c and (c.firstname .. ' ' .. c.lastname) or GetPlayerName(src) or '?'
end

local function weaponDef(item)
    for _, w in ipairs(Config.Weapons) do
        if w.item == item then return w end
    end
end

local function inSlot(item, slot)
    local w = weaponDef(item)
    if not w then return false end
    for _, c in ipairs(Config.SlotCategories[slot] or {}) do
        if c == w.cat then return true end
    end
    return false
end

local function notify(src, msg, t) TriggerClientEvent('zdm:notify', src, msg, t) end

local function each(g, fn)
    for s in pairs(g.members) do fn(s) end
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `corlinks_zdm_saves` (
        `citizenid` VARCHAR(64) NOT NULL PRIMARY KEY, `items` LONGTEXT NULL, `coords` VARCHAR(128) NULL,
        `created` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP)]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `corlinks_zdm_stats` (
        `citizenid` VARCHAR(64) NOT NULL PRIMARY KEY, `name` VARCHAR(100) NULL,
        `kills` INT NOT NULL DEFAULT 0, `deaths` INT NOT NULL DEFAULT 0,
        `walkers` INT NOT NULL DEFAULT 0, `runners` INT NOT NULL DEFAULT 0, `brutes` INT NOT NULL DEFAULT 0,
        `games` INT NOT NULL DEFAULT 0, `playtime` INT NOT NULL DEFAULT 0,
        `best` INT NOT NULL DEFAULT 0, `best_round` INT NOT NULL DEFAULT 0)]])
end)

---------------------------------------------------------------------------
-- stats
---------------------------------------------------------------------------
local KIND_COL = { walker = 'walkers', runner = 'runners', brute = 'brutes' }

local function statAdd(src, sets)
    local cid = citizenid(src)
    if not cid then return end
    MySQL.query(('INSERT INTO corlinks_zdm_stats (citizenid, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name), %s'):format(sets),
        { cid, charName(src) })
end

RegisterNetEvent('zdm:stats', function()
    local src = source
    local cid = citizenid(src)
    local me = cid and MySQL.single.await('SELECT * FROM corlinks_zdm_stats WHERE citizenid = ?', { cid }) or nil
    local top = MySQL.query.await('SELECT citizenid, name, kills, deaths, best_round, games FROM corlinks_zdm_stats ORDER BY kills DESC LIMIT 15') or {}
    local rounds = MySQL.query.await('SELECT citizenid, name, kills, deaths, best_round, games FROM corlinks_zdm_stats WHERE best_round > 0 ORDER BY best_round DESC, kills DESC LIMIT 15') or {}
    for _, r in ipairs(top) do r.me = (r.citizenid == cid); r.citizenid = nil end
    for _, r in ipairs(rounds) do r.me = (r.citizenid == cid); r.citizenid = nil end
    TriggerClientEvent('zdm:stats', src, { me = me, top = top, rounds = rounds, name = charName(src), giveaway = GlobalState.zdmGiveaway or false })
end)

---------------------------------------------------------------------------
-- inventory save / restore
---------------------------------------------------------------------------
local function saveAndClear(src)
    local cid = citizenid(src)
    if not cid then return false end
    local items = exports.ox_inventory:GetInventoryItems(src) or {}
    local list = {}
    for _, it in pairs(items) do
        if type(it) == 'table' and it.name and (it.count or 0) > 0 then
            list[#list + 1] = { name = it.name, count = it.count, metadata = it.metadata, slot = it.slot }
        end
    end
    local p = GetEntityCoords(GetPlayerPed(src))
    MySQL.query.await('REPLACE INTO corlinks_zdm_saves (citizenid, items, coords) VALUES (?, ?, ?)',
        { cid, json.encode(list), json.encode({ p.x, p.y, p.z }) })
    if not MySQL.scalar.await('SELECT 1 FROM corlinks_zdm_saves WHERE citizenid = ?', { cid }) then return false end
    exports.ox_inventory:ClearInventory(src)
    return true
end

local function restore(src, keepTrophies)
    local cid = citizenid(src)
    if not cid then return nil end
    local row = MySQL.single.await('SELECT items, coords FROM corlinks_zdm_saves WHERE citizenid = ?', { cid })
    if not row then return nil end
    local keep = {}
    if keepTrophies then
        for _, name in ipairs(Config.KeepOnLeave) do
            local n = exports.ox_inventory:GetItemCount(src, name)
            if n and n > 0 then keep[name] = n end
        end
    end
    exports.ox_inventory:ClearInventory(src)
    for _, it in ipairs(json.decode(row.items or '[]') or {}) do
        local ok = exports.ox_inventory:AddItem(src, it.name, it.count, it.metadata, it.slot)
        if not ok then exports.ox_inventory:AddItem(src, it.name, it.count, it.metadata) end
    end
    for name, n in pairs(keep) do exports.ox_inventory:AddItem(src, name, n) end
    MySQL.query.await('DELETE FROM corlinks_zdm_saves WHERE citizenid = ?', { cid })
    local c = json.decode(row.coords or 'null')
    return c and vector3(c[1], c[2], c[3]) or nil
end

local function giveAmmo(src, d, share)
    local given = {}
    for _, item in ipairs({ d.prim, d.sec }) do
        local w = item and weaponDef(item)
        if w and w.ammo and not given[w.ammo] then
            given[w.ammo] = true
            exports.ox_inventory:AddItem(src, w.ammo, math.max(1, math.floor((w.amount or 60) * share)))
        end
    end
end

local function giveLoadout(src, d)
    local slot = 1
    for _, item in ipairs({ d.prim, d.sec }) do
        local w = item and weaponDef(item)
        if w then
            exports.ox_inventory:AddItem(src, w.item, 1, nil, slot) -- hotbar 1 / 2
            slot = slot + 1
        end
    end
    -- lethals first so they land on hotbar 4 / 5
    local L = Config.Lethals
    if L and L.Enabled then
        for _, e in ipairs(L.Start or {}) do
            if not exports.ox_inventory:AddItem(src, e[1], e[2], nil, e[3]) then exports.ox_inventory:AddItem(src, e[1], e[2]) end
        end
    end
    giveAmmo(src, d, 1.0)
    -- the rest of the kit goes from slot 6 up, keeping 3 free for Pack-a-Punch
    local slot2 = 6
    for _, k in ipairs(Config.Kit) do
        if not exports.ox_inventory:AddItem(src, k[1], k[2], nil, slot2) then exports.ox_inventory:AddItem(src, k[1], k[2]) end
        slot2 = slot2 + 1
    end
end

-- every round: top lethals back up (never above the max)
local function refillLethals(src)
    local L = Config.Lethals
    if not (L and L.Enabled) then return end
    local got = {}
    for _, e in ipairs(L.Refill or {}) do
        local have = exports.ox_inventory:GetItemCount(src, e[1]) or 0
        local add = math.min(e[2], (e[3] or e[2]) - have)
        if add > 0 and exports.ox_inventory:AddItem(src, e[1], add) then got[#got + 1] = e[1] end
    end
    if #got > 0 then TriggerClientEvent('zdm:loot', src, got) end
end

---------------------------------------------------------------------------
-- rounds
---------------------------------------------------------------------------
local function roundTotal(n) return R.Base + (n - 1) * R.PerRound end

local function gameState(g)
    local list = {}
    for s in pairs(g.members) do
        local d, ped = players[s], GetPlayerPed(s)
        list[#list + 1] = {
            id = s, name = GetPlayerName(s) or '?', kills = d and d.kills or 0, deaths = d and d.deaths or 0,
            down = d and d.down or false, out = d and d.out or false, points = d and d.points or 0,
            lives = d and (Config.Lives or 0) > 0 and math.max(0, Config.Lives + (d.bonusLives or 0) - d.deaths) or nil,
            health = ped ~= 0 and math.floor(math.max(0, GetEntityHealth(ped) - 100) / math.max(1, (Config.Player.MaxHealth or 200) - 100) * 100) or 0,
        }
    end
    table.sort(list, function(a, b) return a.kills > b.kills end)
    return {
        list = list, round = g.round, phase = g.phase, solo = g.solo,
        left = g.remaining + g.aliveN, total = g.round > 0 and roundTotal(g.round) or 0,
        timer = g.phaseEnd > 0 and math.max(0, math.ceil((g.phaseEnd - GetGameTimer()) / 1000)) or 0,
        hunt = g.phase == 'active' and g.remaining == 0 and g.aliveN <= R.HuntWhenLeft,
        dmg = math.min(R.DamageCap or 99, 1 + (math.max(1, g.round) - 1) * R.DamagePerRound),
        mut = g.mut, giveaway = GlobalState.zdmGiveaway or false,
    }
end

local function pushState(g)
    local st = gameState(g)
    each(g, function(s) TriggerClientEvent('zdm:state', s, st) end)
end

local function schedule(g, secs, fn)
    g.gen = g.gen + 1
    local gen, id = g.gen, g.id
    g.phaseEnd = GetGameTimer() + secs * 1000
    SetTimeout(secs * 1000, function()
        local cur = games[id]
        if cur and cur.gen == gen and next(cur.members) then fn(cur) end
    end)
end

local function startRound(g)
    g.round = g.round + 1
    g.phase, g.remaining, g.alive, g.aliveN, g.phaseEnd = 'active', roundTotal(g.round), {}, 0, 0
    g.mut, g.dogs = nil, false
    local M = Config.Mutations
    local DR = Config.DogRound
    if DR and DR.Enabled and DR.Every and DR.Every > 0 and g.round % DR.Every == 0 then
        -- hellhound round: only dogs, fewer of them
        g.dogs, g.mut = true, 'hounds'
        g.remaining = math.max(6, math.floor(roundTotal(g.round) * (DR.Scale or 0.6)))
    elseif M and M.Every and M.Every > 0 and g.round % M.Every == 0 then
        local keys = {}
        for k, v in pairs(M.List) do if not v.special then keys[#keys + 1] = k end end
        table.sort(keys)
        g.mut = keys[math.random(#keys)]
    end
    each(g, function(s) TriggerClientEvent('zdm:round', s, 'start', g.round, g.remaining, nil, g.mut) end)
    each(g, function(s) ZDM_GivePap(g, s) end)
    if g.round > (g.startRound or 1) then each(g, function(s) local d = players[s] if d and not d.out then refillLethals(s) end end) end
    pushState(g)
end

function ZDM_GivePap(g, s)
    local P = Config.PackAPunch
    if not P or g.round < P.Round then return end
    local d = players[s]
    if d and not d.pap then
        local w = P.Weapons[math.random(#P.Weapons)]
        d.pap = w.item
        local meta = {
            label = w.label .. ' (Pack-a-Punched)',
            description = 'Pack-a-Punched at round ' .. g.round .. '. Massive damage and knockback.',
        }
        if not exports.ox_inventory:AddItem(s, w.item, 1, meta, P.Slot) then exports.ox_inventory:AddItem(s, w.item, 1, meta) end
        if w.ammo then exports.ox_inventory:AddItem(s, w.ammo, w.amount or 300) end
        TriggerClientEvent('zdm:pap', s, w.item, w.label, w.melee and true or false)
    end
end

local function roundReward(n)
    local RR = Config.RoundRewards
    if not RR then return 0 end
    if RR.Special and RR.Special[n] then return RR.Special[n] end
    if RR.Every and RR.Every > 0 and n % RR.Every == 0 then return n * (RR.PerRound or 1000) end
    return 0
end

local function roundCleared(g)
    g.phase = 'intermission'
    local full = (g.startRound or 1) == 1 -- cash/prizes/leaderboard only for games started on round 1
    local reward = full and roundReward(g.round) or 0
    each(g, function(s)
        TriggerClientEvent('zdm:round', s, 'clear', g.round, R.Intermission, reward)
        local d = players[s]
        if reward > 0 then
            local P = QBCore.Functions.GetPlayer(s)
            if P then
                P.Functions.AddMoney(Config.RoundRewards.Account or 'bank', reward, ('zombies-round-%d'):format(g.round))
                print(('[corlinks_zombies] %s cleared round %d: +$%d'):format(GetPlayerName(s), g.round, reward))
            end
        end
        if d then
            ZDM_PayPoints(s, d, ('zombies-points-round-%d'):format(g.round))
            if g.dogs and Config.DogRound.MaxAmmo then
                giveAmmo(s, d, 1.0)
                TriggerClientEvent('zdm:maxammo', s)
            end
            if full and ZDM_RollRewards then ZDM_RollRewards(s, g.round) end
            giveAmmo(s, d, R.AmmoEachRound)
            if full then statAdd(s, ('best_round = GREATEST(best_round, %d)'):format(g.round)) end
        end
    end)
    schedule(g, R.Intermission, startRound)
    pushState(g)
end

local function checkRound(g)
    if g and g.phase == 'active' and g.remaining <= 0 and g.aliveN <= 0 then roundCleared(g) end
end

local leave -- forward (defined in "leaving")

-- whole team is out: scoreboard for everyone, then everybody goes home
local function gameOver(g)
    if g.phase == 'ended' then return end
    local board = scoreboard(g, 'over')
    g.phase, g.remaining, g.alive, g.aliveN = 'ended', 0, {}, 0
    g.gen = g.gen + 1 -- cancel any scheduled round
    each(g, function(s)
        TriggerClientEvent('zdm:round', s, 'over', g.round, board.secs)
        TriggerClientEvent('zdm:board', s, board)
    end)
    pushState(g)
    local id = g.id
    SetTimeout(board.secs * 1000, function()
        local cur = games[id]
        if not cur then return end
        local list = {}
        for s in pairs(cur.members) do list[#list + 1] = s end
        for _, s in ipairs(list) do leave(s, false) end
    end)
end

local function allOut(g)
    for s in pairs(g.members) do
        if players[s] and not players[s].out then return false end
    end
    return true
end

-- the end-of-game / eliminated scoreboard
local function scoreboard(g, mode)
    local list = {}
    for s in pairs(g.members) do
        local d = players[s]
        if d then list[#list + 1] = { id = s, name = GetPlayerName(s) or '?', kills = d.kills, deaths = d.deaths, out = d.out or false, points = d.points or 0 } end
    end
    for _, e in pairs(g.gone or {}) do list[#list + 1] = e end
    table.sort(list, function(a, b) return a.kills > b.kills end)
    return { mode = mode, round = g.round, start = g.startRound or 1, map = Config.Maps[g.map].label, list = list, secs = Config.ScoreboardSeconds or 12 }
end

local function allDown(g)
    for s in pairs(g.members) do
        if players[s] and not players[s].down then return false end
    end
    return true
end

local function removeZombie(g, zid, respawn)
    if not g or not g.alive[zid] then return false end
    g.alive[zid] = nil
    g.aliveN = g.aliveN - 1
    if respawn then g.remaining = g.remaining + 1 end
    return true
end

local function pickType(round, mut)
    local pool, total = {}, 0
    for key, t in pairs(Config.Types) do
        if round >= (t.from or 1) then
            local w = t.weight or 1
            if key ~= 'walker' then w = w + (round - (t.from or 1)) * 1.5 end -- more specials later on
            if mut == 'brutes' and key == 'brute' then w = w * 4 end
            pool[#pool + 1] = { key, w }
            total = total + w
        end
    end
    table.sort(pool, function(x, y) return x[1] < y[1] end)
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return 'walker'
end

local function myGame(src)
    local d = players[src]
    return d and games[d.game], d
end

RegisterNetEvent('zdm:want', function(room)
    local src = source
    local g, d = myGame(src)
    if not g or d.down or g.phase ~= 'active' then return end
    local n = math.min(tonumber(room) or 0, 5, g.remaining, R.MaxAlive - g.aliveN)
    if n <= 0 then return end
    local hunt = math.min(1.0, Config.Spawn.HuntChance + (g.round - 1) * Config.Spawn.HuntPerRound)
    local hpMult = math.min(R.HealthCap or 99, 1 + (g.round - 1) * R.HealthPerRound)
    local tickets, now = {}, GetGameTimer()
    for _ = 1, n do
        nextZid = nextZid + 1
        local key = g.dogs and 'hound' or pickType(g.round, g.mut)
        g.alive[nextZid] = now + 15000
        g.aliveN = g.aliveN + 1
        g.remaining = g.remaining - 1
        tickets[#tickets + 1] = { id = nextZid, type = key, hp = math.floor(Config.Types[key].health * hpMult), hunt = math.random() < hunt }
    end
    TriggerClientEvent('zdm:tickets', src, tickets)
end)

RegisterNetEvent('zdm:zdead', function(zid)
    local g = myGame(source)
    zid = tonumber(zid)
    if g and zid and removeZombie(g, zid, false) then
        recentDead[zid] = { time = GetGameTimer(), game = g.id }
        checkRound(g)
    end
end)

RegisterNetEvent('zdm:lost', function(zid)
    local g = myGame(source)
    zid = tonumber(zid)
    if g and zid and removeZombie(g, zid, true) then checkRound(g) end
end)

RegisterNetEvent('zdm:seen', function(ids)
    local g = myGame(source)
    if not g or type(ids) ~= 'table' then return end
    local t = GetGameTimer() + 12000
    for _, zid in ipairs(ids) do
        zid = tonumber(zid)
        if zid and g.alive[zid] then g.alive[zid] = t end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for _, g in pairs(games) do
            if g.phase == 'active' then
                local lost = {}
                for zid, seenUntil in pairs(g.alive) do
                    if now > seenUntil then lost[#lost + 1] = zid end
                end
                for _, zid in ipairs(lost) do removeZombie(g, zid, true) end
                if #lost > 0 then checkRound(g) end
            end
        end
        for zid, r in pairs(recentDead) do
            if now - r.time > 10000 then recentDead[zid] = nil end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        for _, g in pairs(games) do
            if next(g.members) then pushState(g) end
        end
    end
end)

---------------------------------------------------------------------------
-- lobby list (for the menu)
---------------------------------------------------------------------------
local function browse()
    local out = {}
    for i, m in ipairs(Config.Maps) do
        local names, best = {}, 0
        for _, g in pairs(games) do
            if g.map == i then
                for s in pairs(g.members) do names[#names + 1] = GetPlayerName(s) or ('#' .. s) end
                if g.round > best then best = g.round end
            end
        end
        local live = {}
        for _, g in pairs(games) do
            if g.map == i and next(g.members) then
                local n, list, host = 0, {}, nil
                for s in pairs(g.members) do
                    n = n + 1
                    list[#list + 1] = GetPlayerName(s) or ('#' .. s)
                    if not host or s < host then host = s end
                end
                local joinable = Config.Match.JoinInProgress and n < Config.Match.MaxPlayers and g.phase ~= 'ended'
                    and (not g.solo or Config.Match.JoinSolo)
                live[#live + 1] = { id = g.id, host = GetPlayerName(host) or '?', names = list, count = n,
                                    max = Config.Match.MaxPlayers, round = g.round, phase = g.phase,
                                    solo = g.solo, start = g.startRound or 1, joinable = joinable and true or false }
            end
        end
        table.sort(live, function(a, b) return a.id < b.id end)
        out[i] = { label = m.label, desc = m.desc, icon = m.icon, tags = m.tags or {}, open = m.center ~= nil,
                   count = #names, names = names, round = best, queued = #queues[i].list, live = live }
    end
    return out
end

local function pushBrowse() TriggerClientEvent('zdm:browse', -1, browse()) end

RegisterNetEvent('zdm:browse', function() TriggerClientEvent('zdm:browse', source, browse()) end)

---------------------------------------------------------------------------
-- joining a game
---------------------------------------------------------------------------
local joining = {}

-- unlimited carry weight while in a match (restored when you leave; a relog resets it anyway)
function ZDM_BigBag(src, d, on)
    local ok = pcall(function()
        if on then
            local inv = exports.ox_inventory:GetInventory(src)
            if inv and not d.oldWeight then d.oldWeight = inv.maxWeight end
            exports.ox_inventory:SetMaxWeight(src, 10000000)
        elseif d.oldWeight then
            exports.ox_inventory:SetMaxWeight(src, d.oldWeight)
        end
    end)
    if not ok then print('[corlinks_zombies] could not change carry weight (ox_inventory SetMaxWeight)') end
end

local function clampStart(r)
    r = math.floor(tonumber(r) or 1)
    return math.max(1, math.min(Config.Match.MaxStartRound or 100, r))
end

local function newGame(map, solo, startAt)
    nextGame = nextGame + 1
    startAt = clampStart(startAt)
    local g = { id = nextGame, map = map, solo = solo, members = {}, round = startAt - 1, startRound = startAt, phase = 'starting', remaining = 0,
                alive = {}, aliveN = 0, gen = 0, phaseEnd = 0 }
    local b = Config.BucketStart + g.id
    SetRoutingBucketPopulationEnabled(b, false)
    SetRoutingBucketEntityLockdownMode(b, 'inactive') -- players create the zombies
    games[g.id] = g
    return g
end

local function validLoadout(prim, sec)
    if prim and not inSlot(prim, 'primary') then prim = nil end
    if sec and not inSlot(sec, 'secondary') then sec = nil end
    return prim, sec
end

-- moves one player into a game (saves their inventory, gives the loadout). Must run in a thread.
local function enterGame(src, g, prim, sec)
    if players[src] or joining[src] or not GetPlayerName(src) or not citizenid(src) then return false end
    joining[src] = true
    restore(src, false) -- leftovers from a crash/restart
    if not saveAndClear(src) then
        joining[src] = nil
        notify(src, 'Could not save your inventory - nothing was changed. Try again.', 'error')
        return false
    end
    local d = { game = g.id, map = g.map, kills = 0, deaths = 0, prim = prim, sec = sec, last = 0, joined = os.time(), down = false, cid = citizenid(src) }
    players[src], g.members[src], joining[src] = d, true, nil
    ZDM_BigBag(src, d, true)
    giveLoadout(src, d)
    SetPlayerRoutingBucket(src, Config.BucketStart + g.id)
    Player(src).state:set('zdm', g.map, true)
    TriggerClientEvent('zdm:start', src, g.map, g.solo)
    print(('[corlinks_zombies] %s joined %s (game %d%s)'):format(GetPlayerName(src), Config.Maps[g.map].label, g.id, g.solo and ', solo' or ''))
    return true
end

local function hostOf(g)
    local h
    for s in pairs(g.members) do if not h or s < h then h = s end end
    return h
end

local function startGame(g)
    if not next(g.members) then games[g.id] = nil return end
    g.nextDrop = GetGameTimer() + (Config.Airdrops.First or 90) * 1000
    g.drops = {}
    local host = hostOf(g)
    if host and Config.Vehicles and Config.Vehicles.Count > 0 then
        TriggerClientEvent('zdm:cars', host, Config.Vehicles.Count, Config.Vehicles.Models)
    end
    if host then TriggerClientEvent('zdm:yachtKeeper', host, true) end
    schedule(g, R.FirstDelay, startRound)
    pushState(g)
    pushBrowse()
end

---------------------------------------------------------------------------
-- matchmaking
---------------------------------------------------------------------------
local function queueOf(src)
    for i, q in ipairs(queues) do
        for n, e in ipairs(q.list) do
            if e.src == src then return i, n, e end
        end
    end
end

local function pushQueue(i)
    local q = queues[i]
    local list = {}
    for _, e in ipairs(q.list) do
        local w = weaponDef(e.prim)
        list[#list + 1] = { id = e.src, name = GetPlayerName(e.src) or '?', prim = w and w.label or '—', ready = e.ready }
    end
    local data = { map = i, label = Config.Maps[i].label, players = list, max = Config.Match.MaxPlayers, startAt = q.list[1] and q.list[1].startAt or 1,
                   timer = q.startAt > 0 and math.max(0, math.ceil((q.startAt - GetGameTimer()) / 1000)) or nil }
    for _, e in ipairs(q.list) do TriggerClientEvent('zdm:queue', e.src, data) end
end

local launch -- forward

local function armQueue(i)
    local q = queues[i]
    local n = #q.list
    local allReady = n > 0
    for _, e in ipairs(q.list) do if not e.ready then allReady = false end end
    local secs
    if n >= Config.Match.MaxPlayers or (n >= 2 and allReady) then secs = Config.Match.ReadyStart
    elseif n >= 2 then secs = Config.Match.Countdown end
    if not secs then
        q.gen, q.startAt = q.gen + 1, 0
    else
        local at = GetGameTimer() + secs * 1000
        if q.startAt == 0 or at < q.startAt then
            q.gen, q.startAt = q.gen + 1, at
            local gen = q.gen
            SetTimeout(secs * 1000, function()
                if queues[i].gen == gen then launch(i) end
            end)
        end
    end
    pushQueue(i)
    pushBrowse()
end

launch = function(i)
    local q = queues[i]
    q.gen, q.startAt = q.gen + 1, 0
    local group = {}
    while #q.list > 0 and #group < Config.Match.MaxPlayers do
        group[#group + 1] = table.remove(q.list, 1)
    end
    if #group == 0 then return end
    for _, e in ipairs(group) do TriggerClientEvent('zdm:queue', e.src, nil, true) end
    local g = newGame(i, #group == 1, group[1].startAt) -- the first player in the queue picks the starting round
    CreateThread(function()
        for _, e in ipairs(group) do enterGame(e.src, g, e.prim, e.sec) end
        startGame(g)
    end)
    if #q.list > 0 then armQueue(i) else pushBrowse() end
end

local function leaveQueue(src, silent)
    local i, n = queueOf(src)
    if not i then return end
    table.remove(queues[i].list, n)
    if not silent then TriggerClientEvent('zdm:queue', src, nil) end
    armQueue(i)
end

RegisterNetEvent('zdm:solo', function(i, prim, sec, startAt)
    local src = source
    i = tonumber(i)
    local m = i and Config.Maps[i]
    if not m or not m.center or players[src] then return end
    prim, sec = validLoadout(prim, sec)
    if not prim and not sec then return notify(src, 'Pick a weapon first.', 'error') end
    leaveQueue(src, true)
    TriggerClientEvent('zdm:queue', src, nil, true)
    local g = newGame(i, true, startAt)
    CreateThread(function()
        enterGame(src, g, prim, sec)
        startGame(g)
    end)
end)

RegisterNetEvent('zdm:queueJoin', function(i, prim, sec, startAt)
    local src = source
    i = tonumber(i)
    local m = i and Config.Maps[i]
    if not m or not m.center or players[src] then return end
    prim, sec = validLoadout(prim, sec)
    if not prim and not sec then return notify(src, 'Pick a weapon first.', 'error') end
    leaveQueue(src, true)
    local list = queues[i].list
    list[#list + 1] = { src = src, prim = prim, sec = sec, ready = false, startAt = clampStart(startAt) }
    armQueue(i)
end)

RegisterNetEvent('zdm:queueLeave', function() leaveQueue(source) end)

-- jump into a match that's already running
RegisterNetEvent('zdm:joinGame', function(gid, prim, sec)
    local src = source
    if not Config.Match.JoinInProgress or players[src] then return end
    local g = games[tonumber(gid) or -1]
    if not g or not next(g.members) then
        TriggerClientEvent('zdm:browse', src, browse())
        return notify(src, 'That match has ended.', 'error')
    end
    if g.phase == 'ended' then return notify(src, 'That match just ended.', 'error') end
    if g.solo and not Config.Match.JoinSolo then return notify(src, 'That is a solo game.', 'error') end
    local n = 0
    for _ in pairs(g.members) do n = n + 1 end
    if n >= Config.Match.MaxPlayers then return notify(src, 'That match is full.', 'error') end
    prim, sec = validLoadout(prim, sec)
    if not prim and not sec then return notify(src, 'Pick a weapon first.', 'error') end
    leaveQueue(src, true)
    TriggerClientEvent('zdm:queue', src, nil, true)
    CreateThread(function()
        if not games[g.id] or not enterGame(src, g, prim, sec) then return end
        g.solo = false
        local name = GetPlayerName(src) or 'A survivor'
        each(g, function(s)
            if s ~= src then notify(s, name .. ' joined your match!', 'success') end
        end)
        Wait(2500) -- let their client finish loading in
        if not players[src] then return end
        if g.phase == 'active' then
            TriggerClientEvent('zdm:round', src, 'start', g.round, g.remaining + g.aliveN, nil, g.mut)
        end
        ZDM_GivePap(g, src)
        pushState(g)
        pushBrowse()
    end)
end)

RegisterNetEvent('zdm:queueReady', function(on)
    local i, _, e = queueOf(source)
    if not i then return end
    e.ready = on and true or false
    armQueue(i)
end)

RegisterNetEvent('zdm:queueStart', function()
    local i = queueOf(source)
    if i then launch(i) end
end)

---------------------------------------------------------------------------
-- leaving
---------------------------------------------------------------------------
pending = {} -- [citizenid] = { d = playerData, game = id, untilT = os.time() }

function hasPending(gid)
    for _, p in pairs(pending) do
        if p.game == gid and p.untilT > os.time() then return true end
    end
    return false
end

function destroyGame(g)
    games[g.id] = nil -- empty game: gone, and clean its private world
    local b = Config.BucketStart + g.id
    for _, pool in ipairs({ GetAllPeds(), GetAllVehicles(), GetAllObjects() }) do
        for _, e in ipairs(pool) do
            if DoesEntityExist(e) and GetEntityRoutingBucket(e) == b and not IsPedAPlayer(e) then DeleteEntity(e) end
        end
    end
end

leave = function(src, dropped)
    local d = players[src]
    if not d then return end
    local g = games[d.game]
    players[src] = nil
    if g then g.members[src] = nil end
    statAdd(src, ('games = games + 1, playtime = playtime + %d, best = GREATEST(best, %d)'):format(math.max(0, os.time() - d.joined), d.kills))
    local held = false
    if dropped and g and not d.out and g.phase ~= 'ended' and Config.Resume and Config.Resume.Enabled then
        local cid = d.cid
        if cid then
            pending[cid] = { d = d, game = g.id, untilT = os.time() + (Config.Resume.Minutes or 10) * 60 }
            held = true
            print(('[corlinks_zombies] holding a spot in game %d for %s (crash/disconnect)'):format(g.id, cid))
        end
    end
    if not dropped then
        ZDM_PayPoints(src, d, 'zombies-points')
        ZDM_BigBag(src, d, false)
        local back = restore(src, true)
        SetPlayerRoutingBucket(src, 0)
        Player(src).state:set('zdm', false, true)
        Player(src).state:set('zdm_ghost', false, true)
        TriggerClientEvent('zdm:stop', src, back)
    end
    if g then
        if not next(g.members) then
            if held or hasPending(g.id) then
                g.heldUntil = os.time() + (Config.Resume.Minutes or 10) * 60 -- everyone crashed: wait for them
            else
                destroyGame(g)
            end
        else
            local h = hostOf(g)
            if h then TriggerClientEvent('zdm:yachtKeeper', h, true) end
        end
        if not next(g.members) then
        elseif g.phase ~= 'ended' and allOut(g) then
            gameOver(g)
        end
    end
    pushBrowse()
end

RegisterNetEvent('zdm:leave', function() leave(source, false) end)
AddEventHandler('playerDropped', function()
    local src = source
    leaveQueue(src, true)
    leave(src, true) -- saved inventory comes back on next login
end)

local function recover(src)
    if players[src] then return end
    local back = restore(src, true)
    if back then
        SetPlayerRoutingBucket(src, 0)
        Player(src).state:set('zdm', false, true)
        TriggerClientEvent('zdm:stop', src, back)
        print(('[corlinks_zombies] restored saved inventory for %s'):format(GetPlayerName(src)))
    end
end

-- put a crashed player back into their match. Their zombie-mode items are still in their
-- inventory (ox saved it when they dropped) and their real items are still in corlinks_zdm_saves.
local function tryResume(src)
    if not (Config.Resume and Config.Resume.Enabled) or players[src] then return false end
    local cid = citizenid(src)
    local p = cid and pending[cid]
    if not p then return false end
    pending[cid] = nil
    local g = games[p.game]
    if not g or p.untilT < os.time() then
        notify(src, 'Your zombie match ended while you were away. Your inventory is back.', 'error')
        return false
    end
    local n = 0
    for _ in pairs(g.members) do n = n + 1 end
    if n >= Config.Match.MaxPlayers then
        notify(src, 'Your zombie match filled up while you were away. Your inventory is back.', 'error')
        return false
    end
    local d = p.d
    d.down, d.joined, d.last = false, os.time(), 0
    players[src], g.members[src], g.heldUntil = d, true, nil
    ZDM_BigBag(src, d, true)
    SetPlayerRoutingBucket(src, Config.BucketStart + g.id)
    Player(src).state:set('zdm', g.map, true)
    TriggerClientEvent('zdm:start', src, g.map, g.solo)
    local name = GetPlayerName(src) or 'A survivor'
    each(g, function(s) if s ~= src then notify(s, name .. ' is back in the match!', 'success') end end)
    print(('[corlinks_zombies] %s resumed game %d (round %d)'):format(name, g.id, g.round))
    if n == 0 then TriggerClientEvent('zdm:yachtKeeper', src, true) end
    CreateThread(function()
        Wait(2500)
        if not players[src] then return end
        notify(src, ('Welcome back! Resumed at round %d with %d kills.'):format(math.max(1, g.round), d.kills), 'success')
        if d.pap then
            for _, w in ipairs(Config.PackAPunch.Weapons) do
                if w.item == d.pap then TriggerClientEvent('zdm:pap', src, w.item, w.label, w.melee and true or false) break end
            end
        end
        if g.phase == 'active' then
            TriggerClientEvent('zdm:round', src, 'start', g.round, g.remaining + g.aliveN, nil, g.mut)
            if n == 0 then
                -- the whole team had crashed: the zombies that were alive are gone, re-queue them
                g.remaining, g.alive, g.aliveN = g.remaining + g.aliveN, {}, 0
            end
        elseif n == 0 then
            -- the match was frozen between rounds - get it going again
            schedule(g, 8, startRound)
        end
        pushState(g)
        pushBrowse()
    end)
    return true
end

-- private world guard: zombie players must stay in their game's own world, and nobody
-- else may sit in a zombie world. Some other scripts (spawn/apartments/ambulance/staff tools)
-- reset players to world 0 - this puts them straight back and logs who it was.
CreateThread(function()
    local lo, hi = Config.BucketStart, Config.BucketStart + 100000
    while true do
        Wait(1000)
        for src, d in pairs(players) do
            local want = Config.BucketStart + d.game
            if GetPlayerName(src) and GetPlayerRoutingBucket(src) ~= want then
                print(('^3[corlinks_zombies] %s was moved out of the zombie world (to %d) by another script - putting them back^7')
                    :format(GetPlayerName(src), GetPlayerRoutingBucket(src)))
                SetPlayerRoutingBucket(src, want)
                local ped = GetPlayerPed(src)
                local veh = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
                if veh ~= 0 then SetEntityRoutingBucket(veh, want) end
            end
        end
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local b = GetPlayerRoutingBucket(src)
            if not players[src] and not joining[src] and b >= lo and b < hi then
                SetPlayerRoutingBucket(src, 0)
                Player(src).state:set('zdm', false, true)
            end
        end
    end
end)

RegisterCommand('zdm_buckets', function(src)
    if src ~= 0 then return end
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local d = players[id]
        print(('%s [%d] world %d%s'):format(GetPlayerName(id), id, GetPlayerRoutingBucket(id),
            d and (' - in zombie game %d (should be world %d)'):format(d.game, Config.BucketStart + d.game) or ''))
    end
end, true)

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    SetTimeout(5000, function()
        if not tryResume(src) then recover(src) end
    end)
end)

-- held games / spots that nobody came back for
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for cid, p in pairs(pending) do
            if p.untilT < now then pending[cid] = nil end
        end
        for _, g in pairs(games) do
            if g.heldUntil and not next(g.members) and (g.heldUntil < now and not hasPending(g.id)) then
                print(('[corlinks_zombies] nobody came back to game %d, closing it'):format(g.id))
                destroyGame(g)
            end
        end
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetTimeout(6000, function()
        for _, s in ipairs(GetPlayers()) do recover(tonumber(s)) end
    end)
end)

RegisterCommand('zdm_restore', function(src, args)
    if src ~= 0 then return end
    local t = tonumber(args[1])
    if not t or not GetPlayerName(t) then return print('usage: zdm_restore <server id>') end
    if players[t] then leave(t, false) else recover(t) end
    print('[corlinks_zombies] done')
end, true)

---------------------------------------------------------------------------
-- kills, loot, deaths
---------------------------------------------------------------------------
local function pickLoot()
    local total = 0
    for _, l in ipairs(Config.Loot) do total = total + l[2] end
    local r = math.random() * total
    for _, l in ipairs(Config.Loot) do
        r = r - l[2]
        if r <= 0 then return l[1] end
    end
end

local credited = {}


---------------------------------------------------------------------------
-- points + multipliers
---------------------------------------------------------------------------
local PT = Config.Points or {}

local function multFor(streak)
    local m = 1
    for _, t in ipairs(PT.Tiers or {}) do if streak >= t.kills then m = t.mult end end
    return m
end

local function addPoints(src, d, base, why)
    if not PT.Enabled or base <= 0 then return end
    local m = multFor(d.streak or 0)
    local pts = math.floor(base * m + 0.5)
    d.points = (d.points or 0) + pts
    d.wallet = (d.wallet or 0) + pts
    TriggerClientEvent('zdm:points', src, pts, d.wallet, m, why)
end

-- turn unpaid points into money
function ZDM_PayPoints(src, d, why)
    if not PT.Enabled or not d then return 0 end
    local owed = (d.points or 0) - (d.paid or 0)
    local cash = math.floor(owed * (PT.CashRate or 0))
    if cash <= 0 then return 0 end
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return 0 end
    d.paid = d.points
    P.Functions.AddMoney(PT.Account or 'bank', cash, why or 'zombies-points')
    TriggerClientEvent('zdm:paid', src, cash, owed)
    return cash
end


---------------------------------------------------------------------------
-- in-game shop (K) - paid with points (wallet)
---------------------------------------------------------------------------
local SHOP = {}
for _, it in ipairs((Config.Shop and Config.Shop.Items) or {}) do SHOP[it.id] = it end

RegisterNetEvent('zdm:shopBuy', function(id)
    local src = source
    local g, d = myGame(src)
    local it = SHOP[id]
    local function fail(msg) TriggerClientEvent('zdm:shopResult', src, false, msg, d and d.wallet or 0) end
    if not (Config.Shop and Config.Shop.Enabled) or not it or not g or not d then return end
    if d.out then return fail('You are out of this match.') end
    if d.down then return fail('You can not shop while you are down.') end
    if g.round < (it.round or 1) then return fail(('%s unlocks on round %d.'):format(it.label, it.round)) end
    if (d.wallet or 0) < it.price then return fail('Not enough points.') end
    d.perks = d.perks or {}
    if it.kind == 'perk' and d.perks[id] then return fail('You already have ' .. it.label .. '.') end

    local ok = true
    if it.kind == 'weapon' then
        if (exports.ox_inventory:GetItemCount(src, it.item) or 0) == 0 then ok = exports.ox_inventory:AddItem(src, it.item, 1) and true or false end
        if ok and it.ammo then exports.ox_inventory:AddItem(src, it.ammo, it.amount or 100) end
        if ok then d.bought = d.bought or {}; d.bought[it.item] = it end
    elseif it.kind == 'item' then
        local n = it.count or 1
        if it.max then n = math.min(n, it.max - (exports.ox_inventory:GetItemCount(src, it.item) or 0)) end
        if n <= 0 then return fail(('You are already carrying the max %s.'):format(it.label)) end
        ok = exports.ox_inventory:AddItem(src, it.item, n) and true or false
    elseif it.kind == 'ammo' then
        giveAmmo(src, d, 1.0)
        for _, b in pairs(d.bought or {}) do if b.ammo then exports.ox_inventory:AddItem(src, b.ammo, b.amount or 100) end end
    elseif it.kind == 'perk' then
        d.perks[id] = true
        if id == 'extralife' then d.bonusLives = (d.bonusLives or 0) + 1 end
    end
    if not ok then return fail('No room for that right now.') end

    d.wallet = d.wallet - it.price
    TriggerClientEvent('zdm:points', src, 0, d.wallet, multFor(d.streak or 0), 'buy')
    TriggerClientEvent('zdm:shopResult', src, true, ('Bought %s'):format(it.label), d.wallet, id)
    if it.kind == 'perk' or it.kind == 'timed' or it.kind == 'armour' then
        TriggerClientEvent('zdm:ability', src, id, it.secs)
    end
    if id == 'extralife' then pushState(g) end
    if id == 'ghost' then
        Player(src).state:set('zdm_ghost', true, true)
        SetTimeout((it.secs or 60) * 1000, function() if GetPlayerName(src) then Player(src).state:set('zdm_ghost', false, true) end end)
    elseif id == 'shrink' then
        each(g, function(s) TriggerClientEvent('zdm:shrink', s, it.secs or 20, GetPlayerName(src)) end)
    elseif id == 'nuke' then
        local ped = GetPlayerPed(src)
        local c = GetEntityCoords(ped)
        each(g, function(s) TriggerClientEvent('zdm:nuke', s, c.x, c.y, c.z, GetPlayerName(src)) end)
        addPoints(src, d, 400, 'nuke')
    end
end)


---------------------------------------------------------------------------
-- Mystery Box
---------------------------------------------------------------------------
local MB = Config.MysteryBox or {}
local boxPool, boxVip = nil, {}
for _, n in ipairs(MB.Vip or {}) do boxVip[n] = true end

local function buildBoxPool()
    if boxPool then return boxPool end
    boxPool = {}
    local black = {}
    for _, n in ipairs(MB.Blacklist or {}) do black[n] = true end
    local ok, items = pcall(function() return exports.ox_inventory:Items() end)
    if ok and items then
        for name, it in pairs(items) do
            local up = name:upper()
            if up:sub(1, 7) == 'WEAPON_' and not black[up] and it.weapon and not it.throwable then
                boxPool[#boxPool + 1] = { item = name, label = it.label or name, ammo = it.ammoname, vip = boxVip[up] or false }
            end
        end
    end
    table.sort(boxPool, function(a, b) return a.item < b.item end)
    print(('[corlinks_zombies] mystery box: %d weapons in the pool'):format(#boxPool))
    return boxPool
end

local boxBusy = {}
RegisterNetEvent('zdm:boxOpen', function()
    local src = source
    local g, d = myGame(src)
    if not (MB.Enabled and g and d) or d.out or d.down then return end
    if boxBusy[src] and GetGameTimer() < boxBusy[src] then return end
    local price = MB.Price or 950
    if (d.wallet or 0) < price then return notify(src, ('The Mystery Box costs %d points.'):format(price), 'error') end
    local pool = buildBoxPool()
    if #pool == 0 then return notify(src, 'The Mystery Box is empty (no weapons found).', 'error') end
    d.wallet = d.wallet - price
    TriggerClientEvent('zdm:points', src, 0, d.wallet, multFor(d.streak or 0), 'buy')
    local spin = MB.SpinTime or 4.0
    boxBusy[src] = GetGameTimer() + math.floor(spin * 1000) + 1500
    -- names for the spinning animation
    local reel = {}
    for i = 1, 14 do reel[i] = pool[math.random(#pool)].label end
    local teddy = math.random() < (MB.TeddyChance or 0.06)
    local pick = pool[math.random(#pool)]
    TriggerClientEvent('zdm:boxSpin', src, reel, teddy and 'TEDDY' or pick.label, pick.vip, spin)
    SetTimeout(math.floor(spin * 1000), function()
        if players[src] ~= d then return end
        if teddy then
            d.wallet = d.wallet + math.floor(price / 2)
            TriggerClientEvent('zdm:points', src, 0, d.wallet, multFor(d.streak or 0), 'buy')
            return notify(src, 'Bye bye! The bear took your weapon - half your points back.', 'error')
        end
        if (exports.ox_inventory:GetItemCount(src, pick.item) or 0) == 0 then
            if not exports.ox_inventory:AddItem(src, pick.item, 1) then return notify(src, 'No room for the weapon.', 'error') end
        end
        if pick.ammo then exports.ox_inventory:AddItem(src, pick.ammo, MB.AmmoAmount or 300) end
        d.bought = d.bought or {}
        d.bought[pick.item] = { ammo = pick.ammo, amount = MB.AmmoAmount or 300 }
        TriggerClientEvent('zdm:boxGot', src, pick.item, pick.label, pick.vip)
    end)
end)

RegisterNetEvent('zdm:shopOpen', function()
    local src = source
    local g, d = myGame(src)
    if not g or not d then return end
    TriggerClientEvent('zdm:shopData', src, d.wallet or 0, g.round, d.perks or {})
end)

local hitWindow = {} -- [src] = { t = os.time(), n = hits this second }
RegisterNetEvent('zdm:hits', function(n)
    local src = source
    local g, d = myGame(src)
    n = math.floor(tonumber(n) or 0)
    if not g or not d or d.down or n <= 0 or g.phase ~= 'active' then return end
    local now = os.time()
    local w = hitWindow[src]
    if not w or w.t ~= now then w = { t = now, n = 0 }; hitWindow[src] = w end
    n = math.min(n, (PT.MaxHitsPerSecond or 12) - w.n)
    if n <= 0 then return end
    w.n = w.n + n
    addPoints(src, d, (PT.Hit or 10) * n, 'hit')
end)

RegisterNetEvent('zdm:kill', function(zid, kind, head, melee)
    local src = source
    local g, d = myGame(src)
    zid = tonumber(zid)
    if not g or not zid or credited[zid] then return end
    local rd = recentDead[zid]
    if not (g.alive[zid] or (rd and rd.game == g.id)) then return end
    credited[zid] = true
    SetTimeout(30000, function() credited[zid] = nil end)
    if g.alive[zid] then
        removeZombie(g, zid, false)
        recentDead[zid] = { time = GetGameTimer(), game = g.id }
    end
    if not Config.Types[kind] then kind = 'walker' end

    d.kills = d.kills + 1
    -- points + streak multiplier
    local before = multFor(d.streak or 0)
    d.streak = (d.streak or 0) + 1
    local after = multFor(d.streak)
    if after > before then TriggerClientEvent('zdm:mult', src, after, d.streak) end
    local base = (melee and PT.Melee) or (head and PT.Headshot) or PT.Kill or 60
    addPoints(src, d, base + ((PT.TypeBonus or {})[kind] or 0), melee and 'melee' or head and 'head' or 'kill')
    local col = KIND_COL[kind] or 'walkers'
    statAdd(src, ('kills = kills + 1, %s = %s + 1'):format(col, col))

    local got = {}
    if math.random() < Config.LootChance * (g.mut == 'glow' and 2 or 1) then
        local item = pickLoot()
        if item == 'AMMO' then
            giveAmmo(src, d, Config.AmmoLootShare or 0.25)
            got[#got + 1] = 'Ammo'
        elseif item then
            exports.ox_inventory:AddItem(src, item, 1)
            got[#got + 1] = item
        end
    end
    if kind == 'brute' and math.random() < Config.BrainChance then
        exports.ox_inventory:AddItem(src, 'zdm_brain', 1)
        got[#got + 1] = 'zdm_brain'
    end
    if #got > 0 then TriggerClientEvent('zdm:loot', src, got) end
    checkRound(g)
end)

RegisterNetEvent('zdm:died', function()
    local src = source
    local g, d = myGame(src)
    if not g or d.down then return end
    d.down = true
    d.deaths = d.deaths + 1
    if (d.streak or 0) > 0 and multFor(d.streak) > 1 then TriggerClientEvent('zdm:mult', src, 1, 0) end
    d.streak = 0
    statAdd(src, 'deaths = deaths + 1')
    local lives = (Config.Lives or 0) + (d.bonusLives or 0)
    if lives > 0 and d.deaths >= lives then
        -- out of lives
        d.out = true
        g.gone = g.gone or {}
        local name = GetPlayerName(src) or '?'
        each(g, function(s) if s ~= src then notify(s, name .. ' is OUT - no lives left!', 'error') end end)
        if allOut(g) then
            gameOver(g)
        else
            TriggerClientEvent('zdm:board', src, scoreboard(g, 'out'))
            local secs = Config.ScoreboardSeconds or 12
            SetTimeout(secs * 1000, function()
                local cur = players[src]
                if cur and cur == d then
                    g.gone[src] = { id = src, name = name, kills = d.kills, deaths = d.deaths, out = true, points = d.points or 0 }
                    leave(src, false)
                    pushState(g)
                end
            end)
        end
    else
        TriggerClientEvent('zdm:lives', src, lives > 0 and (lives - d.deaths) or -1)
    end
    pushState(g)
end)

RegisterNetEvent('zdm:alive', function()
    local src = source
    local _, d = myGame(src)
    if not d or not d.down then return end
    d.down = false
    giveAmmo(src, d, Config.AmmoRespawnShare or 0.75)
end)

---------------------------------------------------------------------------
-- Pack-a-Punch knockback: pass the push on to whoever controls each zombie
---------------------------------------------------------------------------
RegisterNetEvent('zdm:knock', function(list)
    local g, d = myGame(source)
    if not g or not d.pap or type(list) ~= 'table' then return end
    local bucket = Config.BucketStart + g.id
    for n, k in ipairs(list) do
        if n > 14 then break end
        local ent = tonumber(k[1]) and NetworkGetEntityFromNetworkId(tonumber(k[1])) or 0
        if ent ~= 0 and DoesEntityExist(ent) and Entity(ent).state.zdm and GetEntityRoutingBucket(ent) == bucket then
            local owner = NetworkGetEntityOwner(ent)
            if owner and owner > 0 then
                TriggerClientEvent('zdm:knock', owner, k[1], tonumber(k[2]) or 0.0, tonumber(k[3]) or 0.0, tonumber(k[4]) or 0.0)
            end
        end
    end
end)

---------------------------------------------------------------------------
-- screamers: tell everyone in the game so their zombies go into a frenzy
---------------------------------------------------------------------------
local spitCd = {}
RegisterNetEvent('zdm:spit', function(fx, fy, fz, tx, ty, tz)
    local src = source
    local g = myGame(src)
    if not g then return end
    local now = GetGameTimer()
    if spitCd[src] and now - spitCd[src] < 150 then return end
    spitCd[src] = now
    for _, v in ipairs({ fx, fy, fz, tx, ty, tz }) do if type(v) ~= 'number' then return end end
    if #(vector3(fx, fy, fz) - vector3(tx, ty, tz)) > 40.0 then return end
    each(g, function(s) TriggerClientEvent('zdm:spit', s, fx, fy, fz, tx, ty, tz) end)
end)

RegisterNetEvent('zdm:scream', function(x, y, z)
    local g = myGame(source)
    if not g then return end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return end
    each(g, function(s) TriggerClientEvent('zdm:scream', s, x, y, z) end)
end)

---------------------------------------------------------------------------
-- airdrops
---------------------------------------------------------------------------
local nextDrop = 0
local function inSquare(c, x, y, margin, rad)
    local R = rad or Config.BorderRadius
    return math.abs(x - c.x) <= R - margin and math.abs(y - c.y) <= R - margin
end

CreateThread(function()
    while true do
        Wait(3000)
        local now = GetGameTimer()
        for _, g in pairs(games) do
            if g.drops and next(g.members) and (g.phase == 'active' or g.phase == 'intermission') then
                if now >= (g.nextDrop or 0) then
                    g.nextDrop = now + (Config.Airdrops.Interval or 150) * 1000
                    local c = Config.Maps[g.map].center
                    local RAD = Config.Maps[g.map].radius or Config.BorderRadius
                    local x, y
                    for _ = 1, 20 do
                        local a, r = math.random() * math.pi * 2, math.min(60, RAD * 0.25) + math.random() * math.max(10, RAD - 120)
                        x, y = c.x + math.cos(a) * r, c.y + math.sin(a) * r
                        if inSquare(c, x, y, math.min(40, RAD * 0.2), RAD) then break end
                    end
                    nextDrop = nextDrop + 1
                    local drop = { id = nextDrop, x = x, y = y, z = c.z, landed = false, born = now }
                    g.drops[drop.id] = drop
                    local host = hostOf(g)
                    each(g, function(s) TriggerClientEvent('zdm:drop', s, drop, s == host) end)
                end
                for id, d in pairs(g.drops) do
                    if now - d.born > (Config.Airdrops.Expire or 240) * 1000 then
                        g.drops[id] = nil
                        each(g, function(s) TriggerClientEvent('zdm:dropGone', s, id) end)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('zdm:dropLanded', function(id, z)
    local g = myGame(source)
    local d = g and g.drops and g.drops[tonumber(id) or -1]
    if not d or d.landed then return end
    d.landed, d.z = true, tonumber(z) or d.z
    each(g, function(s) TriggerClientEvent('zdm:dropLanded', s, d.id, d.z) end)
end)

local function pickWeighted(list, wkey)
    local total = 0
    for _, e in ipairs(list) do total = total + (e[wkey] or 1) end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - (e[wkey] or 1)
        if r <= 0 then return e end
    end
    return list[1]
end

RegisterNetEvent('zdm:claim', function(id)
    local src = source
    local g = myGame(src)
    local d = g and g.drops and g.drops[tonumber(id) or -1]
    if not d or not d.landed then return end
    local p = GetEntityCoords(GetPlayerPed(src))
    if #(vector2(p.x, p.y) - vector2(d.x, d.y)) > 8.0 then return end
    g.drops[d.id] = nil
    local w = pickWeighted(Config.Airdrops.Loot, 'weight')
    exports.ox_inventory:AddItem(src, w.item, 1)
    if w.ammo then exports.ox_inventory:AddItem(src, w.ammo, w.amount or 300) end
    for _, e in ipairs(Config.Airdrops.Extras or {}) do exports.ox_inventory:AddItem(src, e[1], e[2]) end
    local who = GetPlayerName(src) or '?'
    each(g, function(s) TriggerClientEvent('zdm:dropGone', s, d.id, who, w.label) end)
end)

---------------------------------------------------------------------------
-- exclusive rewards + staff giveaway mode
---------------------------------------------------------------------------
GlobalState.zdmGiveaway = false
local giveawayGen = 0

local function chatAll(msg, color)
    TriggerClientEvent('chat:addMessage', -1, { color = color or { 192, 132, 252 }, multiline = true, args = { 'ZOMBIES', msg } })
end

-- adds an item to the player's SAVED inventory (the one they get back when they leave)
local function addToSaved(src, item, count, metadata)
    local cid = citizenid(src)
    if not cid then return false end
    local row = MySQL.single.await('SELECT items FROM corlinks_zdm_saves WHERE citizenid = ?', { cid })
    if not row then
        exports.ox_inventory:AddItem(src, item, count or 1, metadata)
        return true
    end
    local list = json.decode(row.items or '[]') or {}
    list[#list + 1] = { name = item, count = count or 1, metadata = metadata }
    MySQL.query.await('UPDATE corlinks_zdm_saves SET items = ? WHERE citizenid = ?', { json.encode(list), cid })
    return true
end

local function plateGen()
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
    for _ = 1, 20 do
        local p = 'ZOM'
        for _ = 1, 5 do local i = math.random(#chars); p = p .. chars:sub(i, i) end
        if not MySQL.scalar.await('SELECT 1 FROM player_vehicles WHERE plate = ?', { p }) then return p end
    end
    return 'ZOM' .. math.random(10000, 99999)
end

local function giveCar(src, model)
    local P = QBCore.Functions.GetPlayer(src)
    if not P then return false end
    local plate = plateGen()
    MySQL.insert.await('INSERT INTO player_vehicles (license, citizenid, vehicle, hash, mods, plate, garage, state) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        P.PlayerData.license, P.PlayerData.citizenid, model, GetHashKey(model), '{}', plate, Config.Rewards.CarGarage or 'pillboxgarage', 1,
    })
    return plate
end

function ZDM_RollRewards(src, round)
    local RW = Config.Rewards
    if not RW then return end
    local name = GetPlayerName(src) or '?'
    if GlobalState.zdmGiveaway and math.random() < (RW.GiveawayChance or 0.01) then
        if math.random() < 0.7 then
            local w = RW.VipWeapons[math.random(#RW.VipWeapons)]
            addToSaved(src, w[1], 1)
            TriggerClientEvent('zdm:reward', src, 'vip', w[2])
            chatAll(('🎁 %s won a VIP %s in the Zombies giveaway (round %d)!'):format(name, w[2], round), { 250, 204, 21 })
        else
            local model = RW.VipCars[math.random(#RW.VipCars)]
            local plate = giveCar(src, model)
            TriggerClientEvent('zdm:reward', src, 'car', model, plate)
            chatAll(('🚗 %s won a VIP car (%s) in the Zombies giveaway (round %d)!'):format(name, model, round), { 250, 204, 21 })
        end
        print(('[corlinks_zombies] GIVEAWAY prize to %s at round %d'):format(name, round))
        return
    end
    if math.random() < (RW.ItemChance or 0) then
        local total = 0
        for _, e in ipairs(RW.Items) do total = total + (e[3] or 1) end
        local r, pick = math.random() * total, RW.Items[1]
        for _, e in ipairs(RW.Items) do r = r - (e[3] or 1); if r <= 0 then pick = e break end end
        addToSaved(src, pick[1], 1)
        TriggerClientEvent('zdm:reward', src, 'item', pick[2])
        chatAll(('🎒 %s found a %s in the Zombies game mode!'):format(name, pick[2]))
    end
end

local function giveawayAllowed(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, Config.Rewards.GiveawayAce or 'corlinks.giveaway') or IsPlayerAceAllowed(src, 'command') then return true end
    local ok, has = pcall(function() return QBCore.Functions.HasPermission(src, 'admin') or QBCore.Functions.HasPermission(src, 'god') end)
    return ok and has
end

local function setGiveaway(on, minutes, by)
    giveawayGen = giveawayGen + 1
    GlobalState.zdmGiveaway = on and true or false
    if on then
        local gen = giveawayGen
        chatAll(('🎁 ZOMBIES GIVEAWAY IS LIVE%s! Survive rounds in /zombies for a chance at VIP weapons and VIP cars!'):format(minutes and (' for ' .. minutes .. ' minutes') or ''), { 250, 204, 21 })
        if minutes then
            SetTimeout(minutes * 60000, function()
                if giveawayGen == gen then setGiveaway(false, nil, 'timer') end
            end)
        end
    else
        chatAll('The Zombies giveaway has ended. Rewards are back to normal.')
    end
    print(('[corlinks_zombies] giveaway %s by %s'):format(on and 'ON' or 'OFF', tostring(by)))
end

RegisterCommand('giveaway', function(src, args)
    if (args[1] or ''):lower() ~= 'zombies' then
        if src ~= 0 then notify(src, 'Usage: /giveaway zombies [minutes] or /giveaway zombies off', 'error') end
        return
    end
    if not giveawayAllowed(src) then return notify(src, 'No permission.', 'error') end
    local a = (args[2] or ''):lower()
    if a == 'off' or a == 'stop' then return setGiveaway(false, nil, src == 0 and 'console' or GetPlayerName(src)) end
    local mins = tonumber(a)
    setGiveaway(true, mins and math.max(1, math.floor(mins)) or nil, src == 0 and 'console' or GetPlayerName(src))
end, false)

---------------------------------------------------------------------------
-- chat broadcast
---------------------------------------------------------------------------
CreateThread(function()
    local B = Config.Broadcast
    if not B or not B.Interval or B.Interval <= 0 then return end
    Wait(60000)
    while true do
        chatAll(B.Message)
        Wait(B.Interval * 60000)
    end
end)
