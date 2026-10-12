# Roll Your Height — Setup Guide (zero experience needed)

You'll paste 3 scripts into Roblox Studio. Do the steps in order and test each one before moving on.

## The 3 kinds of script in Roblox

| Type | Runs on | Used for |
|---|---|---|
| **ModuleScript** | Whoever `require`s it | Shared data, like our tier list |
| **Script** | The server (Roblox's computer) | Anything players must not be able to cheat: rolling, saving |
| **LocalScript** | Each player's device | Anything a player sees: buttons, popups, camera |

## Step 0: Open a blank Baseplate

1. Open Roblox Studio and click **New → Baseplate**.
2. Open these 3 panels from the **View** tab (top menu): **Explorer**, **Properties** and **Output**.
   - **Explorer** is the tree of everything in your game.
   - **Output** shows errors (red) and warnings (orange). Keep it open all the time.

**Test:** Press **Play** (or F5). You should spawn on a grey baseplate. Press **Stop** (Shift+F5).

## Step 1: The tier list (ModuleScript)

1. In Explorer, hover over **ReplicatedStorage**, click the **+** and choose **ModuleScript**.
2. Right-click it → **Rename** → type `RarityTable` (exact spelling and capitals).
3. Double-click it, delete everything inside, and paste in all of [`src/ReplicatedStorage/RarityTable.lua`](src/ReplicatedStorage/RarityTable.lua).

**Test:** Press Play. Nothing visible changes yet. Check that **Output has no red text**. Stop.

## Step 2: The game brain (Script)

1. Hover over **ServerScriptService** → **+** → **Script**.
2. Rename it `RollServer`.
3. Paste in all of [`src/ServerScriptService/RollServer.server.lua`](src/ServerScriptService/RollServer.server.lua).

**Test:** Press Play.
- The top-right leaderboard now shows **Height: Average**, **Best: Average** and **Rolls: 0**.
- Output shows an orange warning that says *"Saving is OFF…"*. That's expected for now and Step 4 fixes it.
- Inside ReplicatedStorage you'll see a new folder called **Remotes** (only while playing).

## Step 3: The screen (LocalScript)

1. In Explorer, expand **StarterPlayer**. Hover over **StarterPlayerScripts** → **+** → **LocalScript**.
2. Rename it `RollClient`.
3. Paste in all of [`src/StarterPlayerScripts/RollClient.client.lua`](src/StarterPlayerScripts/RollClient.client.lua).

**Test:** Press Play.
- [ ] A pink **ROLL** button appears at the bottom, with **EQUIP BEST** next to it.
- [ ] Clicking ROLL (or pressing **R**) spins tier names, which slow down and land on a result with its name, title, odds and height.
- [ ] Your character changes size when the result lands, and the camera zooms to fit.
- [ ] The leaderboard updates: Height, Best and Rolls.
- [ ] **Studio test panel** (top-left, only visible in Studio): type a tier number and press **FORCE**.
  - `20` gives World Eater: a huge flash, shake, cosmic aura, a 1,150 ft titan and a banner at the top.
  - `1` gives Quantum: you become a speck. Zoom in with the scroll wheel.
  - `13` gives Giant: sparkles and a light shake.
- [ ] After a big roll, press **EQUIP BEST** following a normal roll. You should return to your best size.
- [ ] Reset your character (Esc → Reset). You should respawn at the same size.

**Test the announcement with 2 players:** go to **Test** tab → set **Clients and Servers** to **2 Players** → **Start**. Force tier `15` in one window. The *other* window should get the banner at the top and a chat message.

## Step 4: Saving (DataStores)

Saving only works on a published game.

1. **File → Publish to Roblox**. Give it a name. It can stay private.
2. **Home → Game Settings → Security** → turn on **Enable Studio Access to API Services** → Save.

**Test:**
- [ ] Press Play. The *"Saving is OFF"* warning is gone.
- [ ] Force tier `16` (Mountain). Stop. Press Play again. Leaderboard **Best** still says Mountain, and you spawn at the height you had when you stopped.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `RarityTable is not a valid member of ReplicatedStorage` | The ModuleScript isn't named exactly `RarityTable` or isn't in ReplicatedStorage |
| Button doesn't appear | You used a Script instead of a **LocalScript**, or it's not in StarterPlayerScripts |
| Button stuck on "..." | Look in Output for red text from RollServer |
| Titan falls off the map | The baseplate is only 2,048 studs wide. A bigger map comes later |
