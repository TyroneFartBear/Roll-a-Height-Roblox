# Roll Your Height — project context

Roblox RNG game: each roll sets the character's height, from Quantum (0.02x, 1 in 500,000) to World Eater (200x, 1 in 1,000,000). Being huge is the flex, and tiny is a rare flex too.

## The user
- Zero coding and zero Roblox Studio experience. Strong on game design and progression loops.
- Act as their lead developer. Explain simply, go one step at a time, and say exactly what to test after each step.
- They paste scripts into Studio by hand (see SETUP.md), unless a Claude on their own computer is connected to Roblox's Studio MCP server. Cloud sessions can't reach their Studio.

## Code (Rojo-style names; each file maps to one Studio object)
- `src/ReplicatedStorage/RarityTable.lua`: ModuleScript. Has the 20-tier list (colors + aura bracket per tier), the roll, `RollAtLeast`, odds and height formatting. **Rebalance only here.**
- `src/ServerScriptService/RollServer.server.lua`: Script. Server-side roll and cooldown, creates the RemoteEvents (`ReplicatedStorage.Remotes`), resizes with `Model:ScaleTo` (feet kept on the ground; WalkSpeed, JumpHeight and HipHeight adjusted), auras per bracket, leaderstats and announcements, DataStore saving (`RollYourHeight_v1`), Equip Best, Index equip (`EquipTier`), Studio-only force roll. Also: friend boost and group perk (`GROUP_ID`), discovered tiers (`Discovered` JSON attribute), live top-3 board, all luck math (`computeLuck` -> `LuckInfo` JSON attribute), Growth Essence, Growth Spinner, Sky Altars/Orbs, Sky Jump, bonus-roll queue, Crush Pit, gamepasses (`GAMEPASSES` ids, `DEBUG_UNLOCK_PASSES`), VIP overhead tag, and the server copy of the giant animation fix.
- `src/StarterPlayerScripts/RollClient.client.lua`: LocalScript. Builds the UI in code: ROLL (R key), AUTO (needs the Auto Roll pass; 1.5s, 0.45s with Fast Roll), EQUIP BEST, luck badge (renders `LuckInfo`), INDEX / SHOP / SPINNER buttons on the left, toasts (`Notify`), Crush Pit bounce (`Bounce`), slot-machine spin, result popup (+Essence), flash and shake, camera zoom by size, giant footstep thuds + shake (10x+), local-only tier effects (void crystals orbiting "Void", cosmic rings around "Godly", footstep shockwaves at 150x+), [VIP] chat prefix, rare-roll banner + chat message, Studio-only FORCE panel, and the giant animation fix for every character. The `SOUNDS` table is empty and waiting for asset IDs.
- Map objects live in the place file, not the repo:
  - `Workspace.Baseplate` + `MapSafety.Ground`: 10,000 x 10,000 grass island (5x5 tiles of 2000). `MapSafety.Walls`: invisible 2048-tall walls at +/-5000. `MapSafety.Scenery`: trees, rocks, lanterns (kept away from spawn, features and the sky footprint).
  - `MapSafety.SkyRealm`: Cloud Layer (top 250; stepping clouds at 60/120/180; ruins, arch), Celestial stepping stones (360/470/580/690), Celestial Layer (top 800), floating ruin islands, two altars (beam tagged `SkyAltar`), eight orbs tagged `SkyOrb` (`BaseTransparency` attribute).
  - `Workspace.Lobby`: spawn plaza + cobblestone `Paths`, `HeightRuler`, `TopRollsBoard` (`Display` rows `Row1`-`Row3`), `GrowthSpinner` (`Hub` + ProximityPrompt, `BaseCFrame` attribute; its 100 rim tiles must match `WHEEL` weights; Mythic tiles have the `Prismatic` attribute), `CrushPit` (`Center`/`Radius` attributes, `Display` rows). RollServer skips anything missing.

