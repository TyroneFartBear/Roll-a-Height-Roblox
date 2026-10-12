# Roll Your Height — project context

Roblox RNG game: each roll sets the character's height, from Quantum (0.02x, 1 in 500,000) to World Eater (200x, 1 in 1,000,000). Being huge is the flex, and tiny is a rare flex too.

## The user
- Zero coding and zero Roblox Studio experience. Strong on game design and progression loops.
- Act as their lead developer. Explain simply, go one step at a time, and say exactly what to test after each step.
- They paste scripts into Studio by hand (see SETUP.md), unless a Claude on their own computer is connected to Roblox's Studio MCP server. Cloud sessions can't reach their Studio.

## Code (Rojo-style names; each file maps to one Studio object)
- `src/ReplicatedStorage/RarityTable.lua`: ModuleScript. Has the 20-tier list (colors + aura bracket per tier), the roll, `RollAtLeast`, odds and height formatting. **Rebalance only here.**
- `src/ServerScriptService/RollServer.server.lua`: Script. Server-side roll and cooldown, creates the RemoteEvents (`ReplicatedStorage.Remotes`), resizes with `Model:ScaleTo` (feet kept on the ground; WalkSpeed, JumpHeight and HipHeight adjusted), auras per bracket, leaderstats and announcements, DataStore saving (`RollYourHeight_v1`), Equip Best, Index equip (`EquipTier`), Studio-only force roll. Also: friend boost and group perk (`GROUP_ID`), discovered tiers (`Discovered` JSON attribute), live top-3 board, all luck math (`computeLuck` -> `LuckInfo` JSON attribute), Growth Essence, Growth Spinner, Sky Altars/Orbs, Sky Jump, bonus-roll queue, Crush Pit, gamepasses (`GAMEPASSES` ids, `DEBUG_UNLOCK_PASSES`), VIP overhead tag, Wind Launchers, Titan's Throne + Titan's Favor, Ground Shaker Stomp (`Stomp`/`StompFx`), settings saving (`SaveSettings`, `Settings` attribute), and the server copy of the giant animation fix.
- `src/StarterPlayerScripts/RollClient.client.lua`: LocalScript. Builds the UI in code: ROLL (R key), AUTO (needs the Auto Roll pass; 1.5s, 0.45s with Fast Roll), EQUIP BEST, luck badge (renders `LuckInfo`), INDEX / SHOP / SPINNER buttons on the left, toasts (`Notify`), launches (`Bounce`, held as a ballistic arc for launchers), slot-machine spin, result popup (+Essence), flash and shake, camera zoom limits by size (max 3000, min 2.5 x scale from 2x up), giant footsteps (10x+), stomp FX, STOMP [F] / VIEW [V] (Colossal Viewport) + on-screen buttons, SETTINGS (Music / SFX / Low GFX) and MUTE on the right edge, BGM playlist, `SOUNDS` (built-ins + APM / Pro Sound Effects ids), Growth Spinner ticks, UI click sound, local-only tier effects (ground glyph for "Lightning", void orbs for "Super", shockwaves at 150x+, arc crackle, pulsing light), spinning sky decor (tag `SkySpin`), [VIP] chat prefix, rare-roll banner + chat message, Studio-only FORCE panel, and the giant animation fix for every character.
- Map objects live in the place file, not the repo:
  - `Workspace.Baseplate` + `MapSafety.Ground`: 10,000 x 10,000 grass island (5x5 tiles of 2000). `MapSafety.Walls`: invisible 2048-tall walls at +/-5000. `MapSafety.Scenery`: trees, rocks, lanterns (kept away from spawn, features and the sky footprint).
  - `MapSafety.SkyRealm`: Cloud Layer (top 250; stepping clouds at 60/120/180; ruins, arch, `EtherealGarden`, `Waterfalls`), Celestial stepping stones (360/470/580/690), `StellarSanctum` (top 800; dark constellation floor, astrolabes and a crystal ring tagged `SkySpin`), `VoidPlatforms` (top 800, 100-stud gaps), `TitansThrone` (top 1000 at 1800,2390; `ApexPedestal` tag; crown tagged `SkySpin`), floating ruin islands, two altars (beam tagged `SkyAltar`), eight orbs tagged `SkyOrb` (`BaseTransparency` attribute).
  - `Workspace.Lobby`: spawn plaza + cobblestone `Paths`, `WindLaunchers` (pads tagged `WindLauncher` with `Target`/`FlightTime`), `HeightRuler`, `TopRollsBoard` (`Display` rows `Row1`-`Row3`), `GrowthSpinner` (`Hub` + ProximityPrompt, `BaseCFrame` attribute; its 100 rim tiles must match `WHEEL` weights; Mythic tiles have the `Prismatic` attribute; `RimGlow`; `Platform` with the `SpinSwirl` emitter), `CrushPit` (`Center`/`Radius` attributes, `Display` rows). RollServer skips anything missing.
  - Lighting: Atmosphere 0.32/0.25/0.8/0.15, Bloom 24/0.85/0.65, `AnimeGrade` color correction 0.02/0.12/0.2, SunRays 0.12/0.75. `Technology` can't be set from scripts; set it to Future in Studio.

