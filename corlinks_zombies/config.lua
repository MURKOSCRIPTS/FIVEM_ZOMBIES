Config = {}

Config.Command      = 'zombies'   -- opens the lobby menu
Config.LeaveCommand = 'zleave'    -- leaves the lobby and gives your normal inventory back

-- Each map gets its own private world (routing bucket) starting at this number.
Config.BucketStart = 7100

-- Border: a glowing square wall this far (metres) from the map's centre in every direction. Past it you get sent back.
Config.BorderRadius  = 500.0
Config.BorderWarning = 450.0      -- warning starts here (maps with their own radius warn 50m before their edge)
-- A map can set its own size with  radius = 150.0  (see The Mansion)
Config.BorderWall    = { height = 140.0, color = { 168, 85, 247 }, alpha = 55 } -- the visible wall

Config.FriendlyFire = false       -- false = teammates can't shoot/hurt each other in zombie matches
-- Points (CoD Zombies style). Kill streaks (kills without going down) raise your multiplier.
-- Points are turned into bank money at the end of every round you clear (and when you leave).
Config.Points = {
    Enabled  = true,
    Hit      = 10,     -- every bullet/melee hit on a zombie
    Kill     = 60,     -- normal kill
    Headshot = 100,    -- headshot kill (replaces Kill)
    Melee    = 130,    -- melee kill (replaces Kill)
    TypeBonus = { runner = 10, bloater = 20, screamer = 30, brute = 60, hound = 40, jumper = 40, volatile = 50, tank = 150 },
    Tiers = {          -- kill streak -> multiplier
        { kills = 10,  mult = 1.5 },
        { kills = 25,  mult = 2 },
        { kills = 50,  mult = 3 },
        { kills = 100, mult = 4 },
    },
    CashRate = 0.5,    -- $ per point (1,000 points = $500)
    Account  = 'bank',
    MaxHitsPerSecond = 12,
}

Config.Lives = 2                  -- die this many times and you're OUT (scoreboard, then back to the city)
Config.ScoreboardSeconds = 12     -- how long the end scoreboard shows before you're sent back
Config.RespawnSeconds = 8         -- downed -> respawn at the map centre after this long

-- Your zombie ped(s). Put your custom ped's model name here once it's streamed.
-- More than one = random pick per zombie.
-- Zombie looks.
-- UseZombiePack = true  -> an add-on zombie ped pack (put its model names in PackModels)
-- UseZombiePack = false -> GTA's own zombie (u_m_y_zombie_01) - always safe
-- The pack crashed the game (GTA5_b3258.exe+13BF39A) the moment zombies spawned, so it is OFF until tested.
Config.UseZombiePack = false
Config.PackModels    = { }
Config.ZombieModels  = { 'u_m_y_zombie_01' }
Config.ZombieFallback = 'u_m_y_zombie_01'
Config.ZombieLod = 15.0  -- how far zombies keep full detail (1.0 = GTA default). Higher = nicer at range, a bit heavier
if Config.UseZombiePack then Config.ZombieModels = Config.PackModels end

-- Maps. Set center = vector3(...) to unlock a map. center = nil shows "Coming soon".
Config.Maps = {
    { label = 'LSIA Airport', desc = 'Open runways, hangars and the terminal. Nowhere to hide.', icon = '✈️', tags = { 'Open ground', 'Long range' }, center = vector3(-1136.94, -2935.73, 13.95) },
    { label = 'Grove Street', desc = 'Tight streets, alleys and yards in the hood.', icon = '🏚️', tags = { 'Close quarters', 'Alleys' }, center = vector3(-133.12, -1622.42, 32.48) },
    { label = 'Diamond Casino', desc = 'The casino grounds and car park. Neon, money and the dead.', icon = '🎰', tags = { 'Mixed range', 'Open lots' }, center = vector3(1153.12, 131.57, 81.53) },
    { label = 'The Farm', desc = 'Fields, barns and fences out in the hills. Nowhere to run.', icon = '🌾', tags = { 'Open fields', 'Long range' }, center = vector3(1445.78, 1112.53, 114.34) },
    { label = 'Bolingbroke Prison', desc = 'The state pen and the desert around it. Walls, towers and yards - the inmates have turned.', icon = '⛓️', tags = { 'Walls & towers', 'Long range' }, center = vector3(1660.08, 2524.37, 45.55) },
    { label = 'Sandy Shores Airfield', desc = 'A huge open airfield in the desert. Hangars, runway and nowhere to hide - grab a car.', icon = '🛩️', tags = { 'Huge', 'Vehicles', '700m zone' }, center = vector3(1585.4, 3217.16, 40.41), radius = 700.0 },
    { label = 'Sandy Motel', desc = 'The run-down motel off Route 68. Rooms, car park and open desert all around.', icon = '🏚️', tags = { 'Rooms', 'Mixed range' }, center = vector3(1563.01, 3571.78, 33.92) },
    { label = 'Chicken Factory', desc = 'The Paleto Bay chicken plant. Conveyor halls, loading bays and the dead on the line.', icon = '🐔', tags = { 'Indoors', 'Close quarters' }, center = vector3(-80.91, 6219.94, 31.09) },
    -- Add your own maps (custom MLOs / islands) like this:
    -- { label = 'My Map', desc = 'Short description.', icon = '🏝️', tags = { 'Custom map' }, center = vector3(x, y, z), radius = 300.0, direct = true },
    --   radius = zone size in metres, direct = true for custom MLOs (zombies chase in straight lines and follow your path),
    --   boats = { count = 5, models = { 'dinghy', 'jetmax' } } to spawn boats instead of cars.
}

-- Zombie spawning (zombies appear out of sight around the players, inside the border).
Config.Spawn = {
    MaxPerPlayer = 14,     -- most zombies one player keeps alive around themselves at once
    MinDist      = 45.0,   -- spawn at least this far away (and out of sight)
    MaxDist      = 120.0,  -- ...and at most this far
    DespawnDist  = 220.0,  -- zombies this far from every player get recycled (they come back later)
    Interval     = 1500,   -- ms between spawn requests
    HuntChance   = 1.0,    -- 1.0 = every zombie follows the players constantly (lower = some wander until they spot you)
    HuntPerRound = 0.08,   -- +8% per round
}

