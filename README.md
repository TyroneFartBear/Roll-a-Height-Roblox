# Roll Your Height (Roblox)

An RNG game where every roll sets your character's height, from a 1.4-inch **Quantum** speck to a 1,150 ft **World Eater** titan (1 in 1,000,000).

**New here? Start with [SETUP.md](SETUP.md).** It walks you through pasting each script into Studio and what to test.

## Files → where they go in Studio

| File | Studio location | Type |
|---|---|---|
| `src/ReplicatedStorage/RarityTable.lua` | ReplicatedStorage › `RarityTable` | ModuleScript |
| `src/ServerScriptService/RollServer.server.lua` | ServerScriptService › `RollServer` | Script |
| `src/StarterPlayerScripts/RollClient.client.lua` | StarterPlayer › StarterPlayerScripts › `RollClient` | LocalScript |

(The `.server.lua` / `.client.lua` naming is compatible with Rojo if you want to sync files automatically later.)

## Rarity table (v1)

Each tier gets exactly 1/N of the roll. "Average" gets whatever is left over, about 37%. Common tiers vary ±6% in height. Tiers rarer than 1 in 100 are always exact.

| # | Tier | Title | Height | Odds | Effect | Server banner |
|---|---|---|---|---|---|---|
| 1 | Quantum | Smaller Than Physics | 0.02x · 1.4 in | 1 in 500,000 | Cosmic | ✅ |
| 2 | Microbe | Germ of Legend | 0.05x · 3.5 in | 1 in 50,000 | Glow | ✅ |
| 3 | Ant | Tiny Terror | 0.1x · 6.9 in | 1 in 5,000 | Glow | ✅ |
| 4 | Mouse | Cheese Seeker | 0.2x · 1 ft 2 in | 1 in 750 | Sparkles | |
| 5 | Pebble | Kickable | 0.4x · 2 ft 4 in | 1 in 60 | — | |
| 6 | Pocket-Sized | Fits in a Backpack | 0.65x · 3 ft 9 in | 1 in 15 | — | |
| 7 | Shorty | Fun-Sized | 0.85x · 4 ft 11 in | 1 in 5 | — | |
| 8 | Average | Perfectly Normal | 1x · 5 ft 9 in | ~1 in 2.7 | — | |
| 9 | Tall | Top Shelf Reacher | 1.15x · 6 ft 7 in | 1 in 5 | — | |
| 10 | Lanky | All Legs | 1.35x · 7 ft 9 in | 1 in 10 | — | |
| 11 | Towering | Door Ducker | 1.75x · 10 ft | 1 in 30 | — | |
| 12 | Tree | Walking Timber | 2.5x · 14 ft | 1 in 120 | Sparkles | |
| 13 | Giant | Fee-Fi-Fo-Fum | 4x · 23 ft | 1 in 400 | Sparkles | |
| 14 | Lighthouse | Beacon of the Coast | 7x · 40 ft | 1 in 1,500 | Glow | ✅ |
| 15 | Skyscraper | Cloud Scraper | 12x · 69 ft | 1 in 6,000 | Glow | ✅ |
| 16 | Mountain | Peak Performer | 20x · 115 ft | 1 in 25,000 | Flames | ✅ |
| 17 | Colossus | Earth Shaker | 35x · 201 ft | 1 in 80,000 | Flames | ✅ |
| 18 | Storm Titan | Lord of Thunder | 60x · 345 ft | 1 in 200,000 | Cosmic | ✅ |
| 19 | Planet Breaker | Moon Kicker | 100x · 575 ft | 1 in 400,000 | Cosmic | ✅ |
| 20 | World Eater | Devourer of Worlds | 200x · 1,150 ft | 1 in 1,000,000 | Cosmic | ✅ |

**Effects:** Sparkles = particles. Glow = outline highlight + light + particles. Flames = glow + rising fire. Cosmic = glow + fire + a heavy sparkle storm.
On screen, rolls of 1 in 100 or rarer shake the camera. Rolls of 1 in 1,000 or rarer also flash the screen in the tier's color.

**"Best"** means rarest: a Quantum outranks a Colossus. Within one tier, the more extreme height wins.

**Luck** multiplies only tiers of 1 in 100 or rarer, so the common tiers stay balanced. It's read from the player attribute `Luck` (default 1), which is the hook for luck potions and a VIP pass later.

## Built so far (v1)

- Roll button (plus the R key), with a slot-machine spin then the reveal
- Server-side weighted roll that resizes the character with `Model:ScaleTo`; feet stay on the ground, and walk speed, jump height and camera zoom adapt
- Result popup, auras, flash and shake, plus a server-wide banner and chat message for rare rolls
- DataStore saving of best height, current height and roll count
- Equip Best button
- Studio-only test panel to force any tier
