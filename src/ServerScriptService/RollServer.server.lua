--[[
	RollServer  (Script)
	Goes in: ServerScriptService   Name it: RollServer

	The server is the referee. It does the actual dice roll (so players
	can't cheat), resizes characters, saves progress and tells everyone
	about rare rolls. The client only asks "please roll" and shows effects.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService") -- only for JSONEncode, no web requests
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local RarityTable = require(ReplicatedStorage:WaitForChild("RarityTable"))
local Tiers = RarityTable.Tiers

---------------------------------------------------------------------
-- SETTINGS (safe to tweak)
---------------------------------------------------------------------
local ROLL_COOLDOWN = 1.3 -- seconds between rolls per player (spin is 1.2s, auto-roll fires every 1.5s)
local SPIN_TIME = 1.2 -- how long the "slot machine" spins before the reveal
local AUTOSAVE_INTERVAL = 90 -- seconds
local DATASTORE_NAME = "RollYourHeight_v1" -- change this to wipe everyone's saves
local BASE_WALKSPEED = 16
local BASE_JUMP_HEIGHT = 7.2
local FRIEND_BOOST_PER_FRIEND = 0.10 -- +10% luck per Roblox friend in the same server
local FRIEND_BOOST_MAX = 0.50 -- capped at +50%
local GROUP_ID = 5353332 -- placeholder: set this to your group's id
local GROUP_BOOST = 0.15 -- flat +15% luck for group members, stacks with friend boost
local MAX_LUCK = 25 -- all boosts together are capped here; RarityTable stays balanced up to ~25x

-- Rags to Riches: Growth Essence from common rolls, spent on the Gambler's Wheel
local ESSENCE_MAX_ONE_IN = 100 -- only rolls more common than 1 in 100 give Essence (1-3, rarer = more)
local ESSENCE_PER_SPIN = 50
local WHEEL_SPIN_TIME = 4 -- seconds the wheel spins before the prize
local WHEEL_LUCK_BOOST = 0.15
local WHEEL_LUCK_TIME = 60
local SURGE_BOOST = 1.0 -- Super Surge: +100% luck
local JACKPOT_MULT = 10
local WHEEL = { -- weights must add up to 100: the physical wheel has 100 rim tiles, in this order
	{ key = "Luck15", weight = 45, label = "+15% Luck for 60 seconds", color = Color3.fromRGB(80, 170, 255) },
	{ key = "FreeRolls", weight = 30, label = "3 Instant Free Rolls!", color = Color3.fromRGB(80, 220, 120) },
	{ key = "SuperSurge", weight = 15, label = "SUPER SURGE!  +100% Luck for 3 rolls", color = Color3.fromRGB(180, 90, 255) },
	{ key = "TitanPity", weight = 8, label = "TITAN PITY ROLL!  Guaranteed 1 in 500 or rarer", color = Color3.fromRGB(255, 140, 40) },
	{ key = "Jackpot", weight = 2, label = "JACKPOT!!  10x Luck for your next 5 rolls", color = Color3.fromRGB(255, 215, 0) },
}

-- Sky Realm (cloud layers, altars and orbs are built in Studio and found by tag)
local SKY_BLESSING = 0.25 -- +25% luck after touching a Sky Altar, while you stand over a cloud
local ORB_RESPAWN = 90 -- seconds before a collected Sky Orb comes back
local ORB_SURGE_TIME = 60
local ORB_LUCK_MULT = 1.5

-- Gamepasses: put your real gamepass ids here (0 = not on sale yet)
local GAMEPASSES = {
	Luck2x = { id = 0, name = "2x Luck" },
	FastRoll = { id = 0, name = "Fast Roll" },
	VIP = { id = 0, name = "VIP" },
}
local STUDIO_PASSES = { Luck2x = false, FastRoll = false, VIP = false } -- Studio playtests start with these on
local VIP_BOOST = 0.25
local FAST_ROLL_COOLDOWN = 0.35
local FAST_SPIN_TIME = 0.4

---------------------------------------------------------------------
-- REMOTES: the "phone lines" between client and server.
-- Created here so you don't have to make them by hand in Studio.
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"

local function newRemote(name)
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local rollRequest = newRemote("RollRequest") -- client -> server: "roll for me"
local rollResult = newRemote("RollResult") -- server -> one client: "here's what you got"
local announce = newRemote("Announce") -- server -> everyone: "someone rolled something rare"
local equipBest = newRemote("EquipBest") -- client -> server: "go back to my best height"
local devForceRoll = newRemote("DevForceRoll") -- Studio-only testing shortcut
local equipTier = newRemote("EquipTier") -- client -> server: "equip this tier from my Index"
local spinWheel = newRemote("SpinWheel") -- client -> server: "spin the Gambler's Wheel"
local shopRequest = newRemote("ShopRequest") -- client -> server: "buy this pass" (Studio: toggle it)
local notify = newRemote("Notify") -- server -> one client: a short message for the toast
for key, pass in pairs(GAMEPASSES) do
	remotes:SetAttribute("PassId_" .. key, pass.id) -- the shop reads these to show prices
end
remotes:SetAttribute("EssencePerSpin", ESSENCE_PER_SPIN)
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- PLAYER DATA
---------------------------------------------------------------------
local storeOk, store = pcall(function()
	return DataStoreService:GetDataStore(DATASTORE_NAME)
end)
if not storeOk then
	warn("[RollServer] DataStore unavailable (" .. tostring(store) .. "). Saving is OFF this session.")
	store = nil
end
local rng = Random.new()
local playerData = {} -- [player] = { currentId, currentScale, bestId, bestScale, rolls, canSave }
local lastRollTime = {} -- [player] = os.clock() of their last roll
local effects = {} -- [player] = temporary boosts and owned passes (not saved), see newEffects()

local function defaultData()
	return {
		currentId = RarityTable.FallbackId,
		currentScale = 1,
		bestId = RarityTable.FallbackId,
		bestScale = 1,
		rolls = 0,
		essence = 0, -- Growth Essence: earned from common rolls, spent on the wheel
		discovered = {}, -- [tierName] = most extreme scale rolled for that tier
		canSave = false,
	}
end

local function newEffects()
	return {
		passes = {}, -- [passKey] = true
		sky = false, -- Sky Blessing, lost when you leave the clouds
		wheelLuckUntil = 0, -- os.clock() when the wheel's +15% ends
		orbUntil = 0, -- os.clock() when a Sky Orb's 1.5x ends
		surgeRolls = 0, -- rolls left with Super Surge
		jackpotRolls = 0, -- rolls left with Jackpot
		bonusRolls = 0, -- free rolls waiting to be played
		bonusRunning = false,
		wheelBusy = false,
	}
end

local function markDiscovered(data, tierId, scale)
	local name = Tiers[tierId].name
	local old = data.discovered[name]
	if old == nil or math.abs(math.log(scale)) > math.abs(math.log(old)) then
		data.discovered[name] = scale
	end
end

local function loadData(player)
	local key = "player_" .. player.UserId
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return store:GetAsync(key)
		end)
		if ok then
			return result, true
		end
		warn(("[RollServer] Load attempt %d failed for %s: %s"):format(attempt, player.Name, tostring(result)))
		if RunService:IsStudio() then
			warn("[RollServer] Saving is OFF. To test saving: publish the game, then Game Settings > Security > Enable Studio Access to API Services.")
			return nil, false
		end
		task.wait(2)
	end
	return nil, false
end

local function saveData(player)
	local data = playerData[player]
	if not data or not data.canSave then
		return
	end
	-- Saved by tier NAME so reordering the tier list never breaks old saves.
	local saved = {
		current = Tiers[data.currentId].name,
		currentScale = data.currentScale,
		best = Tiers[data.bestId].name,
		bestScale = data.bestScale,
		rolls = data.rolls,
		discovered = data.discovered,
		essence = data.essence,
	}
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, saved)
	end)
	if not ok then
		warn(("[RollServer] Save failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

---------------------------------------------------------------------
-- LEADERBOARD + ATTRIBUTES (what other scripts/players can see)
---------------------------------------------------------------------
local function setupLeaderstats(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local height = Instance.new("StringValue")
	height.Name = "Height"
	height.Parent = leaderstats

	local best = Instance.new("StringValue")
	best.Name = "Best"
	best.Parent = leaderstats

	local rolls = Instance.new("IntValue")
	rolls.Name = "Rolls"
	rolls.Parent = leaderstats

	leaderstats.Parent = player
end

---------------------------------------------------------------------
-- LIVE BOARD: best height of the top 3 players in this server
-- (Workspace.Lobby.TopRollsBoard, built in Studio)
---------------------------------------------------------------------
local function escapeRichText(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function getBoardRows()
	local lobby = workspace:FindFirstChild("Lobby")
	local board = lobby and lobby:FindFirstChild("TopRollsBoard")
	local display = board and board:FindFirstChild("Display", true)
	if not display then
		return nil
	end
	local rows = {}
	for i = 1, 3 do
		rows[i] = display:FindFirstChild("Row" .. i, true)
		if not rows[i] then
			return nil
		end
	end
	return rows
end

local function updateBoard()
	local rows = getBoardRows()
	if not rows then
		return -- no board in this place; nothing to update
	end
	local entries = {}
	for player, data in pairs(playerData) do
		if player.Parent then
			table.insert(entries, { name = player.DisplayName, id = data.bestId, scale = data.bestScale })
		end
	end
	table.sort(entries, function(a, b)
		return RarityTable.IsBetter(a.id, a.scale, b.id, b.scale)
	end)
	for i, row in ipairs(rows) do
		local entry = entries[i]
		if entry then
			local tier = Tiers[entry.id]
			row.Text = ('%d.  %s   <font color="#%s">%s</font>   %s'):format(
				i,
				escapeRichText(entry.name),
				tier.color:ToHex(),
				tier.name:upper(),
				RarityTable.FormatScale(entry.scale)
			)
		else
			row.Text = i .. ".  ---"
		end
	end
end

local function refreshStats(player)
	local data = playerData[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if not data or not leaderstats then
		return
	end
	leaderstats.Height.Value = Tiers[data.currentId].name
	leaderstats.Best.Value = Tiers[data.bestId].name
	leaderstats.Rolls.Value = data.rolls

	-- The client reads these to update its on-screen labels and camera.
	player:SetAttribute("HeightTier", data.currentId)
	player:SetAttribute("HeightScale", data.currentScale)
	player:SetAttribute("BestTier", data.bestId)
	player:SetAttribute("BestScale", data.bestScale)
	player:SetAttribute("Discovered", HttpService:JSONEncode(data.discovered)) -- for the Index UI
	player:SetAttribute("Essence", data.essence)

	updateBoard()
end

---------------------------------------------------------------------
-- AURAS: the visual effect around a character
---------------------------------------------------------------------
local AURA_NAME = "HeightAura"
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"

local function clearAura(character)
	for _, obj in ipairs(character:GetDescendants()) do
		if obj.Name == AURA_NAME then
			obj:Destroy()
		end
	end
end

local function addEmitter(root, texture, color, scale, rate, upward)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = AURA_NAME
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Speed = NumberRange.new(1 * scale, 3 * scale)
	emitter.SpreadAngle = Vector2.new(180, 180)
	if upward then
		emitter.Acceleration = Vector3.new(0, 6 * scale, 0)
	end
	emitter.Parent = root
end

local function addGlow(character, root, color, scale)
	local highlight = Instance.new("Highlight")
	highlight.Name = AURA_NAME
	highlight.FillColor = color
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.Adornee = character
	highlight.Parent = character

	local light = Instance.new("PointLight")
	light.Name = AURA_NAME
	light.Color = color
	light.Brightness = 3
	light.Range = math.clamp(8 * scale, 4, 60)
	light.Parent = root
end

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function addNebula(root, scale)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = AURA_NAME
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(90, 20, 140), Color3.fromRGB(10, 10, 40))
	emitter.LightEmission = 0.4
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.Rate = 12
	emitter.Lifetime = NumberRange.new(3, 5)
	emitter.Size = NumberSequence.new(1.5 * scale, 4 * scale)
	emitter.Speed = NumberRange.new(0.3 * scale, 1 * scale)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-20, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = root
end

local function applyAura(character, tier, scale)
	clearAura(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or tier.aura == "None" then
		return
	end
	if tier.aura == "Sparkles" then
		addEmitter(root, SPARKLE_TEXTURE, tier.color, scale, 10, false)
	elseif tier.aura == "Glow" then
		addGlow(character, root, tier.color, scale)
		addEmitter(root, SPARKLE_TEXTURE, tier.color, scale, 15, false)
	elseif tier.aura == "Flames" then
		addGlow(character, root, tier.color, scale)
		addEmitter(root, FIRE_TEXTURE, tier.color, scale, 30, true)
	elseif tier.aura == "Starry" then
		addGlow(character, root, tier.color, scale)
		addEmitter(root, SPARKLE_TEXTURE, Color3.fromRGB(255, 245, 200), scale * 1.2, 35, false) -- twinkling stars
		addEmitter(root, FIRE_TEXTURE, tier.color, scale, 20, true)
	elseif tier.aura == "Cosmic" then
		addGlow(character, root, tier.color, scale)
		addEmitter(root, FIRE_TEXTURE, tier.color, scale, 25, true)
		addEmitter(root, SPARKLE_TEXTURE, Color3.new(1, 1, 1), scale * 1.5, 40, false)
	elseif tier.aura == "Nebula" then
		addGlow(character, root, tier.color, scale)
		addNebula(root, scale) -- dark cosmic clouds
		addEmitter(root, SPARKLE_TEXTURE, Color3.new(1, 1, 1), scale * 1.5, 40, false)
	end
end

---------------------------------------------------------------------
-- RESIZING THE CHARACTER
---------------------------------------------------------------------
local function applyHeight(player)
	local data = playerData[player]
	local character = player.Character
	if not data or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local scale = data.currentScale
	local tier = Tiers[data.currentId]

	-- Remember the character's normal hip height the first time we see it.
	if character:GetAttribute("BaseHipHeight") == nil then
		character:SetAttribute("BaseHipHeight", humanoid.HipHeight / character:GetScale())
	end

	clearAura(character) -- don't let ScaleTo stretch the old effects

	-- Where are the feet now? We keep them planted after resizing,
	-- otherwise a titan would spawn with its legs through the floor.
	local boxCFrame, boxSize = character:GetBoundingBox()
	local feetY = boxCFrame.Position.Y - boxSize.Y / 2

	character:ScaleTo(scale) -- Roblox's built-in "resize the whole model"

	humanoid.HipHeight = character:GetAttribute("BaseHipHeight") * scale
	humanoid.WalkSpeed = BASE_WALKSPEED * math.sqrt(scale) -- big = faster, but not 200x faster
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = BASE_JUMP_HEIGHT * scale ^ 0.75

	local newCFrame, newSize = character:GetBoundingBox()
	local newFeetY = newCFrame.Position.Y - newSize.Y / 2
	character:PivotTo(character:GetPivot() + Vector3.new(0, feetY - newFeetY + 0.05 * scale, 0))

	applyAura(character, tier, scale)
end

local VIP_TAG_NAME = "VIPTag"

local function updateVipTag(player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild(VIP_TAG_NAME)
	if old then
		old:Destroy()
	end
	if not player:GetAttribute("VIP") then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Name = VIP_TAG_NAME
	tag.Size = UDim2.new(0, 90, 0, 32)
	tag.ExtentsOffsetWorldSpace = Vector3.new(0, 1.5, 0) -- in head-sizes, so it rises with giants
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "VIP"
	label.TextColor3 = Color3.fromRGB(255, 215, 0)
	local outline = Instance.new("UIStroke")
	outline.Thickness = 2
	outline.Parent = label
	label.Parent = tag
	tag.Parent = head
end

local function onCharacterAdded(player, character)
	character:WaitForChild("Humanoid")
	-- Wait (max 5s) for hats/hair to load so they get resized too.
	local waited = 0
	while not player:HasAppearanceLoaded() and waited < 5 do
		waited += task.wait(0.1)
	end
	task.wait(0.1)
	if character.Parent then
		applyHeight(player)
		updateVipTag(player)
	end
end

---------------------------------------------------------------------
-- GIANT ANIMATION FIX (server copy; RollClient explains the bug)
-- The server poses every character from its animations too. Without this,
-- the server sees a 200x body thousands of studs underground, so touches
-- (altars, orbs) and anything else using body positions break for giants.
---------------------------------------------------------------------
local ANIM_FIX_MIN_SCALE = 2
local motorCache = setmetatable({}, { __mode = "k" }) -- [character] = its Motor6Ds

local function motorsOf(character)
	local motors = motorCache[character]
	if not motors then
		motors = {}
		for _, obj in ipairs(character:GetDescendants()) do
			if obj:IsA("Motor6D") then
				table.insert(motors, obj)
			end
		end
		character.DescendantAdded:Connect(function(obj)
			if obj:IsA("Motor6D") then
				table.insert(motors, obj)
			end
		end)
		motorCache[character] = motors
	end
	return motors
end

RunService.PreSimulation:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:GetScale() >= ANIM_FIX_MIN_SCALE then
			for _, motor in ipairs(motorsOf(character)) do
				local transform = motor.Transform
				if transform.Position.Magnitude > 0 then
					motor.Transform = transform.Rotation
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- ROLLING
---------------------------------------------------------------------
local function hasPass(player, key)
	local fx = effects[player]
	return fx ~= nil and fx.passes[key] == true
end

local function pct(x)
	return math.floor(x * 100 + 0.5)
end

local function rollsLeft(n)
	return n == 1 and "1 roll" or (n .. " rolls")
end

-- Total luck = (all +% bonuses added up) x (all multipliers), capped at MAX_LUCK.
-- Also returns a list of what's active, for the luck badge.
local function computeLuck(player)
	local fx = effects[player]
	local now = os.clock()
	local parts = {}
	local add = player:GetAttribute("Luck") or 1 -- hook for luck potions etc.
	local function bonus(amount, text)
		if amount > 0 then
			add += amount
			table.insert(parts, text)
		end
	end
	local friend = player:GetAttribute("FriendBoost") or 0
	bonus(friend, ("Friend Boost +%d%%"):format(pct(friend)))
	local group = player:GetAttribute("GroupBoost") or 0
	bonus(group, ("Group Member +%d%%"):format(pct(group)))

	local mult = 1
	if fx then
		if fx.passes.VIP then
			bonus(VIP_BOOST, ("VIP +%d%%"):format(pct(VIP_BOOST)))
		end
		if fx.sky then
			bonus(SKY_BLESSING, ("Sky Blessing +%d%%"):format(pct(SKY_BLESSING)))
		end
		if now < fx.wheelLuckUntil then
			bonus(WHEEL_LUCK_BOOST, ("Wheel +%d%% (%ds)"):format(pct(WHEEL_LUCK_BOOST), math.ceil(fx.wheelLuckUntil - now)))
		end
		if fx.surgeRolls > 0 then
			bonus(SURGE_BOOST, ("Super Surge +%d%% (%s)"):format(pct(SURGE_BOOST), rollsLeft(fx.surgeRolls)))
		end
		if fx.passes.Luck2x then
			mult *= 2
			table.insert(parts, "2x Luck Pass")
		end
		if now < fx.orbUntil then
			mult *= ORB_LUCK_MULT
			table.insert(parts, ("Orb Surge x%s (%ds)"):format(tostring(ORB_LUCK_MULT), math.ceil(fx.orbUntil - now)))
		end
		if fx.jackpotRolls > 0 then
			mult *= JACKPOT_MULT
			table.insert(parts, ("JACKPOT x%d (%s)"):format(JACKPOT_MULT, rollsLeft(fx.jackpotRolls)))
		end
	end

	local total = add * mult
	if total > MAX_LUCK then
		total = MAX_LUCK
		table.insert(parts, ("capped at %dx"):format(MAX_LUCK))
	end
	return total, parts
end

local function getLuck(player)
	return (computeLuck(player))
end

-- The client's luck badge reads this attribute.
local function refreshLuckInfo(player)
	local total, parts = computeLuck(player)
	local info = HttpService:JSONEncode({ total = total, parts = parts })
	if player:GetAttribute("LuckInfo") ~= info then
		player:SetAttribute("LuckInfo", info)
	end
end

---------------------------------------------------------------------
-- SOCIAL LUCK: +10% per Roblox friend in the same server (max +50%)
---------------------------------------------------------------------
local friendCache = {} -- ["lowId:highId"] = true/false, friendship never re-checked per server

local function areFriends(a, b)
	if a.UserId <= 0 or b.UserId <= 0 then
		return false -- Studio test players have fake ids
	end
	local key = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	if friendCache[key] == nil then
		local ok, result = pcall(a.IsFriendsWith, a, b.UserId)
		if not ok then
			return false -- web call failed; don't cache so it's retried next time
		end
		friendCache[key] = result
	end
	return friendCache[key]
end

local function refreshFriendBoost(player, leaving)
	local count = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other ~= leaving and areFriends(player, other) then
			count += 1
		end
	end
	if player.Parent then
		player:SetAttribute("FriendsInServer", count)
		player:SetAttribute("FriendBoost", math.min(count * FRIEND_BOOST_PER_FRIEND, FRIEND_BOOST_MAX))
	end
end

local function refreshAllFriendBoosts(leaving)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= leaving then
			task.spawn(refreshFriendBoost, player, leaving)
		end
	end
end

---------------------------------------------------------------------
-- GROUP PERK: flat +15% luck for members of GROUP_ID
---------------------------------------------------------------------
local function refreshGroupBoost(player)
	local ok, inGroup = pcall(player.IsInGroup, player, GROUP_ID)
	if not ok then
		warn(("[RollServer] Group check failed for %s: %s"):format(player.Name, tostring(inGroup)))
	end
	if player.Parent then
		player:SetAttribute("GroupBoost", (ok and inGroup) and GROUP_BOOST or 0)
	end
end

local function tryStartCooldown(player)
	local now = os.clock()
	local cooldown = hasPass(player, "FastRoll") and FAST_ROLL_COOLDOWN or ROLL_COOLDOWN
	if lastRollTime[player] and now - lastRollTime[player] < cooldown then
		return false
	end
	lastRollTime[player] = now
	return true
end

-- Common rolls aren't wasted: they give Growth Essence (rarer common = more).
local function essenceFor(tierId)
	local rarity = RarityTable.Rarity(tierId)
	if rarity >= ESSENCE_MAX_ONE_IN then
		return 0
	elseif rarity >= 30 then
		return 3
	elseif rarity >= 10 then
		return 2
	end
	return 1
end

-- opts.ignoreCooldown: free/pity rolls skip the cooldown
-- opts.minOneIn: only land on tiers at least this rare (Titan Pity Roll)
local function doRoll(player, forcedTierId, opts)
	opts = opts or {}
	local data, fx = playerData[player], effects[player]
	if not data or not fx then
		return
	end
	if opts.ignoreCooldown then
		lastRollTime[player] = os.clock()
	elseif not tryStartCooldown(player) then
		return
	end

	local tierId, scale
	if forcedTierId then
		tierId, scale = forcedTierId, RarityTable.ScaleFor(forcedTierId, rng)
	elseif opts.minOneIn then
		tierId, scale = RarityTable.RollAtLeast(opts.minOneIn, rng)
	else
		tierId, scale = RarityTable.Roll(getLuck(player), rng)
		-- per-roll boosts are used up by normal rolls only
		if fx.surgeRolls > 0 then
			fx.surgeRolls -= 1
		end
		if fx.jackpotRolls > 0 then
			fx.jackpotRolls -= 1
		end
	end
	local tier = Tiers[tierId]
	local essence = essenceFor(tierId)
	data.essence += essence

	local isNewBest = RarityTable.IsBetter(tierId, scale, data.bestId, data.bestScale)
	data.rolls += 1
	data.currentId, data.currentScale = tierId, scale
	markDiscovered(data, tierId, scale)
	if isNewBest then
		data.bestId, data.bestScale = tierId, scale
	end

	-- Tell the roller right away so their spin animation can start...
	local spinTime = hasPass(player, "FastRoll") and FAST_SPIN_TIME or SPIN_TIME
	rollResult:FireClient(player, tierId, scale, isNewBest, spinTime, essence)

	-- ...and only change the body when the spin finishes, for the big reveal.
	task.delay(spinTime, function()
		if not player.Parent then
			return
		end
		applyHeight(player)
		refreshStats(player)
		refreshLuckInfo(player)
		if tier.announce then
			announce:FireAllClients(player.DisplayName, tierId, scale)
		end
	end)
end

-- Free rolls are played one after another, each after the previous spin ends.
local function queueBonusRolls(player, count)
	local fx = effects[player]
	if not fx then
		return
	end
	fx.bonusRolls += count
	if fx.bonusRunning then
		return
	end
	fx.bonusRunning = true
	task.spawn(function()
		while fx.bonusRolls > 0 and player.Parent do
			local waitFor = (lastRollTime[player] or 0) + SPIN_TIME + 0.6 - os.clock()
			if waitFor > 0 then
				task.wait(waitFor)
			end
			if not player.Parent then
				break
			end
			fx.bonusRolls -= 1
			doRoll(player, nil, { ignoreCooldown = true })
		end
		fx.bonusRunning = false
	end)
end

rollRequest.OnServerEvent:Connect(function(player)
	doRoll(player, nil)
end)

equipBest.OnServerEvent:Connect(function(player)
	local data = playerData[player]
	if not data or not tryStartCooldown(player) then
		return
	end
	data.currentId, data.currentScale = data.bestId, data.bestScale
	applyHeight(player)
	refreshStats(player)
end)

equipTier.OnServerEvent:Connect(function(player, tierId)
	local data = playerData[player]
	if not data or typeof(tierId) ~= "number" or not Tiers[tierId] then
		return
	end
	local scale = data.discovered[Tiers[tierId].name]
	if not scale or not tryStartCooldown(player) then
		return -- only tiers you've actually rolled
	end
	data.currentId, data.currentScale = tierId, scale
	applyHeight(player)
	refreshStats(player)
end)

-- Studio-only: lets the test panel force any tier. Ignored in the live game.
devForceRoll.OnServerEvent:Connect(function(player, tierId)
	if not RunService:IsStudio() then
		return
	end
	if typeof(tierId) == "number" and Tiers[tierId] then
		lastRollTime[player] = nil
		doRoll(player, tierId)
	end
end)

---------------------------------------------------------------------
-- MESSAGES (the toast at the top of the screen)
---------------------------------------------------------------------
local GOLD = Color3.fromRGB(255, 215, 0)
local SKY_BLUE = Color3.fromRGB(150, 220, 255)
local GREY = Color3.fromRGB(190, 190, 205)

local function tell(player, text, color)
	notify:FireClient(player, text, color or Color3.new(1, 1, 1))
end

local function playerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

---------------------------------------------------------------------
-- SKY REALM: altars (tag "SkyAltar") and orbs (tag "SkyOrb")
---------------------------------------------------------------------
local function connectAltar(altar)
	altar.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local fx = player and effects[player]
		if fx and not fx.sky then
			fx.sky = true
			refreshLuckInfo(player)
			tell(player, "SKY BLESSING!  +25% Luck while you stay in the clouds", SKY_BLUE)
		end
	end)
end

local function setOrbVisible(orb, visible)
	orb.Transparency = visible and 0 or 1
	for _, obj in ipairs(orb:GetDescendants()) do
		if obj:IsA("Light") or obj:IsA("ParticleEmitter") or obj:IsA("BillboardGui") then
			obj.Enabled = visible
		end
	end
end

local function connectOrb(orb)
	orb.Touched:Connect(function(hit)
		if orb:GetAttribute("Cooling") then
			return
		end
		local player = playerFromHit(hit)
		local fx = player and effects[player]
		if not fx then
			return
		end
		orb:SetAttribute("Cooling", true)
		setOrbVisible(orb, false)
		if rng:NextNumber() < 0.5 then
			queueBonusRolls(player, 1)
			tell(player, "SKY ORB!  Free roll", GOLD)
		else
			fx.orbUntil = os.clock() + ORB_SURGE_TIME
			refreshLuckInfo(player)
			tell(player, ("SKY ORB!  %sx Luck for %d seconds"):format(tostring(ORB_LUCK_MULT), ORB_SURGE_TIME), GOLD)
		end
		task.delay(ORB_RESPAWN, function()
			orb:SetAttribute("Cooling", nil)
			setOrbVisible(orb, true)
		end)
	end)
end

for _, altar in ipairs(CollectionService:GetTagged("SkyAltar")) do
	connectAltar(altar)
end
CollectionService:GetInstanceAddedSignal("SkyAltar"):Connect(connectAltar)
for _, orb in ipairs(CollectionService:GetTagged("SkyOrb")) do
	connectOrb(orb)
end
CollectionService:GetInstanceAddedSignal("SkyOrb"):Connect(connectOrb)

-- Is there a cloud directly under this character?
local skyRealm = workspace:FindFirstChild("MapSafety") and workspace.MapSafety:FindFirstChild("SkyRealm")
local cloudRay = RaycastParams.new()
cloudRay.FilterType = Enum.RaycastFilterType.Include
cloudRay.FilterDescendantsInstances = { skyRealm }

local function isOverClouds(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid and skyRealm) or humanoid.Health <= 0 then
		return false
	end
	return workspace:Raycast(root.Position, Vector3.new(0, -(root.Position.Y + 10), 0), cloudRay) ~= nil
end

-- Twice a second: end Sky Blessings for anyone who left the clouds, and
-- refresh everyone's luck badge (timers count down).
task.spawn(function()
	while true do
		task.wait(0.5)
		for player, fx in pairs(effects) do
			if fx.sky then
				if not isOverClouds(player.Character) then
					fx.sky = false
					tell(player, "Your Sky Blessing faded: you left the clouds.", GREY)
				end
			end
			if player.Parent then
				refreshLuckInfo(player)
			end
		end
	end
end)

---------------------------------------------------------------------
-- GAMBLER'S WHEEL (Workspace.Lobby.GamblersWheel, built in Studio)
---------------------------------------------------------------------
local WHEEL_TILES = 100
local HUB_TILT = CFrame.Angles(0, math.rad(90), 0) -- the hub is a cylinder, which spins around its X axis
local lobby = workspace:FindFirstChild("Lobby")
local wheelModel = lobby and lobby:FindFirstChild("GamblersWheel")
local wheelHub = wheelModel and wheelModel:FindFirstChild("Hub")
local wheelBase = wheelModel and wheelModel:GetAttribute("BaseCFrame")
local wheelAngle = Instance.new("NumberValue")
local wheelTween = nil
if wheelHub and wheelBase then
	wheelAngle.Changed:Connect(function(angle)
		wheelHub.CFrame = wheelBase * CFrame.Angles(0, 0, angle) * HUB_TILT
	end)
end

-- Spin the physical wheel so it stops on a tile of the winning segment.
local function spinWheelModel(segmentIndex)
	if not (wheelHub and wheelBase) then
		return
	end
	local first = 1
	for i = 1, segmentIndex - 1 do
		first += WHEEL[i].weight
	end
	local tile = first + rng:NextInteger(0, WHEEL[segmentIndex].weight - 1)
	local tileAngle = (tile - 0.5) / WHEEL_TILES * 2 * math.pi
	local current = wheelAngle.Value
	local target = current - ((current + tileAngle) % (2 * math.pi)) - 8 * math.pi -- 4 full turns, then land
	if wheelTween then
		wheelTween:Cancel()
	end
	wheelTween = TweenService:Create(wheelAngle, TweenInfo.new(WHEEL_SPIN_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = target })
	wheelTween:Play()
end

local function pickWheelSegment()
	local r = rng:NextNumber() * 100
	for i, segment in ipairs(WHEEL) do
		r -= segment.weight
		if r < 0 then
			return i
		end
	end
	return 1
end

local function giveWheelPrize(player, key)
	local fx = effects[player]
	if key == "Luck15" then
		fx.wheelLuckUntil = os.clock() + WHEEL_LUCK_TIME
	elseif key == "FreeRolls" then
		queueBonusRolls(player, 3)
	elseif key == "SuperSurge" then
		fx.surgeRolls += 3
	elseif key == "TitanPity" then
		doRoll(player, nil, { ignoreCooldown = true, minOneIn = 500 })
	elseif key == "Jackpot" then
		fx.jackpotRolls += 5
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				tell(other, player.DisplayName .. " hit the JACKPOT on the Gambler's Wheel!", GOLD)
			end
		end
	end
	refreshLuckInfo(player)
end

local function spinWheelFor(player)
	local data, fx = playerData[player], effects[player]
	if not data or not fx or fx.wheelBusy then
		return
	end
	if data.essence < ESSENCE_PER_SPIN then
		tell(player, ("Need %d Growth Essence to spin (you have %d). Common rolls give Essence!"):format(ESSENCE_PER_SPIN, data.essence), GREY)
		return
	end
	data.essence -= ESSENCE_PER_SPIN
	player:SetAttribute("Essence", data.essence)
	fx.wheelBusy = true
	local index = pickWheelSegment()
	spinWheelModel(index)
	tell(player, "The Gambler's Wheel is spinning...", Color3.fromRGB(200, 150, 255))
	task.delay(WHEEL_SPIN_TIME, function()
		fx.wheelBusy = false
		if player.Parent and effects[player] then
			giveWheelPrize(player, WHEEL[index].key)
			tell(player, WHEEL[index].label, WHEEL[index].color)
		end
	end)
end

spinWheel.OnServerEvent:Connect(spinWheelFor)
local wheelPrompt = wheelHub and wheelHub:FindFirstChildOfClass("ProximityPrompt")
if wheelPrompt then
	wheelPrompt.Triggered:Connect(spinWheelFor)
end

---------------------------------------------------------------------
-- GAMEPASSES
---------------------------------------------------------------------
local function setPass(player, key, owned)
	local fx = effects[player]
	if not fx then
		return
	end
	fx.passes[key] = owned or nil
	player:SetAttribute("Pass_" .. key, owned)
	if key == "VIP" then
		player:SetAttribute("VIP", owned) -- clients use this for the [VIP] chat tag
		updateVipTag(player)
	end
	refreshLuckInfo(player)
end

local function loadPasses(player)
	for key, pass in pairs(GAMEPASSES) do
		local owned = false
		if RunService:IsStudio() and STUDIO_PASSES[key] then
			owned = true
		elseif pass.id ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			owned = ok and result == true
		end
		setPass(player, key, owned)
	end
end

shopRequest.OnServerEvent:Connect(function(player, key)
	local pass = typeof(key) == "string" and GAMEPASSES[key]
	if not pass or not effects[player] then
		return
	end
	if RunService:IsStudio() then
		-- Studio testing: no Robux, the button just switches the pass on and off.
		setPass(player, key, not hasPass(player, key))
		tell(player, ("[Studio test] %s is now %s"):format(pass.name, hasPass(player, key) and "ON" or "OFF"))
	elseif hasPass(player, key) then
		return
	elseif pass.id == 0 then
		tell(player, pass.name .. " isn't on sale yet.", GREY)
	else
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then
		return
	end
	for key, pass in pairs(GAMEPASSES) do
		if pass.id ~= 0 and pass.id == passId then
			setPass(player, key, true)
			tell(player, "Thanks! " .. pass.name .. " is now active.", GOLD)
		end
	end
end)

---------------------------------------------------------------------
-- JOIN / LEAVE
---------------------------------------------------------------------
local function onPlayerAdded(player)
	effects[player] = newEffects()
	setupLeaderstats(player)
	player:SetAttribute("FriendBoost", 0)
	player:SetAttribute("FriendsInServer", 0)
	refreshAllFriendBoosts() -- everyone re-checks: the newcomer may be someone's friend
	player:SetAttribute("GroupBoost", 0)
	task.spawn(refreshGroupBoost, player)

	local data = defaultData()
	local saved, loadedOk = loadData(player)
	data.canSave = loadedOk -- if loading failed, never save (protects old data)
	if type(saved) == "table" then
		local best = RarityTable.ByName[saved.best]
		local current = RarityTable.ByName[saved.current]
		if best then
			data.bestId, data.bestScale = best.id, saved.bestScale or best.scale
		end
		if current then
			data.currentId, data.currentScale = current.id, saved.currentScale or current.scale
		end
		data.rolls = saved.rolls or 0
		data.essence = tonumber(saved.essence) or 0
		if type(saved.discovered) == "table" then
			for name, scale in pairs(saved.discovered) do
				if RarityTable.ByName[name] and type(scale) == "number" then
					data.discovered[name] = scale
				end
			end
		end
	end
	-- Saves from before the Index existed: count what they're wearing as discovered.
	markDiscovered(data, data.bestId, data.bestScale)
	markDiscovered(data, data.currentId, data.currentScale)
	if not player.Parent then
		return -- left while we were loading
	end
	playerData[player] = data
	refreshStats(player)
	task.spawn(loadPasses, player)
	refreshLuckInfo(player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	refreshAllFriendBoosts(player)
	saveData(player)
	playerData[player] = nil
	lastRollTime[player] = nil
	effects[player] = nil
	updateBoard()
end)

game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function()
			saveData(player)
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait(0.1)
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, player)
		end
	end
end)
