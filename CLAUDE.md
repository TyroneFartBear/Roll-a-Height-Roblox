# Roll Your Height — project context

Roblox RNG game: each roll sets the character's height, from Quantum (0.02x, 1 in 500,000) to World Eater (200x, 1 in 1,000,000). Being huge is the flex, and tiny is a rare flex too.

## The user
- Zero coding and zero Roblox Studio experience. Strong on game design and progression loops.
- Act as their lead developer. Explain simply, go one step at a time, and say exactly what to test after each step.
- They paste scripts into Studio by hand (see SETUP.md), unless a Claude on their own computer is connected to Roblox's Studio MCP server. Cloud sessions can't reach their Studio.

## Code (Rojo-style names; each file maps to one Studio object)
- `src/ReplicatedStorage/RarityTable.lua`: ModuleScript. Has the 20-tier list, the roll, odds and height formatting. **Rebalance only here.**
- `src/ServerScriptService/RollServer.server.lua`: Script. Handles the server-side roll and cooldown, creates the RemoteEvents (`ReplicatedStorage.Remotes`), resizes with `Model:ScaleTo` (feet kept on the ground; WalkSpeed, JumpHeight and HipHeight adjusted), adds auras, leaderstats and announcements, saves with a DataStore (`RollYourHeight_v1`), and handles Equip Best, Index equip (`EquipTier`) and the Studio-only force roll. It also sets the friend boost (`FriendBoost`) and group perk (`GroupBoost`, `GROUP_ID` constant), tracks discovered tiers (`Discovered` attribute, JSON), and fills the live top-3 board.
- `src/StarterPlayerScripts/RollClient.client.lua`: LocalScript. Builds the UI in code: ROLL button (R key), AUTO toggle (1.5s), EQUIP BEST, luck badge, INDEX panel, slot-machine spin, result popup, flash and shake, camera zoom by size, top banner plus a chat message for rare rolls, and a Studio-only FORCE test panel. It also holds the giant animation fix (see below). The `SOUNDS` table is empty and waiting for asset IDs.
- Map objects live in the place file, not the repo: `Workspace.MapSafety` (6144x6144 floor + 2048-tall invisible walls) and `Workspace.Lobby` (spawn plaza, `HeightRuler` wall, `TopRollsBoard` with `Display` SurfaceGui rows `Row1`-`Row3`). RollServer skips the board if it's missing.

## Design decisions
- Exact odds: each tier gets 1/oneIn of the roll, and "Average" gets the leftover (~37%). Odds were verified with a 10M-roll Luau simulation.
- Luck = `Luck` attribute (default 1, hook for potions/VIP) + `FriendBoost` (+10% per friend in server, max +50%) + `GroupBoost` (+15%). Luck only multiplies tiers 1 in 100 or rarer. It stays balanced up to about 25x.
- Index: a tier is discovered once rolled; saves keep the most extreme scale per tier. Equipping from the Index is server-validated.
- Height ruler marks use 5.2 studs per 1x (standard R15). Avatars with tall body scales stand above their mark.
- Giant fix: Roblox inflates animated joint translation by scale^2 on scaled characters, sinking 35x+ bodies through the floor. RollClient keeps animated rotation but drops translation for characters >= 2x. `StarterPlayer.AvatarJointUpgrade` is set to Disabled in the place.
- Common tiers vary ±6% in height. Tiers rarer than 1 in 100 are always exact.
- "Best" means rarest; within a tier, the more extreme size wins. Equip Best returns you to it.
- Saves store tier names (not indexes) plus current/best scale and roll count. Current height persists on rejoin.
- Banner and chat announcement for tiers marked `announce` (Ant, Microbe, Quantum, and Lighthouse and up).

## Status
- Tested in Studio (place "Roll a Height!", published): rolling, auto-roll, saving, all tier sizes 0.02x-200x, Index equip + persistence, group perk, top-3 board (single player only).
- Not yet tested live: friend boost (needs real friends in one server) and the board with several players.
- `GROUP_ID` in RollServer is a placeholder (5353332); set it to the real group.

## Roadmap (the user's plan)
- Size-based gameplay: giants step over walls, tiny players enter secret holes.
- Monetization: luck boosts, auto-roll, VIP, extra save slots.
- Punchy, TikTok-clippable visuals: add sounds and a bigger map.