## Design decisions
- Exact odds: each tier gets 1/oneIn of the roll, and "Average" gets the leftover (~37%). Odds were verified with a 10M-roll Luau simulation.
- Luck = (`Luck` attribute + friend +10%/friend max +50% + group +15% + VIP +25% + Sky Blessing +25% + spinner +15% (60s) + Growth Overcharge +100% (5 rolls)) x (2x Luck pass) x (orb 1.5x, 60s) x (Godspeed 10x, 3 rolls), capped at 25x (`MAX_LUCK`). Luck only multiplies tiers 1 in 100 or rarer.
- Growth Essence: rolls more common than 1 in 100 give 1 / 2 / 3 Essence (1 in <10 / 10-29 / 30-99), ~1.25 per roll on average; a spin costs 50 (~40 rolls). Crush Pit also gives Essence. Saved.
- Growth Spinner odds 40/27/16/10/5/2: Common +15% luck 60s / Uncommon 5 fast free rolls / Rare Sky Jump (3x jump height, 120s) / Epic Growth Overcharge / Legendary Titan Surge (`RollAtLeast(250)`, keeps relative odds, so it is usually Giant) / Mythic Godspeed.
- "Free rolls" (spinner, orbs) are bonus rolls the server plays immediately, ignoring cooldown; like any roll they replace current height.
- Sky reachability is by jump height (7.2 x scale^0.75, x3 with Sky Jump): the Cloud Layer steps need ~Colossus (35x); the celestial stones (110-stud rises) need Storm Titan (60x), or Colossus with Sky Jump. Sky Blessing lasts while a downward ray from the root hits SkyRealm.
- Aura brackets: small/common (under 10x and more common than 1 in 500) = "Earth" with earth-tone colors; 10x-49x = "Electric" (+ ground dust); Storm Titan = "Embers", Planet Breaker = "Void"; World Eater = "Godly". Tiny rare tiers (Mouse/Ant/Microbe/Quantum) and Lighthouse keep their own glow.
- Crush Pit: players 10x+ whose foot is over the pit bounce players 2x or smaller (client-applied launch, no damage): +3 Essence bounced, +2 stomper, +1 each every 10s while both share the pit.
- Gamepass ids are 0 (placeholders) until set. In Studio, `DEBUG_UNLOCK_PASSES = true` starts every pass unlocked and the shop buttons toggle passes; it never applies live.
- Index: a tier is discovered once rolled; saves keep the most extreme scale per tier. Equipping from the Index is server-validated.
- Height ruler marks use 5.2 studs per 1x (standard R15). Avatars with tall body scales stand above their mark.
- Giant fix: Roblox inflates animated joint translation by scale^2 on scaled characters, sinking 35x+ bodies through the floor. Every machine animates every character, so both RollClient (all characters) and RollServer keep animated rotation but drop translation for characters >= 2x. `StarterPlayer.AvatarJointUpgrade` is set to Disabled in the place.
- Common tiers vary ±6% in height. Tiers rarer than 1 in 100 are always exact.
- "Best" means rarest; within a tier, the more extreme size wins. Equip Best returns you to it.
- Saves store tier names (not indexes) plus current/best scale, roll count, essence and discovered tiers. Current height persists on rejoin.
- Banner and chat announcement for tiers marked `announce` (Ant, Microbe, Quantum, and Lighthouse and up).
- Visual tone: grass/cobblestone ground, softer Lighting (Bloom 0.35, Atmosphere haze, `GroundedGrade` color correction); sky neon at 0.5 transparency in pastel cyan/lavender/amber; no neon on the spinner.

## Status
- Tested in Studio (place "Roll a Height!", published): rolling, auto-roll + its pass lock, saving, all tier sizes 0.02x-200x (client and server view), every aura bracket and the local orbiters/shockwaves, Index, group perk, top-3 board (single player), Essence + spinner (Sky Jump x3 and Titan Surge prizes, physical spinner landed on the right slice, prismatic tiles cycling), shop pass toggles, Sky Blessing, orbs, footstep sounds, the Crush Pit bounce on the client and giant detection.
- Not yet tested live: an actual giant-stomps-small-player bounce (needs two players), friend boost and boards with several players, real gamepass purchases, the [VIP] chat prefix.
- `GROUP_ID` (5353332) and the `GAMEPASSES` ids (0) in RollServer are placeholders.
- Cosmetic: on the clouds a 200x giant's root sits ~50 studs lower than on the ground (feet sink into the cloud slab).

## Roadmap (the user's plan)
- Size-based gameplay: giants step over walls, tiny players enter secret holes.
- Monetization: luck boosts, auto-roll, VIP, extra save slots.
- Punchy, TikTok-clippable visuals: add sounds.
