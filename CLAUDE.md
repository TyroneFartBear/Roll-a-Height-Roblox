# Roll Your Height — project context

Roblox RNG game: each roll sets the character's height, from Quantum (0.02x, 1 in 500,000) to World Eater (200x, 1 in 1,000,000). Being huge is the flex, and tiny is a rare flex too.

## The user
- Zero coding and zero Roblox Studio experience. Strong on game design and progression loops.
- Act as their lead developer. Explain simply, go one step at a time, and say exactly what to test after each step.
- They paste scripts into Studio by hand (see SETUP.md), unless a Claude on their own computer is connected to Roblox's Studio MCP server. Cloud sessions can't reach their Studio.

## Code (Rojo-style names; each file maps to one Studio object)
- `src/ReplicatedStorage/RarityTable.lua`: ModuleScript. Has the 20-tier list, the roll, odds and height formatting. **Rebalance only here.**
- `src/ServerScriptService/RollServer.server.lua`: Script. Handles the server-side roll and cooldown, creates the RemoteEvents (`ReplicatedStorage.Remotes`), resizes with `Model:ScaleTo` (feet kept on the ground; WalkSpeed, JumpHeight and HipHeight adjusted), adds auras, leaderstats and announcements, saves with a DataStore (`RollYourHeight_v1`), and handles Equip Best and the Studio-only force roll.
- `src/StarterPlayerScripts/RollClient.client.lua`: LocalScript. Builds the UI in code: ROLL button (R key), slot-machine spin, result popup, flash and shake, camera zoom by size, top banner plus a chat message for rare rolls, and a Studio-only FORCE test panel. The `SOUNDS` table is empty and waiting for asset IDs.

## Design decisions
- Exact odds: each tier gets 1/oneIn of the roll, and "Average" gets the leftover (~37%). Odds were verified with a 10M-roll Luau simulation.
- Luck (player attribute `Luck`, default 1) only multiplies tiers 1 in 100 or rarer. It stays balanced up to about 25x.
- Common tiers vary ±6% in height. Tiers rarer than 1 in 100 are always exact.
- "Best" means rarest; within a tier, the more extreme size wins. Equip Best returns you to it.
- Saves store tier names (not indexes) plus current/best scale and roll count. Current height persists on rejoin.
- Banner and chat announcement for tiers marked `announce` (Ant, Microbe, Quantum, and Lighthouse and up).

## Status
- v1 is written and compile-checked with `luau-compile`, but **not yet tested in Studio**.
- Known risks: Quantum 0.02x may be physics-jittery (fallback: 0.04). Titans outgrow the 2048-stud baseplate.

## Roadmap (the user's plan)
- Size-based gameplay: giants step over walls, tiny players enter secret holes.
- Monetization: luck boosts, auto-roll, VIP, extra save slots.
- Punchy, TikTok-clippable visuals: add sounds and a bigger map.
