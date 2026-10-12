# Roll Your Height — project context

Roblox RNG game: each roll sets the character's height, from Quantum (0.02x, 1 in 500,000) to World Eater (200x, 1 in 1,000,000). Being huge is the flex, and tiny is a rare flex too.

## The user
- Zero coding and zero Roblox Studio experience. Strong on game design and progression loops.
- Act as their lead developer. Explain simply, go one step at a time, and say exactly what to test after each step.
- They paste scripts into Studio by hand (see SETUP.md), unless a Claude on their own computer is connected to Roblox's Studio MCP server. Cloud sessions can't reach their Studio.

## Code (Rojo-style names; each file maps to one Studio object)
- `src/ReplicatedStorage/RarityTable.lua`: ModuleScript. Has the 20-tier list, the roll, odds and height formatting. **Rebalance only here.**
- `src/ServerScriptService/RollServer.server.lua`: Script. Handles the server-side roll and cooldown, creates the RemoteEvents (`ReplicatedStorage.Remotes`), resizes with `Model:ScaleTo` (feet kept on the ground; WalkSpeed, JumpHeight and HipHeight adjusted), adds auras, leaderstats and announcements, saves with a DataStore (`RollYourHeight_v1`), and handles Equip Best, Index equip (`EquipTier`) and the Studio-only force roll. It also sets the friend boost (`FriendBoost`) and group perk (`GroupBoost`, `GROUP_ID` constant), tracks discovered tiers (`Discovered` attribute, JSON), and fills the live top-3 board. Also: all luck math (`computeLuck`, published as the `LuckInfo` JSON attribute), Growth Essence, Gambler's Wheel, Sky Altars/Orbs, bonus-roll queue, gamepasses (`GAMEPASSES` ids, `STUDIO_PASSES`), VIP overhead tag, Starry/Nebula auras, and the server copy of the giant animation fix.
- `src/StarterPlayerScripts/RollClient.client.lua`: LocalScript. Builds the UI in code: ROLL button (R key), AUTO toggle (1.5s; 0.45s with Fast Roll), EQUIP BEST, luck badge (renders `LuckInfo`), INDEX / SHOP / SPIN WHEEL buttons on the left, toast messages (`Notify` remote), slot-machine spin, result popup (+Essence), flash and shake, camera zoom by size, giant footstep thuds + shake (10x+), [VIP] chat prefix, top banner plus a chat message for rare rolls, and a Studio-only FORCE test panel. It also holds the giant animation fix for every character (see below). The `SOUNDS` table is empty and waiting for asset IDs.
- Map objects live in the place file, not the repo: `Workspace.MapSafety` (6144x6144 floor + 2048-tall invisible walls, plus `SkyRealm`: Cloud Layer top 250 with stepping clouds at 60/120/180, Celestial Layer top 800 via a step at 520, two altars tagged `SkyAltar`, eight orbs tagged `SkyOrb`) and `Workspace.Lobby` (spawn plaza, `HeightRuler` wall, `TopRollsBoard` with `Display` SurfaceGui rows `Row1`-`Row3`, `GamblersWheel` with `Hub` + ProximityPrompt and a `BaseCFrame` attribute; its 100 rim tiles must match `WHEEL` weights). RollServer skips anything missing.

## Design decisions
- Exact odds: each tier gets 1/oneIn of the roll, and "Average" gets the leftover (~37%). Odds were verified with a 10M-roll Luau simulation.
- Luck = (`Luck` attribute + friend +10%/friend max +50% + group +15% + VIP +25% + Sky Blessing +25% + wheel +15% (60s) + Super Surge +100% (3 rolls)) x (2x Luck pass) x (orb 1.5x, 60s) x (Jackpot 10x, 5 rolls), capped at 25x (`MAX_LUCK`). Luck only multiplies tiers 1 in 100 or rarer.
- Growth Essence: rolls more common than 1 in 100 give 1 / 2 / 3 Essence (1 in <10 / 10-29 / 30-99), ~1.25 per roll on average; a wheel spin costs 50 (~40 rolls). Saved.
- Wheel odds 45/30/15/8/2 (+15% luck 60s / 3 free rolls / Super Surge / Titan Pity / Jackpot). Titan Pity = `RarityTable.RollAtLeast(500)`, which keeps relative odds, so ~54% of pity rolls are Mouse and ~27% Lighthouse.
- "Free rolls" (wheel, orbs) are bonus rolls the server plays immediately, ignoring cooldown; like any roll they replace current height.
- Sky reachability is by jump height (7.2 x scale^0.75): Cloud Layer steps need ~Colossus (35x) or bigger; the Celestial Layer needs World Eater. Sky Blessing lasts while a downward ray from the root hits SkyRealm.
- Gamepass ids are 0 (placeholders) until set; in Studio the shop buttons toggle passes instead of prompting.
- Index: a tier is discovered once rolled; saves keep the most extreme scale per tier. Equipping from the Index is server-validated.
- Height ruler marks use 5.2 studs per 1x (standard R15). Avatars with tall body scales stand above their mark.
- Giant fix: Roblox inflates animated joint translation by scale^2 on scaled characters, sinking 35x+ bodies through the floor. Every machine animates every character, so both RollClient (all characters) and RollServer keep animated rotation but drop translation for characters >= 2x. `StarterPlayer.AvatarJointUpgrade` is set to Disabled in the place.
- Common tiers vary ±6% in height. Tiers rarer than 1 in 100 are always exact.
- "Best" means rarest; within a tier, the more extreme size wins. Equip Best returns you to it.
- Saves store tier names (not indexes) plus current/best scale and roll count. Current height persists on rejoin.
- Banner and chat announcement for tiers marked `announce` (Ant, Microbe, Quantum, and Lighthouse and up).

## Status
- Tested in Studio (place "Roll a Height!", published): rolling, auto-roll, saving, all tier sizes 0.02x-200x (client and server view), Index equip + persistence, group perk, top-3 board (single player only), Essence + wheel spin (Super Surge prize, physical wheel landed on the right segment), pity-roll odds (200k simulation), shop pass toggles (2x Luck, Fast Roll 0.4s, VIP tag), Sky Blessing on/off, orbs (surge and free roll), Nebula aura, footstep sounds.
- Not yet tested live: friend boost and the board with several players, real gamepass purchases, the [VIP] chat prefix, other players seeing giants (should be fixed by the client fix covering all characters).
- `GROUP_ID` (5353332) and the `GAMEPASSES` ids (0) in RollServer are placeholders.
- Cosmetic: on the clouds a 200x giant's root sits ~50 studs lower than on the baseplate (feet sink into the 30-stud cloud slab).

## Roadmap (the user's plan)
- Size-based gameplay: giants step over walls, tiny players enter secret holes.
- Monetization: luck boosts, auto-roll, VIP, extra save slots.
- Punchy, TikTok-clippable visuals: add sounds and a bigger map.
