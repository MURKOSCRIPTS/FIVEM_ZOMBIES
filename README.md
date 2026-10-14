# Corlinks Zombies

Co-op zombie survival for **QBCore + ox_inventory**. Type `/zombies` to open the lobby, pick a map and a loadout, and survive round after round with your friends.

## Features

- **Matches:**
  - 8 maps across GTA's own map.
  - Every match runs in its own world (routing bucket).
  - Join a match that's already running.
  - Start on any round.
  - Crash protection: you get your spot back if you crash or disconnect.
- **Zombies:**
  - Walkers, runners, brutes, jumpers, volatiles and tanks.
  - A hellhound round every 6th round.
  - Infection after 3–4 hits; cure it with the Z-Antidote.
- **Loadout:** pick 2 weapons from 100+ standard ox_inventory weapons, including LMGs and launchers.
- **Points and rewards:** points, multipliers and a cash payout. Bank rewards every 5 rounds. A leaderboard of kills and highest round.
- **Shop (K):** weapons, explosives and abilities (Ghost, Sprint Boost, Insta-Kill, Nuke, Bodyguard and more).
- **Mystery Box:** gives a random weapon from every ox weapon on the server.
- **Extras:**
  - Pack-a-Punch at round 15.
  - Airdrops.
  - Survivor cars.
  - Hitmarkers and kill feed.
- **Auto reload** (`corlinks_weaponreload`): reloads your gun when the magazine is empty, server-wide. Players can toggle it with `/gunreload`.

## Requirements

- `qb-core`
- `ox_lib`
- `ox_inventory`
- `oxmysql` (the tables are created automatically on first start; there's no SQL file to import)

## Install

1. Copy these folders into your `resources`:
   - `corlinks_zombies`
   - `corlinks_weaponreload` (optional, but recommended)
   - `corlinks_zombie_replace` (optional zombie skin; see below)
2. Add the zombie items to ox_inventory. Either:
   - run `python corlinks_zombies/install/install.py path/to/ox_inventory`, which adds the items and copies the pictures, **or**
   - paste `corlinks_zombies/install/items_block.txt` into `ox_inventory/data/items.lua` (inside the main table), then copy `corlinks_zombies/install/images/*.png` into `ox_inventory/web/images/`.
3. Add these lines to `server.cfg` **after** qb-core, ox_lib, ox_inventory and oxmysql:
   ```
   ensure corlinks_zombie_replace
   ensure corlinks_weaponreload
   ensure corlinks_zombies
   ```
4. Restart the server, then type `/zombies` in game.

## Peds

| What | Resource | If missing |
|---|---|---|
| Zombie skin (replaces GTA's `u_m_y_zombie_01`) | `corlinks_zombie_replace`: download **All-in-One Zombies Mega Pack** (gta5-mods.com), take the 4 `u_m_y_zombie_01` files from its *[LIMITED] Vanilla Zombie Replacement* folder and drop them into `corlinks_zombie_replace/stream/` | GTA's own zombie |
| Hellhounds (`zombie_dog`, `zombie_dog2`) | Popcorn RP **Free Zombie Pack Two**: claim it free on the CFX portal / Tebex, then `ensure` it | Rottweilers |
| Tank (`zombie_monster`) | same Popcorn RP pack | Normal zombie with tank health |
| Bodyguard | any ped, set in `Config.Shop.Bodyguard.Models` | Black-ops soldier |

The Popcorn RP pack is a CFX escrow asset. Every server owner has to claim it on their own CFX account, so it can't be shipped in this repo.

## Config

Everything is in `corlinks_zombies/config.lua`:

- **Maps:** `Config.Maps`. Add your own custom maps; there's an example at the bottom of the list.
- **Weapons and the loadout:** `Config.Weapons` and `Config.SlotCategories`.
- **Shop:** `Config.Shop`.
- **Mystery Box:** `Config.MysteryBox`.
- **Rewards:** `Config.RoundRewards` for money and `Config.Rewards` for the item drops. Item drops are off until you add your own items.
- **Zombie sounds and menu music** (optional): drop `.ogg` files into `corlinks_zombies/html/assets/sfx/` (`z1`–`z5`, `laugh`, `killpop`, `souls`) and `corlinks_zombies/html/assets/menu_music.ogg`. Without them the script uses built-in synth sounds.

## Commands

| Command | What it does |
|---|---|
| `/zombies` | Open the lobby |
| `/zleave` | Leave the match and get your inventory back |
| `K` | Shop (in a match) |
| `E` | Mystery Box (in a match) |
| `/gunreload` | Turn auto reload on or off |
| `/giveaway zombies [minutes]` | Staff: VIP giveaway mode (ace `corlinks.giveaway`) |

## Credits

- **Fonts:** Creepster, Special Elite, Archivo and Chakra Petch, all under the SIL Open Font License.
- **Zombie skin:** All-in-One Zombies Mega Pack by its original author on gta5-mods.com (not included; download it from there).