-- Rounds (Call of Duty Zombies style)
Config.Rounds = {
    Base         = 5,      -- zombies in round 1
    PerRound     = 5,      -- +5 every round (round 2 = 10, round 3 = 15 ...)
    MaxAlive     = 26,     -- most zombies alive at once in one lobby (the rest come as you kill)
    FirstDelay   = 10,     -- seconds before round 1 starts
    Intermission = 15,     -- seconds between rounds
    HealthPerRound = 0.06, -- zombies get +6% health every round...
    HealthCap      = 5.0,  -- ...up to 5x their normal health
    DamagePerRound = 0.03, -- zombies hit 3% harder every round...
    DamageCap      = 2.5,  -- ...up to 2.5x
    RunnersFrom  = 2,      -- runners start appearing this round
    BrutesFrom   = 4,      -- brutes start appearing this round
    HuntWhenLeft = 3,      -- when this many are left, they all hunt you and show on the map
    GameOverWhenAllDown = true, -- everyone down at the same time = game over, back to round 1
    AmmoEachRound = 0.30,  -- share of starting ammo everyone gets when a round is cleared
}

-- Zombie types. health = hit points, speed = 1.0 walk / 2.0 jog / 3.0 sprint, damage per hit.
-- weight = how common. sight = metres before a wandering zombie notices you.
Config.Types = {
    walker = { from = 1, label = 'Walker', desc = 'Slow and clumsy, but they never stop following you.', weight = 55, health = 220, speed = 1.2, damage = 14, sight = 40.0, clipset = 'move_m@drunk@verydrunk', color = { 166, 227, 112 } },
    runner = { from = 2, label = 'Runner', desc = 'Fast and fragile. Charges straight at you.', weight = 33, health = 150, speed = 2.0, damage = 11, sight = 60.0, rate = 1.12,                      color = { 251, 191, 36 } },
    brute  = { from = 4, label = 'Brute', desc = 'A walking tank. Soaks bullets and hits like a truck. Drops Brute Brains.', weight = 12, health = 750, speed = 1.3, damage = 32, sight = 45.0, clipset = 'anim_group_move_ballistic', color = { 248, 113, 113 } },
    bloater  = { from = 3, label = 'Bloater',  desc = 'Swollen with toxic gas. Explodes when it reaches you - or when you shoot it. Pop one inside a crowd.', weight = 10, health = 120, speed = 1.0, damage = 0, sight = 35.0, clipset = 'move_m@drunk@verydrunk', color = { 163, 230, 53 }, special = 'bloater' },
    jumper   = { from = 6,  label = 'Jumper',   desc = 'Leaps up onto roofs, cars and ledges after you. High ground will not save you.', weight = 8, health = 200, speed = 1.9, damage = 13, sight = 70.0, color = { 56, 189, 248 }, special = 'jumper' },
    volatile = { from = 8,  label = 'Volatile', desc = 'Spits burning green acid from range. Keep moving - it aims where you stand.', weight = 7, health = 230, speed = 1.5, damage = 10, sight = 60.0, color = { 132, 204, 22 }, special = 'volatile' },
    tank     = { from = 10, label = 'Tank',     desc = 'A huge mutated monster. Tons of health and every hit sends you flying.', weight = 4, health = 1600, speed = 1.15, damage = 40, sight = 50.0, color = { 220, 38, 38 }, special = 'tank', models = { 'zombie_monster' } },
    hound    = { from = 9999, label = 'Hellhound', desc = 'Dog rounds only. Fast, low health, hunts in packs.', weight = 0, health = 160, speed = 2.6, damage = 12, sight = 999.0, color = { 251, 146, 60 }, special = 'hound', models = { 'zombie_dog', 'zombie_dog2' }, model = 'a_c_rottweiler' }, -- zombie dogs from poprpfreezombietwo, rottweiler if missing
    screamer = { from = 5, label = 'Screamer', desc = 'Screams when it sees you and sends every zombie nearby into a frenzy. Kill it first.', weight = 7, health = 170, speed = 1.8, damage = 8, sight = 70.0, color = { 232, 121, 249 }, special = 'screamer' },
}

-- Hellhound rounds (CoD dog rounds): every Every-th round (6, 12, 18, 24 ...) only hounds spawn.
-- Swap Model for the zombie dog ped when you have it.
Config.DogRound = { Enabled = true, Every = 6, Scale = 0.6, MaxAmmo = true }

Config.DamageMult     = 1.0     -- scale every zombie hit
Config.AttackRange    = 1.45    -- metres
Config.AttackCooldown = 1100    -- ms between hits from the same zombie

-- Special abilities
Config.Jumper   = { MinHeight = 1.6, MaxRange = 14.0, Cooldown = 3500 }               -- leaps when you are above it
Config.Volatile = { MinRange = 4.0, MaxRange = 18.0, Cooldown = 4500, Damage = 22, Splash = 2.6, Windup = 650, Speed = 22.0 }
Config.Tank     = { Knockdown = 1600 }                                                -- ms you stay on the floor after a hit

-- Infection: zombie hits can infect you. Infected = slowly lose health until you use an antidote.
-- You only get infected after a few zombie hits (random between HitsMin..HitsMax).
-- Hit count resets if you go Window ms without being hit, and after an antidote.
-- Toxic Fog mutation: one hit fewer is needed.
Config.Infection = { HitsMin = 3, HitsMax = 4, Window = 45000, Tick = 3000, Damage = 3, Shake = 0.08 }

-- Aim steadiness: removes camera shake while you're aiming so long shots are easy.
Config.SteadyAim = true