## Design decisions
- Exact odds: each tier gets 1/oneIn of the roll, and "Average" gets the leftover (~37%). Odds were verified with a 10M-roll Luau simulation.
- Luck = (`Luck` attribute + friend +10%/friend max +50% + group +15% + VIP +25% + Sky Blessing +25% + spinner +15% (60s) + Growth Overcharge +100% (5 rolls)) x (2x Luck pass) x (orb 1.5x, 60s) x (Godspeed 10x, 3 rolls), capped at 25x (`MAX_LUCK`). Luck only multiplies tiers 1 in 100 or rarer.
- Growth Essence: rolls more common than 1 in 100 give 1 / 2 / 3 Essence (1 in <10 / 10-29 / 30-99), ~1.25 per roll on average; a spin costs 50 (~40 rolls). Crush Pit also gives Essence. Saved.
- Growth Spinner odds 40/27/16/10/5/2: Common +15% luck 60s / Uncommon 5 fast free rolls / Rare Sky Jump (3x jump height, 120s) / Epic Growth Overcharge / Legendary Titan Surge (`RollAtLeast(250)`, keeps relative odds, so it is usually Giant) / Mythic Godspeed.
- "Free rolls" (spinner, orbs) are bonus rolls the server plays immediately, ignoring cooldown; like any roll they replace current height.
- Sky reachability is by jump height (7.2 x scale^0.75, x3 with Sky Jump): the Cloud Layer steps need ~Colossus (35x); the celestial stones (110-stud rises) need Storm Titan (60x), or Colossus with Sky Jump. Sky Blessing lasts while a downward ray from the root hits SkyRealm.
- Aura brackets: small/common (under 10x and more common than 1 in 500) = "Earth" with earth-tone colors; Skyscraper/Mountain = "Ki" (cyan/gold outline, rising flames); Colossus/Storm Titan/Planet Breaker = "Lightning" (arcs + ground glyph; the user filed Colossus here though it is 35x); World Eater = "Super" (cosmic pillars, void orbs, pulsing light, dark arcs, footstep shockwaves). Tiny rare tiers (Mouse/Ant/Microbe/Quantum) and Lighthouse keep their own glow.
- Movement: WalkSpeed = clamp(16 x scale^0.45, 16, 120).
- Wind Launchers (2.5x or smaller, 3s cooldown): to the first cloud step (60), West meadow, far northwest. Normal-sized players can't climb higher than step 1, so the clouds stay giant content.
- Titan's Throne (1000 studs): 100x+ standing on it get +50% luck, everyone else +10% Titan's Favor. Reachable via void platforms + a 200-stud rise (Planet Breaker/World Eater, or Storm Titan with Sky Jump, who gets no bonus below 100x).
- Stomp (F, 50x+, 10s cooldown): boom + shockwave for everyone; pops players at most a tenth of the stomper's size within 4 x scale studs.
- Settings (music / sfx / lowGfx) are saved in the player's data and applied on join; Low GFX hides other players' aura effects and turns off bloom, sun rays, depth of field, shadows and cloud mist locally.
- Crush Pit: players 10x+ whose foot is over the pit bounce players 2x or smaller (client-applied launch, no damage): +3 Essence bounced, +2 stomper, +1 each every 10s while both share the pit.
- Gamepass ids are 0 (placeholders) until set. In Studio, `DEBUG_UNLOCK_PASSES = true` starts every pass unlocked and the shop buttons toggle passes; it never applies live.
- Index: a tier is discovered once rolled; saves keep the most extreme scale per tier. Equipping from the Index is server-validated.
- Height ruler marks use 5.2 studs per 1x (standard R15). Avatars with tall body scales stand above their mark.
- Giant fix: Roblox inflates animated joint translation by scale^2 on scaled characters, sinking 35x+ bodies through the floor. Every machine animates every character, so both RollClient (all characters) and RollServer keep animated rotation but drop translation for characters >= 2x. `StarterPlayer.AvatarJointUpgrade` is set to Disabled in the place.
- Common tiers vary ±6% in height. Tiers rarer than 1 in 100 are always exact.
- "Best" means rarest; within a tier, the more extreme size wins. Equip Best returns you to it.
- Saves store tier names (not indexes) plus current/best scale, roll count, essence and discovered tiers. Current height persists on rejoin.
- Banner and chat announcement for tiers marked `announce` (Ant, Microbe, Quantum, and Lighthouse and up).
- Visual tone: grass/cobblestone ground, anime-style post-processing (see Lighting above), pastel sky neon at 0.4-0.6 transparency, metal spinner with a soft glowing rim.

## Status
- Tested in Studio (place "Roll a Height!", published): rolling, auto-roll + its pass lock, saving, all tier sizes 0.02x-200x (client and server view), every aura bracket and the local glyph/orbs, walk speed and camera limits per size, Index, group perk, top-3 board (single player), Essence + spinner, shop pass toggles, Sky Blessing, orbs, all sounds load (APM / Pro Sound Effects / built-ins) and the BGM plays, stomp + cooldown, Colossal Viewport on/off, Titan's Throne bonus on/off, Wind Launcher landing on the first cloud step, Settings panel (Low GFX, Music) + persistence, Crush Pit bounce on the client and giant detection.
- Not yet tested live (needs 2+ players): giant-stomps-small-player bounce in the pit, stomp popping other players, Titan's Favor for others, friend boost, boards with several players; also real gamepass purchases and the [VIP] chat prefix.
- `GROUP_ID` (5353332) and the `GAMEPASSES` ids (0) in RollServer are placeholders.
- Cosmetic: on the clouds a 200x giant's root sits ~50 studs lower than on the ground (feet sink into the cloud slab).

## Roadmap (the user's plan)
- Size-based gameplay: giants step over walls, tiny players enter secret holes.
- Monetization: luck boosts, auto-roll, VIP, extra save slots.
- Punchy, TikTok-clippable visuals.