-- Weapons players can pick. item = ox_inventory item, ammo = ammo item (nil for melee), amount = starting ammo.
Config.Weapons = {
    -- cat = filter group, dmg / rate / range = 1-5 bars on the weapon card
    { item = 'WEAPON_PISTOL',          label = 'Pistol',          cat = 'Pistols',  ammo = 'ammo-9',       amount = 400, dmg = 2, rate = 3, range = 2 },
    { item = 'WEAPON_COMBATPISTOL',    label = 'Combat Pistol',   cat = 'Pistols',  ammo = 'ammo-9',       amount = 400, dmg = 2, rate = 3, range = 2 },
    { item = 'WEAPON_HEAVYPISTOL',     label = 'Heavy Pistol',    cat = 'Pistols',  ammo = 'ammo-45',      amount = 300, dmg = 3, rate = 2, range = 2 },
    { item = 'WEAPON_PISTOL50',        label = 'Pistol .50',      cat = 'Pistols',  ammo = 'ammo-50',      amount = 240, dmg = 4, rate = 2, range = 3 },
    { item = 'WEAPON_MICROSMG',        label = 'Micro SMG',       cat = 'SMGs',     ammo = 'ammo-45',      amount = 900, dmg = 2, rate = 5, range = 2 },
    { item = 'WEAPON_SMG',             label = 'SMG',             cat = 'SMGs',     ammo = 'ammo-9',       amount = 900, dmg = 2, rate = 4, range = 3 },
    { item = 'WEAPON_COMBATPDW',       label = 'Combat PDW',      cat = 'SMGs',     ammo = 'ammo-9',       amount = 900, dmg = 3, rate = 4, range = 3 },
    { item = 'WEAPON_PUMPSHOTGUN',     label = 'Pump Shotgun',    cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 200, dmg = 5, rate = 1, range = 1 },
    { item = 'WEAPON_ASSAULTSHOTGUN',  label = 'Assault Shotgun', cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 240, dmg = 4, rate = 3, range = 1 },
    { item = 'WEAPON_ASSAULTRIFLE',    label = 'Assault Rifle',   cat = 'Rifles',   ammo = 'ammo-rifle2',  amount = 900, dmg = 3, rate = 4, range = 4 },
    { item = 'WEAPON_CARBINERIFLE',    label = 'Carbine Rifle',   cat = 'Rifles',   ammo = 'ammo-rifle',   amount = 900, dmg = 3, rate = 4, range = 4 },
    { item = 'WEAPON_SPECIALCARBINE',  label = 'Special Carbine', cat = 'Rifles',   ammo = 'ammo-rifle',   amount = 900, dmg = 3, rate = 4, range = 4 },
    { item = 'WEAPON_SNIPERRIFLE',     label = 'Sniper Rifle',    cat = 'Snipers',  ammo = 'ammo-sniper',  amount = 120, dmg = 5, rate = 1, range = 5 },
    { item = 'WEAPON_APPISTOL', label = 'AP Pistol', cat = 'Pistols', ammo = 'ammo-9', amount = 500, dmg = 2, rate = 5, range = 2 },
    { item = 'WEAPON_PISTOL_MK2', label = 'Pistol Mk II', cat = 'Pistols', ammo = 'ammo-9', amount = 400, dmg = 2, rate = 3, range = 2 },
    { item = 'WEAPON_SNSPISTOL', label = 'SNS Pistol', cat = 'Pistols', ammo = 'ammo-45', amount = 300, dmg = 2, rate = 3, range = 1 },
    { item = 'WEAPON_VINTAGEPISTOL', label = 'Vintage Pistol', cat = 'Pistols', ammo = 'ammo-9', amount = 400, dmg = 2, rate = 3, range = 2 },
    { item = 'WEAPON_CERAMICPISTOL', label = 'Ceramic Pistol', cat = 'Pistols', ammo = 'ammo-9', amount = 400, dmg = 2, rate = 3, range = 2 },
    { item = 'WEAPON_PISTOLXM3', label = 'WM 29 Pistol', cat = 'Pistols', ammo = 'ammo-9', amount = 400, dmg = 3, rate = 3, range = 2 },
    { item = 'WEAPON_REVOLVER', label = 'Heavy Revolver', cat = 'Pistols', ammo = 'ammo-44', amount = 150, dmg = 5, rate = 1, range = 3 },
    { item = 'WEAPON_REVOLVER_MK2', label = 'Revolver Mk II', cat = 'Pistols', ammo = 'ammo-44', amount = 150, dmg = 5, rate = 1, range = 3 },
    { item = 'WEAPON_NAVYREVOLVER', label = 'Navy Revolver', cat = 'Pistols', ammo = 'ammo-44', amount = 150, dmg = 5, rate = 1, range = 3 },
    { item = 'WEAPON_DOUBLEACTION', label = 'Double-Action Revolver', cat = 'Pistols', ammo = 'ammo-38', amount = 200, dmg = 4, rate = 2, range = 2 },
    { item = 'WEAPON_MARKSMANPISTOL', label = 'Marksman Pistol', cat = 'Pistols', ammo = 'ammo-22', amount = 80, dmg = 5, rate = 1, range = 3 },
    { item = 'WEAPON_ASSAULTSMG', label = 'Assault SMG', cat = 'SMGs', ammo = 'ammo-9', amount = 900, dmg = 2, rate = 5, range = 3 },
    { item = 'WEAPON_MINISMG', label = 'Mini SMG', cat = 'SMGs', ammo = 'ammo-45', amount = 900, dmg = 2, rate = 5, range = 2 },
    { item = 'WEAPON_MACHINEPISTOL', label = 'Machine Pistol', cat = 'SMGs', ammo = 'ammo-9', amount = 900, dmg = 2, rate = 5, range = 2 },
    { item = 'WEAPON_SMG_MK2', label = 'SMG Mk II', cat = 'SMGs', ammo = 'ammo-9', amount = 900, dmg = 3, rate = 4, range = 3 },
    { item = 'WEAPON_TECPISTOL', label = 'Tactical SMG', cat = 'SMGs', ammo = 'ammo-9', amount = 900, dmg = 2, rate = 5, range = 2 },
    { item = 'WEAPON_PUMPSHOTGUN_MK2', label = 'Pump Shotgun Mk II', cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 200, dmg = 5, rate = 1, range = 2 },
    { item = 'WEAPON_BULLPUPSHOTGUN', label = 'Bullpup Shotgun', cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 240, dmg = 4, rate = 2, range = 1 },
    { item = 'WEAPON_COMBATSHOTGUN', label = 'Combat Shotgun', cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 240, dmg = 4, rate = 3, range = 2 },
    { item = 'WEAPON_DBSHOTGUN', label = 'Double Barrel Shotgun', cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 160, dmg = 5, rate = 2, range = 1 },
    { item = 'WEAPON_AUTOSHOTGUN', label = 'Sweeper Shotgun', cat = 'Shotguns', ammo = 'ammo-shotgun', amount = 300, dmg = 3, rate = 5, range = 1 },
    { item = 'WEAPON_ADVANCEDRIFLE', label = 'Advanced Rifle', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 3, rate = 5, range = 4 },
    { item = 'WEAPON_ASSAULTRIFLE_MK2', label = 'Assault Rifle Mk II', cat = 'Rifles', ammo = 'ammo-rifle2', amount = 900, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_CARBINERIFLE_MK2', label = 'Carbine Rifle Mk II', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_SPECIALCARBINE_MK2', label = 'Special Carbine Mk II', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_BULLPUPRIFLE', label = 'Bullpup Rifle', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 3, rate = 4, range = 4 },
    { item = 'WEAPON_BULLPUPRIFLE_MK2', label = 'Bullpup Rifle Mk II', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_COMPACTRIFLE', label = 'Compact Rifle', cat = 'Rifles', ammo = 'ammo-rifle2', amount = 900, dmg = 3, rate = 4, range = 3 },
    { item = 'WEAPON_MILITARYRIFLE', label = 'Military Rifle', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_HEAVYRIFLE', label = 'Heavy Rifle', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 4, rate = 3, range = 4 },
    { item = 'WEAPON_TACTICALRIFLE', label = 'Service Carbine', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 3, rate = 4, range = 4 },
    { item = 'WEAPON_BATTLERIFLE', label = 'Battle Rifle', cat = 'Rifles', ammo = 'ammo-rifle', amount = 900, dmg = 4, rate = 3, range = 5 },
    { item = 'WEAPON_HEAVYSNIPER', label = 'Heavy Sniper', cat = 'Snipers', ammo = 'ammo-heavysniper', amount = 60, dmg = 5, rate = 1, range = 5 },
    { item = 'WEAPON_HEAVYSNIPER_MK2', label = 'Heavy Sniper Mk II', cat = 'Snipers', ammo = 'ammo-heavysniper', amount = 60, dmg = 5, rate = 1, range = 5 },
    { item = 'WEAPON_MARKSMANRIFLE', label = 'Marksman Rifle', cat = 'Snipers', ammo = 'ammo-sniper', amount = 200, dmg = 4, rate = 2, range = 5 },
    { item = 'WEAPON_MARKSMANRIFLE_MK2', label = 'Marksman Rifle Mk II', cat = 'Snipers', ammo = 'ammo-sniper', amount = 200, dmg = 4, rate = 2, range = 5 },
    { item = 'WEAPON_PRECISIONRIFLE', label = 'Precision Rifle', cat = 'Snipers', ammo = 'ammo-sniper', amount = 150, dmg = 5, rate = 1, range = 5 },
    { item = 'WEAPON_MUSKET', label = 'Musket', cat = 'Snipers', ammo = 'ammo-musket', amount = 80, dmg = 5, rate = 1, range = 3 },
    { item = 'WEAPON_MG', label = 'Machine Gun', cat = 'LMGs', ammo = 'ammo-rifle2', amount = 1000, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_COMBATMG', label = 'Combat MG', cat = 'LMGs', ammo = 'ammo-rifle', amount = 1000, dmg = 4, rate = 4, range = 4 },
    { item = 'WEAPON_COMBATMG_MK2', label = 'Combat MG Mk II', cat = 'LMGs', ammo = 'ammo-rifle2', amount = 1000, dmg = 5, rate = 4, range = 4 },
    { item = 'WEAPON_GUSENBERG', label = 'Gusenberg Sweeper', cat = 'LMGs', ammo = 'ammo-45', amount = 900, dmg = 3, rate = 5, range = 3 },
    { item = 'WEAPON_MINIGUN', label = 'Minigun', cat = 'LMGs', ammo = 'ammo-rifle2', amount = 2000, dmg = 4, rate = 5, range = 3 },
    { item = 'WEAPON_RPG', label = 'RPG', cat = 'Launchers', ammo = 'ammo-rocket', amount = 12, dmg = 5, rate = 1, range = 4 },
    { item = 'WEAPON_HOMINGLAUNCHER', label = 'Homing Launcher', cat = 'Launchers', ammo = 'ammo-rocket', amount = 10, dmg = 5, rate = 1, range = 5 },
    { item = 'WEAPON_GRENADELAUNCHER', label = 'Grenade Launcher', cat = 'Launchers', ammo = 'ammo-grenade', amount = 20, dmg = 5, rate = 2, range = 3 },
    { item = 'WEAPON_COMPACTLAUNCHER', label = 'Compact Launcher', cat = 'Launchers', ammo = 'ammo-grenade', amount = 15, dmg = 5, rate = 1, range = 3 },
    { item = 'WEAPON_FIREWORK', label = 'Firework Launcher', cat = 'Launchers', ammo = 'ammo-firework', amount = 15, dmg = 4, rate = 1, range = 4 },
    { item = 'WEAPON_EMPLAUNCHER', label = 'EMP Launcher', cat = 'Launchers', ammo = 'ammo-emp', amount = 15, dmg = 3, rate = 1, range = 3 },
    { item = 'WEAPON_RAYCARBINE', label = 'Unholy Hellbringer', cat = 'Launchers', ammo = 'ammo-laser', amount = 600, dmg = 4, rate = 5, range = 4 },
    { item = 'WEAPON_RAYMINIGUN', label = 'Widowmaker', cat = 'Launchers', ammo = 'ammo-laser', amount = 1500, dmg = 5, rate = 5, range = 4 },
    { item = 'WEAPON_RAILGUNXM3', label = 'Railgun', cat = 'Launchers', ammo = 'ammo-railgun', amount = 30, dmg = 5, rate = 1, range = 5 },
    { item = 'WEAPON_DAGGER', label = 'Dagger', cat = 'Melee', ammo = nil, dmg = 2, rate = 3, range = 1 },
    { item = 'WEAPON_KNUCKLE', label = 'Knuckle Duster', cat = 'Melee', ammo = nil, dmg = 1, rate = 4, range = 1 },
    { item = 'WEAPON_SWITCHBLADE', label = 'Switchblade', cat = 'Melee', ammo = nil, dmg = 2, rate = 4, range = 1 },
    { item = 'WEAPON_WRENCH', label = 'Pipe Wrench', cat = 'Melee', ammo = nil, dmg = 3, rate = 1, range = 1 },
    { item = 'WEAPON_POOLCUE', label = 'Pool Cue', cat = 'Melee', ammo = nil, dmg = 2, rate = 2, range = 1 },
    { item = 'WEAPON_BOTTLE', label = 'Broken Bottle', cat = 'Melee', ammo = nil, dmg = 1, rate = 3, range = 1 },
    { item = 'WEAPON_CANDYCANE', label = 'Candy Cane', cat = 'Melee', ammo = nil, dmg = 2, rate = 2, range = 1 },
    { item = 'WEAPON_STONE_HATCHET', label = 'Stone Hatchet', cat = 'Melee', ammo = nil, dmg = 3, rate = 2, range = 1 },
    { item = 'WEAPON_BAT',             label = 'Baseball Bat',    cat = 'Melee',    ammo = nil, dmg = 2, rate = 2, range = 1 },
    { item = 'WEAPON_KNIFE',           label = 'Knife',           cat = 'Melee',    ammo = nil, dmg = 2, rate = 3, range = 1 },
    { item = 'WEAPON_HATCHET',         label = 'Hatchet',         cat = 'Melee',    ammo = nil, dmg = 3, rate = 2, range = 1 },
}

-- Everyone also gets this kit. { item, count, label }
Config.Kit = {
    { 'bandage',        3, 'Bandage' },
    { 'water',          2, 'Water' },
    { 'burger',         2, 'Burger' },
    { 'zdm_medkit',     1, 'Field Medkit' },
    { 'zdm_antidote',   1, 'Z-Antidote' },
    { 'zdm_adrenaline', 1, 'Adrenaline Shot' },
}

-- Lethals (grenades & explosives). Item names are ox_inventory weapons.
-- Start  = what every class spawns with (item, count, hotbar slot)
-- Refill = topped up at the start of every round, never above max (CoD style)
-- Throw grenades / pipe bombs / molotovs with the normal attack button.
-- C4 (Sticky Bomb): throw it, then press G to blow it. Proximity mines go off when zombies walk over them.
Config.Lethals = {
    Enabled = true,
    Start  = {
        { 'WEAPON_GRENADE',    3, 4, 'Grenade' },
        { 'WEAPON_STICKYBOMB', 1, 5, 'C4 (Sticky Bomb)' },
    },
    Refill = {
        { 'WEAPON_GRENADE',    5, 15 }, -- +5 per round, max 15 (they run out - use them wisely)
        { 'WEAPON_STICKYBOMB', 1, 2 },  -- +1 per round, max 2
    },
}

-- In-game shop (press K during a match). Paid with your POINTS (the gold number on screen).
-- Spending points does NOT lower the cash you get paid - cash is worked out from points EARNED.
-- round = first round it can be bought. kind: weapon | item | ammo | armour | perk (whole match) | timed (seconds)
Config.Shop = {
    Enabled = true,
    Key = 'K',
    Items = {
        -- Weapons
        { id = 'w_pistol50',  cat = 'Weapons',   label = 'Pistol .50',      price = 800,   round = 1,  kind = 'weapon', item = 'WEAPON_PISTOL50',       ammo = 'ammo-50',          amount = 240 },
        { id = 'w_smg',       cat = 'Weapons',   label = 'SMG',             price = 1200,  round = 1,  kind = 'weapon', item = 'WEAPON_SMG',            ammo = 'ammo-9',           amount = 900 },
        { id = 'w_pump',      cat = 'Weapons',   label = 'Pump Shotgun',    price = 1500,  round = 1,  kind = 'weapon', item = 'WEAPON_PUMPSHOTGUN',    ammo = 'ammo-shotgun',     amount = 200 },
        { id = 'w_ar',        cat = 'Weapons',   label = 'Assault Rifle',   price = 2000,  round = 2,  kind = 'weapon', item = 'WEAPON_ASSAULTRIFLE',   ammo = 'ammo-rifle2',      amount = 900 },
        { id = 'w_scar',      cat = 'Weapons',   label = 'Special Carbine', price = 2500,  round = 3,  kind = 'weapon', item = 'WEAPON_SPECIALCARBINE', ammo = 'ammo-rifle',       amount = 900 },
        { id = 'w_ashotgun',  cat = 'Weapons',   label = 'Assault Shotgun', price = 3000,  round = 5,  kind = 'weapon', item = 'WEAPON_ASSAULTSHOTGUN', ammo = 'ammo-shotgun',     amount = 240 },
        { id = 'w_hsniper',   cat = 'Weapons',   label = 'Heavy Sniper',    price = 3500,  round = 6,  kind = 'weapon', item = 'WEAPON_HEAVYSNIPER',    ammo = 'ammo-heavysniper', amount = 60 },
        { id = 'w_cmg',       cat = 'Weapons',   label = 'Combat MG',       price = 4500,  round = 8,  kind = 'weapon', item = 'WEAPON_COMBATMG',       ammo = 'ammo-rifle',       amount = 1000 },
        { id = 'w_rpg',       cat = 'Weapons',   label = 'RPG',             price = 7000,  round = 12, kind = 'weapon', item = 'WEAPON_RPG',            ammo = 'ammo-rocket',      amount = 8 },
        { id = 'w_glaunch',   cat = 'Explosives', label = 'Compact Grenade Launcher', price = 6000, round = 10, kind = 'weapon', item = 'WEAPON_COMPACTLAUNCHER', ammo = 'ammo-grenade', amount = 10 },
        { id = 'w_launcher',  cat = 'Explosives', label = 'Grenade Launcher', price = 8000, round = 14, kind = 'weapon', item = 'WEAPON_GRENADELAUNCHER', ammo = 'ammo-grenade',  amount = 15 },
        { id = 'w_firework',  cat = 'Explosives', label = 'Firework Launcher', price = 5000, round = 8, kind = 'weapon', item = 'WEAPON_FIREWORK',        ammo = 'ammo-firework', amount = 10 },
        { id = 'w_flaregun',  cat = 'Explosives', label = 'Flare Gun',        price = 1500,  round = 3,  kind = 'weapon', item = 'WEAPON_FLAREGUN',       ammo = 'ammo-flare',       amount = 10 },
        { id = 'w_homing',    cat = 'Explosives', label = 'Homing Launcher',  price = 10000, round = 16, kind = 'weapon', item = 'WEAPON_HOMINGLAUNCHER', ammo = 'ammo-rocket',      amount = 6 },
        { id = 'w_minigun',   cat = 'Weapons',   label = 'Minigun',         price = 12000, round = 18, kind = 'weapon', item = 'WEAPON_MINIGUN',        ammo = 'ammo-rifle2',      amount = 1500 },
        -- Gear
        { id = 'ammo',        cat = 'Gear',      label = 'Max Ammo',        price = 750,   round = 1,  kind = 'ammo',   desc = 'Refills every gun you own.' },
        { id = 'armour',      cat = 'Gear',      label = 'Body Armour',     price = 1000,  round = 1,  kind = 'armour', desc = 'Full armour right now.' },
        { id = 'medkit',      cat = 'Gear',      label = 'Field Medkit',    price = 400,   round = 1,  kind = 'item',   item = 'zdm_medkit',     count = 1 },
        { id = 'antidote',    cat = 'Gear',      label = 'Z-Antidote',      price = 300,   round = 1,  kind = 'item',   item = 'zdm_antidote',   count = 1 },
        { id = 'adrenaline',  cat = 'Gear',      label = 'Adrenaline Shot', price = 500,   round = 1,  kind = 'item',   item = 'zdm_adrenaline', count = 1 },
        -- Lethals
        { id = 'grenades',    cat = 'Lethals',   label = 'Grenades x3',     price = 500,   round = 1,  kind = 'item',   item = 'WEAPON_GRENADE',    count = 3, max = 15 },
        { id = 'c4',          cat = 'Lethals',   label = 'C4 x2',           price = 800,   round = 2,  kind = 'item',   item = 'WEAPON_STICKYBOMB', count = 2, max = 6 },
        { id = 'pipebombs',   cat = 'Lethals',   label = 'Pipe Bombs x2',   price = 700,   round = 2,  kind = 'item',   item = 'WEAPON_PIPEBOMB',   count = 2, max = 8 },
        { id = 'molotovs',    cat = 'Lethals',   label = 'Molotovs x2',     price = 600,   round = 2,  kind = 'item',   item = 'WEAPON_MOLOTOV',    count = 2, max = 8 },
        { id = 'mines',       cat = 'Lethals',   label = 'Proximity Mines x2', price = 900, round = 4, kind = 'item',   item = 'WEAPON_PROXMINE',   count = 2, max = 6 },
        { id = 'jerrycan',    cat = 'Lethals',   label = 'Jerry Can',       price = 800,   round = 3,  kind = 'item',   item = 'WEAPON_PETROLCAN',  count = 1, max = 2, desc = 'Pour a petrol trail, then light it with a molotov, flare or gunfire.' },
        { id = 'bzgas',       cat = 'Lethals',   label = 'BZ Gas x2',       price = 600,   round = 3,  kind = 'item',   item = 'WEAPON_BZGAS',      count = 2, max = 6, desc = 'Choking gas that slows the horde down.' },
        { id = 'flares',      cat = 'Lethals',   label = 'Flares x3',       price = 300,   round = 1,  kind = 'item',   item = 'WEAPON_FLARE',      count = 3, max = 9, desc = 'Light up the dark - and lights petrol.' },
        -- Abilities (whole match)
        { id = 'juggernog',   cat = 'Abilities', label = 'Juggernog',       price = 2500,  round = 5,  kind = 'perk', desc = '+50% max health for the rest of the match.' },
        { id = 'staminup',    cat = 'Abilities', label = 'Stamin-Up',       price = 2000,  round = 5,  kind = 'perk', desc = 'Run faster for the rest of the match.' },
        { id = 'doubletap',   cat = 'Abilities', label = 'Double Tap',      price = 4000,  round = 10, kind = 'perk', desc = 'Every gun does 1.5x damage.' },
        { id = 'phd',         cat = 'Abilities', label = 'PhD Flopper',     price = 3000,  round = 8,  kind = 'perk', desc = 'Your own explosions can not hurt you.' },
        { id = 'extralife',   cat = 'Abilities', label = 'Extra Life',      price = 5000,  round = 10, kind = 'perk', desc = '+1 life (once per match).' },
        { id = 'bodyguard',   cat = 'Abilities', label = 'Bodyguard',       price = 10000, round = 10, kind = 'perk', desc = 'A bodyguard follows you and shoots zombies for the rest of the match.' },
        -- Timed abilities
        { id = 'sprint',      cat = 'Timed',     label = 'Sprint Boost',    price = 5000,  round = 3,  kind = 'timed', secs = 120, desc = 'Run at top speed for 2 minutes.' },
        { id = 'instakill',   cat = 'Timed',     label = 'Insta-Kill',      price = 6000,  round = 8,  kind = 'timed', secs = 30,  desc = 'Every hit kills for 30 seconds.' },
        { id = 'infammo',     cat = 'Timed',     label = 'Bottomless Clip', price = 7000,  round = 10, kind = 'timed', secs = 60,  desc = 'No reloading, no ammo used for 60 seconds.' },
        { id = 'godmode',     cat = 'Timed',     label = 'Iron Skin',       price = 8000,  round = 12, kind = 'timed', secs = 20,  desc = 'Take no damage for 20 seconds.' },
        { id = 'ghost',       cat = 'Timed',     label = 'Ghost',           price = 4000,  round = 5,  kind = 'timed', secs = 60,  desc = 'Every zombie ignores you for 1 minute.' },
        { id = 'shrink',      cat = 'Timed',     label = 'Shrink Ray',      price = 3000,  round = 6,  kind = 'timed', secs = 20,  desc = 'Every zombie shrinks for 20 seconds (everyone in the match sees it).' },
        { id = 'regen',       cat = 'Timed',     label = 'Regeneration',    price = 3500,  round = 6,  kind = 'timed', secs = 60,  desc = 'Heal constantly for 60 seconds.' },
        { id = 'nuke',        cat = 'Timed',     label = 'Nuke',            price = 9000,  round = 12, kind = 'timed', secs = 0,   desc = 'Wipes out every zombie near you right now. +400 points.' },
    },
    Bodyguard = { Models = { 's_m_y_blackops_01', 's_m_y_marine_03' }, Weapon = 'WEAPON_CARBINERIFLE', Health = 1500 },
}

-- Mystery Box (one per map, next to the spawn). Press E: pay points, it spins and gives a random gun
-- from EVERY gun on the server (all ox_inventory weapons incl. VIP/paid ones). VIP guns hit much harder.
Config.MysteryBox = {
    Enabled  = true,
    Price    = 950,
    Offset   = vector3(4.0, 4.0, 0.0),   -- from the map centre; a map can set  box = vector3(x, y, z)  instead
    Props    = { 'prop_box_guncase_01a', 'prop_box_guncase_02a', 'prop_box_wood05a' }, -- slim, long crate; first one that exists is used
    Blip     = { Sprite = 66, Colour = 46, Scale = 0.85, Label = 'Mystery Box' },
    SpinTime = 4.0,                       -- seconds the weapons cycle before you get one
    TeddyChance = 0.06,                   -- the bear: no weapon, half your points back
    VipDamage = 2.5,                      -- damage multiplier for VIP / custom guns from the box
    BaseDamage = 1.3,                     -- damage multiplier for normal guns from the box
    -- these count as VIP (insane damage); any other custom gun on the server is detected automatically
    Vip = { 'WEAPON_VIPDRAINBOW', 'WEAPON_WIREFRAMEAK2', 'WEAPON_WAP', 'WEAPON_WUZI', 'WEAPON_WSMG2', 'WEAPON_WFSC',
            'WEAPON_HEAVYSHOTGUN', 'WEAPON_RAILGUN', 'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_BATTLEAXE', 'WEAPON_HAMMER',
            'WEAPON_CROWBAR', 'WEAPON_MACHETE', 'WEAPON_GOLFCLUB', 'WEAPON_DAGGER' },
    -- never give these
    Blacklist = { 'WEAPON_UNARMED', 'WEAPON_PETROLCAN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_HAZARDCAN', 'WEAPON_FERTILIZERCAN',
                  'WEAPON_DIGISCANNER', 'WEAPON_METALDETECTOR', 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP', 'WEAPON_SNOWBALL', 'WEAPON_BALL',
                  'WEAPON_FLARE', 'WEAPON_PARACHUTE', 'WEAPON_NIGHTSTICK', 'WEAPON_FLASHLIGHT', 'WEAPON_GADGETPISTOL' },
    AmmoAmount = 300,
}

-- Loot when you kill a zombie. chance per kill, then one weighted pick. 'AMMO' = ammo for your weapons.
Config.LootChance = 0.35
Config.Loot = {
    { 'AMMO',           45 },
    { 'zdm_flesh',      30 },
    { 'bandage',        15 },
    { 'zdm_antidote',    8 },
    { 'zdm_medkit',      6 },
    { 'zdm_adrenaline',  6 },
    { 'water',           5 },
    { 'WEAPON_GRENADE',    6 },
    { 'WEAPON_PIPEBOMB',   4 },
    { 'WEAPON_MOLOTOV',    4 },
    { 'WEAPON_STICKYBOMB', 2 },
    { 'WEAPON_PROXMINE',   2 },
}
Config.BrainChance = 0.5          -- brutes: chance to drop a Brute Brain on top

-- Items you keep when you leave (trophies). Everything else from the lobby is removed.
Config.KeepOnLeave = { 'zdm_flesh', 'zdm_brain' }

-- Extra ammo: share of your starting ammo given back by an ammo drop / when you respawn.
Config.AmmoLootShare    = 0.25
Config.AmmoRespawnShare = 0.75

-- Ranks shown in the menu (total kills needed).
Config.Ranks = {
    { 0,    'Rookie' },
    { 50,   'Survivor' },
    { 150,  'Scavenger' },
    { 400,  'Hunter' },
    { 1000, 'Slayer' },
    { 2500, 'Legend' },
}

-- Zombie noises (made by the zombies themselves - groans, screeches, bites).
Config.SoundRange = 38.0   -- metres you can hear a zombie from

-- Pack-a-Punch: reach this round and everyone gets an upgraded VIP weapon (hotbar slot 3).
-- melee = true weapons blast back every zombie near the one you hit.
Config.PackAPunch = {
    Round  = 15,
    Slot   = 3,
    Weapons = {
        { item = 'WEAPON_ASSAULTRIFLE',   label = 'Pack-a-Punched AR',                 ammo = 'ammo-rifle2',  amount = 900 },
        { item = 'WEAPON_SAWNOFFSHOTGUN', label = 'Pack-a-Punched Sawed-Off',         ammo = 'ammo-shotgun', amount = 240 },
        { item = 'WEAPON_BATTLEAXE',      label = 'Doom Axe',                  melee = true },
        { item = 'WEAPON_HAMMER',         label = 'Thunder Hammer',            melee = true },
        { item = 'WEAPON_CROWBAR',        label = 'Skull Splitter',            melee = true },
    },
    GunDamage      = 2.5,   -- damage multiplier for Pack-a-Punched guns
    MeleeDamage    = 4.0,   -- ...and melee
    GunKnockback   = 9.0,   -- how hard a gun hit pushes the zombie
    MeleeKnockback = 20.0,  -- how hard a melee hit blasts zombies away
    MeleeRadius    = 4.5,   -- metres: every zombie this close to the one you hit gets blasted too
}

-- Matchmaking ("Find players"). "Play solo" always starts a private game straight away.
-- Crash protection: if you crash/disconnect mid-match, your spot is held this long.
-- Log back in within the time and you go straight back into the same match with your kills,
-- weapons, ammo and Pack-a-Punch. If the whole team crashes, the match waits (frozen) for you.
Config.Resume = { Enabled = true, Minutes = 10 }

Config.Match = {
    MaxPlayers = 4,      -- per game
    MaxStartRound = 100,   -- players can pick any starting round up to this
    -- Starting above round 1 = harder zombies straight away. Points still pay out, but round cash,
    -- milestone prizes, reward drops and the leaderboard best-round only count when you start on round 1.
    JoinInProgress = true, -- others can jump into a match that's already running (shown under the map in the menu)
    JoinSolo = true,       -- ...including someone's solo game (it becomes a team game)
    Countdown  = 25,     -- seconds to wait for more players once 2+ are queued
    ReadyStart = 5,      -- everyone pressed Ready (or the game is full) -> start in this many seconds
}

-- Which weapon categories go in which loadout slot (Call of Duty style).
Config.SlotCategories = {
    primary   = { 'Rifles', 'SMGs', 'Shotguns', 'Snipers', 'LMGs', 'Launchers' },
    secondary = { 'Pistols', 'Melee' },
}

Config.MenuMusic = true -- plays html/assets/menu_music.ogg while the menu is open

-- Round rewards (paid to the bank when the round is cleared).
-- Every 5th round pays round x PerRound ($5k, $10k, $15k ...); Special overrides a round.
Config.RoundRewards = {
    Account  = 'bank',
    Every    = 5,
    PerRound = 1000,
    Special  = { [50] = 300000, [100] = 1000000 },
}

-- Players in a zombie lobby
Config.Player = {
    MaxHealth = 400,   -- normal is 200
    Armour    = 50,    -- given on spawn / respawn
    Damage    = 2.0,   -- every weapon does this much more damage (Pack-a-Punch stacks on top)
    Speed     = 1.15,  -- sprint speed (1.0 normal, max 1.49) so players can outrun most zombies
}


-- Mutation rounds: every Nth round gets a random twist
Config.Mutations = {
    Every = 3,
    List = {
        bloodmoon = { label = 'BLOOD MOON',   desc = 'Every zombie sprints.',                       timecycle = 'REDMIST',       strength = 0.55 },
        toxic     = { label = 'TOXIC FOG',    desc = 'Infection after fewer hits.',                        timecycle = 'Barry1_Stoned', strength = 0.35 },
        glow      = { label = 'GLOW HORDE',   desc = 'Every zombie shows on your minimap - double loot.' },
        brutes    = { label = 'BRUTE PARADE', desc = 'The big ones are out. 4x more Brutes.' },
        hounds    = { label = 'HELLHOUND ROUND', desc = 'Every 6th round: only hellhounds. Survive it for MAX AMMO.', timecycle = 'REDMIST', strength = 0.35, special = true },
    },
}

-- Survivor vehicles parked around each map (shown on the minimap). Missing models are skipped.
Config.Vehicles = {
    Count  = 4,
    -- In a car you're safe-ish: zombie hits damage the CAR, not you. The car never explodes or
    -- burns - it just gets wrecked and the engine dies, so you have to get out and fight.
    Shelter      = true,
    HitBody      = 35.0,   -- body damage per zombie hit (body health starts at 1000)
    HitEngine    = 22.0,   -- engine damage per zombie hit (engine dies at ~0, never explodes)
    EngineFloor  = 0.0,    -- engine never goes below this (0 = dead engine, smoking, can't drive)
    Models = { 'kuruma2', 'insurgent2', 'sandking', 'technical', 'mesa3' }, -- vanilla only (custom addon cars can be added back once stable)
}

-- Stuck zombies: if a chasing zombie hasn't got any closer for StuckSeconds, it is moved to a
-- hidden spot closer to its target (never in view, never right on top of you).
Config.Unstuck = { Enabled = true, StuckSeconds = 9, StuckSecondsCustom = 5, MinProgress = 3.0, MinDist = 22.0, MaxDist = 40.0 }

-- Yachts: always parked in the water, can't be destroyed. Zombies swim out and climb aboard.
Config.Yachts = {
    Enabled = false,                   -- needs an add-on yacht vehicle (Model below)
    Model   = 'sr650fly',
    Maps    = { [1] = true },          -- which maps get them (1 = LSIA Airport) - needs an add-on yacht model
    Spots   = {                        -- x, y, heading (z is the water)
        { -700.8, -3384.93, 90.0 },
        { -660.0, -3352.0, 35.0 },
        { -742.0, -3350.0, 210.0 },
        { -668.0, -3420.0, 140.0 },
        { -738.0, -3418.0, 300.0 },
    },
    Z       = 0.3,
    Blip    = true,
    ClimbSeconds = 1.2,                -- how long a zombie hangs on the side before it's aboard
}

-- Airdrops (Apex style): a crate parachutes in with a light beam. First to open it gets the loot.
Config.Airdrops = {
    First    = 90,    -- seconds after the game starts
    Interval = 150,   -- seconds between drops
    Expire   = 240,   -- unopened drops disappear after this long
    Loot = { -- one weapon (weighted) + ammo, plus the extras below
        { item = 'WEAPON_ASSAULTRIFLE',    label = 'Assault Rifle',           ammo = 'ammo-rifle2',  amount = 600, weight = 12 },
        { item = 'WEAPON_SPECIALCARBINE',  label = 'Special Carbine',         ammo = 'ammo-rifle',   amount = 600, weight = 12 },
        { item = 'WEAPON_COMBATMG',        label = 'Combat MG',               ammo = 'ammo-rifle',   amount = 800, weight = 8 },
        { item = 'WEAPON_SAWNOFFSHOTGUN',  label = 'Sawed-Off Shotgun',       ammo = 'ammo-shotgun', amount = 200, weight = 8 },
        { item = 'WEAPON_HEAVYSHOTGUN',    label = 'Heavy Shotgun',           ammo = 'ammo-shotgun', amount = 200, weight = 6 },
                        { item = 'WEAPON_BATTLEAXE',       label = 'Battle Axe',              weight = 4 },
        { item = 'WEAPON_HAMMER',          label = 'Hammer',                  weight = 4 },
        { item = 'WEAPON_MACHETE',         label = 'Machete',                 weight = 4 },
        { item = 'WEAPON_GOLFCLUB',        label = 'Golf Club',               weight = 3 },
    },
    Extras = { { 'zdm_medkit', 1 }, { 'zdm_adrenaline', 1 }, { 'bandage', 2 }, { 'WEAPON_PIPEBOMB', 2 }, { 'WEAPON_STICKYBOMB', 2 }, { 'WEAPON_PROXMINE', 2 } },
}

-- Chat broadcast advertising the game mode
Config.Broadcast = {
    Interval = 20, -- minutes
    Message  = '🧟 The ZOMBIES game mode is LIVE! Type /zombies to fight the horde, survive the rounds and win exclusive rewards 🎁',
}

-- Exclusive rewards: rolled for every player each time a round is cleared.
-- Won items are added to your SAVED inventory, so you keep them when you leave.
Config.Rewards = {
    ItemChance = 0.0,   -- set e.g. 0.05 (5% per round cleared) once you've put your own items below
    Items = {           -- { item, label, weight } - any ox_inventory items from YOUR server
        { 'bandage', 'Bandage', 1 },
    },
    -- Giveaway mode (staff only): /giveaway zombies [minutes]  |  /giveaway zombies off
    GiveawayAce   = 'corlinks.giveaway',  -- ace that may start it (txAdmin console always can)
    GiveawayChance = 0.01,                -- 1% per round cleared while it's on: VIP weapon (70%) or VIP car (30%)
    VipWeapons = {
        { 'WEAPON_BATTLEAXE', 'Battle Axe' }, { 'WEAPON_HAMMER', 'Hammer' }, { 'WEAPON_CROWBAR', 'Crowbar' },
        { 'WEAPON_MACHETE', 'Machete' }, { 'WEAPON_HEAVYSHOTGUN', 'Heavy Shotgun' }, { 'WEAPON_RAILGUN', 'Railgun' },
        { 'WEAPON_SAWNOFFSHOTGUN', 'Sawed-Off Shotgun' },
    },
    VipCars = { 'zentorno', 't20', 'osiris', 'entityxf', 'adder' }, -- any car spawn names
    CarGarage = 'pillboxgarage',
}
