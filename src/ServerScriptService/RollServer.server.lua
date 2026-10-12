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
local WALKSPEED_EXPONENT = 0.45 -- WalkSpeed = 16 x scale^0.45, between 16 and MAX_WALKSPEED
local MAX_WALKSPEED = 120
local BASE_JUMP_HEIGHT = 7.2
local FRIEND_BOOST_PER_FRIEND = 0.10 -- +10% luck per Roblox friend in the same server
local FRIEND_BOOST_MAX = 0.50 -- capped at +50%
local GROUP_ID = 5353332 -- placeholder: set this to your group's id
local GROUP_BOOST = 0.15 -- flat +15% luck for group members, stacks with friend boost
local MAX_LUCK = 25 -- all boosts together are capped here; RarityTable stays balanced up to ~25x

-- Rags to Riches: Growth Essence from common rolls, spent on the Growth Spinner
local ESSENCE_MAX_ONE_IN = 100 -- only rolls more common than 1 in 100 give Essence (1-3, rarer = more)
local ESSENCE_PER_SPIN = 50
local WHEEL_SPIN_TIME = 4 -- seconds the spinner spins before the prize
local WHEEL_LUCK_BOOST = 0.15
local WHEEL_LUCK_TIME = 60
local FAST_ROLL_PRIZE = 5 -- "5 Instant Fast Rolls"
local SKY_JUMP_MULT = 3 -- Sky Jump: jump height x3...
local SKY_JUMP_TIME = 120 -- ...for this many seconds
local OVERCHARGE_BOOST = 1.0 -- Growth Overcharge: +100% luck...
local OVERCHARGE_ROLLS = 5 -- ...for this many rolls
local TITAN_SURGE_MIN_ONE_IN = 250 -- Titan Surge: guaranteed 1 in 250 or rarer
local GODSPEED_MULT = 10 -- Godspeed: 10x luck...
local GODSPEED_ROLLS = 3 -- ...for this many rolls
local WHEEL = { -- weights must add up to 100: the physical spinner has 100 rim tiles, in this order
	{ key = "Luck15", rarity = "Common", weight = 40, label = "+15% Luck for 60 seconds", color = Color3.fromRGB(112, 128, 144) },
	{ key = "FastRolls", rarity = "Uncommon", weight = 27, label = "5 Instant Fast Rolls!", color = Color3.fromRGB(120, 210, 70) },
	{ key = "SkyJump", rarity = "Rare", weight = 16, label = "SKY JUMP!  3x jump height for 2 minutes", color = Color3.fromRGB(110, 190, 240) },
	{ key = "Overcharge", rarity = "Epic", weight = 10, label = "GROWTH OVERCHARGE!  +100% Luck for 5 rolls", color = Color3.fromRGB(155, 100, 210) },
	{ key = "TitanSurge", rarity = "Legendary", weight = 5, label = "TITAN SURGE!  Guaranteed 1 in 250 or rarer", color = Color3.fromRGB(250, 175, 70) },
	{ key = "Godspeed", rarity = "Mythic", weight = 2, label = "GODSPEED!!  10x Luck for your next 3 rolls", color = Color3.fromRGB(255, 130, 210) },
}

-- Crush Pit (Workspace.Lobby.CrushPit): giants bounce small players, both earn Essence
local PIT_SMALL_MAX_SCALE = 2 -- players this size or smaller get bounced...
local PIT_GIANT_MIN_SCALE = 10 -- ...by the feet of players this size or bigger
local PIT_BOUNCE_UP = 90
local PIT_BOUNCE_OUT = 70
local PIT_BOUNCE_COOLDOWN = 1.5 -- seconds before the same player can be bounced again
local PIT_ESSENCE_BOUNCED = 3 -- for the small player
local PIT_ESSENCE_STOMPER = 2 -- for the giant
local PIT_PARTICIPATION_ESSENCE = 1 -- everyone in the pit, every 10s while giants and small players share it

-- Wind Launchers (tag "WindLauncher", attributes Target + FlightTime): fling normal-sized players
local LAUNCH_MAX_SCALE = 2.5
local LAUNCH_COOLDOWN = 3

-- Updraft Void Catcher: a non-giant who falls off a cloud gets caught by a
-- soft updraft below this height and set down at the spawn plaza
local CATCH_Y = 150
local CATCH_MAX_SCALE = 10 -- giants step down from the clouds on purpose
local CATCH_DROP = 15 -- only after falling this far below the cloud they left

-- Mist barriers (collision group "MistBarrier") ring the cloud edges. They
-- stop normal-sized players; characters this big walk through them.
local MIST_PASS_SCALE = 10

-- Titan's Throne (tag "ApexPedestal"): 50x+ players standing on it
local THRONE_MIN_SCALE = 50
local THRONE_LUCK = 0.5 -- +50% for the titan on the throne
local FAVOR_LUCK = 0.10 -- +10% "Titan's Favor" for everyone else while the throne is taken

-- Ground Shaker Stomp (F key)
local STOMP_MIN_SCALE = 50
local STOMP_COOLDOWN = 10
local STOMP_RADIUS = 4 -- x the stomper's scale, in studs
local STOMP_POP = 45 -- upward launch speed for popped players
local STOMP_SIZE_RATIO = 0.1 -- only players at most a tenth of the stomper's size get popped

-- Sky Realm (cloud layers, altars and orbs are built in Studio and found by tag)
local SKY_BLESSING = 0.25 -- +25% luck after touching a Sky Altar, while you stand over a cloud
local ORB_RESPAWN = 90 -- seconds before a collected Sky Orb comes back
local ORB_SURGE_TIME = 60
local ORB_LUCK_MULT = 1.5

-- Gamepasses: put your real gamepass ids here (0 = not on sale yet)
local GAMEPASSES = {
	AutoRoll = { id = 0, name = "Auto Roll" },
	Luck2x = { id = 0, name = "2x Luck" },
	FastRoll = { id = 0, name = "Fast Roll" },
	VIP = { id = 0, name = "VIP Rank" },
}
local DEBUG_UNLOCK_PASSES = true -- Studio playtests only: every pass starts unlocked. Never applies in the live game.
local VIP_BOOST = 0.25
local FAST_ROLL_COOLDOWN = 0.7 -- Fast Roll: a roll every ~0.75s (normal: 1.3s)
local FAST_SPIN_TIME = 0.55 -- still a full (short) spin, nothing skipped

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
local spinWheel = newRemote("SpinWheel") -- client -> server: "spin the Growth Spinner"
local shopRequest = newRemote("ShopRequest") -- client -> server: "buy this pass" (Studio: toggle it)
local notify = newRemote("Notify") -- server -> one client: a short message for the toast
local bounce = newRemote("Bounce") -- server -> one client: "fly with this velocity" (pit, stomp, launchers)
local stomp = newRemote("Stomp") -- client -> server: "I pressed F"
local stompFx = newRemote("StompFx") -- server -> everyone: "a giant stomped here" (boom + shockwave)
local saveSettings = newRemote("SaveSettings") -- client -> server: music / sfx / low gfx choices
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
local throneTaken = false -- someone 50x+ is on the Titan's Throne (see TITAN'S THRONE)

local function defaultData()
	return {
		currentId = RarityTable.FallbackId,
		currentScale = 1,
		bestId = RarityTable.FallbackId,
		bestScale = 1,
		rolls = 0,
		essence = 0, -- Growth Essence: earned from common rolls, spent on the wheel
		settings = { music = true, sfx = true, lowGfx = false }, -- the player's SETTINGS choices
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
		skyJumpUntil = 0, -- os.clock() when Sky Jump ends
		overchargeRolls = 0, -- rolls left with Growth Overcharge
		godspeedRolls = 0, -- rolls left with Godspeed
		bonusQueue = {}, -- free rolls waiting to be played (true = fast roll)
		bonusRunning = false,
		lastSpinTime = 0, -- spin length of the last roll, so free rolls wait for it
		throne = false, -- standing on the Titan's Throne
		lastStomp = 0,
		lastLaunch = 0,
		wheelBusy = false,
		cloudFeetY = nil, -- feet height on the last cloud stood on (Void Catcher), nil = on the ground
		catching = false,
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
		settings = data.settings,
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
local ELECTRIC_CYAN = Color3.fromRGB(70, 225, 255)
local RADIANT_GOLD = Color3.fromRGB(255, 205, 60)
local COSMIC_VIOLET = Color3.fromRGB(130, 50, 255)
local OBSIDIAN = Color3.fromRGB(25, 10, 40)

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

local function addMotes(root, color, scale)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = AURA_NAME
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.2
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Rate = 3
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Size = NumberSequence.new(0.3 * scale, 0)
	emitter.Speed = NumberRange.new(0.5 * scale, 1 * scale)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = root
end

local function addLight(root, color, scale)
	local light = Instance.new("PointLight")
	light.Name = AURA_NAME
	light.Color = color
	light.Brightness = 1.5
	light.Range = math.clamp(6 * scale, 4, 60)
	light.Parent = root
end

-- Highlight around 10x+ characters. Each client slowly pulses the outline
-- between the OutlineA and OutlineB colors.
local function addOutline(character, fillColor, outlineA, outlineB)
	local highlight = Instance.new("Highlight")
	highlight.Name = AURA_NAME
	highlight.FillColor = fillColor
	highlight.FillTransparency = 0.85
	highlight.OutlineColor = outlineA
	highlight.OutlineTransparency = 0.05
	highlight.Adornee = character
	highlight:SetAttribute("OutlineA", outlineA)
	highlight:SetAttribute("OutlineB", outlineB)
	highlight.Parent = character
end

-- Vertical flame / energy streaks shooting up out of the body: fast, narrow,
-- stretched along their direction of travel and tapering to nothing.
local function addStreaks(root, scale, color, tipColor, rate, glow)
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = AURA_NAME
	streaks.Texture = FIRE_TEXTURE
	streaks.Color = ColorSequence.new(color, tipColor)
	streaks.LightEmission = glow or 1
	streaks.LightInfluence = 0
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.Squash = NumberSequence.new(2.5) -- tall and thin
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	streaks.Lifetime = NumberRange.new(0.35, 0.6)
	streaks.Rate = rate
	streaks.Speed = NumberRange.new(9 * scale, 14 * scale)
	streaks.EmissionDirection = Enum.NormalId.Top
	streaks.SpreadAngle = Vector2.new(6, 6)
	streaks.Shape = Enum.ParticleEmitterShape.Box
	streaks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	streaks.Parent = root
end

-- Lightning arcs between the limbs. Every limb gets an attachment marked
-- "ArcPoint"; the beams start on hand-to-hand and torso-to-head, and each
-- client re-wires them to random limb pairs every 0.1s ("Crackle") and
-- re-bends them, so they jump around the body like electricity.
local ARC_LIMBS = {
	"LeftHand", "RightHand", "Head", "UpperTorso", "LowerTorso", "LeftFoot", "RightFoot", -- R15
	"Left Arm", "Right Arm", "Torso", "Left Leg", "Right Leg", -- R6
}

local function addArcs(character, root, scale, color, count)
	local points, all = {}, {}
	for _, limbName in ipairs(ARC_LIMBS) do
		local limb = character:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			local point = Instance.new("Attachment")
			point.Name = AURA_NAME
			point:SetAttribute("ArcPoint", true)
			point.Parent = limb
			points[limbName] = point
			table.insert(all, point)
		end
	end
	if #all < 2 then
		return
	end
	local starts = {
		{ points.LeftHand or points["Left Arm"], points.RightHand or points["Right Arm"] },
		{ points.UpperTorso or points.Torso, points.Head },
	}
	for i = 1, count do
		local from, to = starts[i] and starts[i][1], starts[i] and starts[i][2]
		if not (from and to) then
			from = all[rng:NextInteger(1, #all)]
			repeat
				to = all[rng:NextInteger(1, #all)]
			until to ~= from
		end
		local beam = Instance.new("Beam")
		beam.Name = AURA_NAME
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), -- white-hot middle
			ColorSequenceKeypoint.new(1, color),
		})
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 0.14 * scale
		beam.Width1 = 0.1 * scale
		beam.Texture = SPARKLE_TEXTURE -- crackling sparks running along the arc
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 0.8 * scale
		beam.TextureSpeed = 4
		beam.Segments = 16
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.05)
		beam:SetAttribute("Crackle", scale)
		beam.Parent = root
	end
end

-- Cosmic sparks shooting up off a god-tier body.
local function addCosmicSparks(root, scale)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = AURA_NAME
	sparks.Texture = SPARKLE_TEXTURE
	sparks.Color = ColorSequence.new(Color3.fromRGB(200, 150, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.4 * scale, 0)
	sparks.Lifetime = NumberRange.new(1, 1.5)
	sparks.Rate = 30
	sparks.Speed = NumberRange.new(4 * scale, 7 * scale)
	sparks.SpreadAngle = Vector2.new(10, 10)
	sparks.Parent = root
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
	elseif tier.aura == "Cosmic" then
		addGlow(character, root, tier.color, scale)
		addEmitter(root, FIRE_TEXTURE, tier.color, scale, 25, true)
		addEmitter(root, SPARKLE_TEXTURE, Color3.new(1, 1, 1), scale * 1.5, 40, false)
	elseif tier.aura == "Earth" then
		-- small / common tiers: a few drifting earth-tone motes
		addMotes(root, tier.color, scale)
	elseif tier.aura == "Ki" then
		-- anime ki: cyan/gold outline and vertical flame streaks
		addOutline(character, tier.color, ELECTRIC_CYAN, RADIANT_GOLD)
		addLight(root, tier.color, scale)
		addStreaks(root, scale, tier.color, Color3.new(1, 1, 1), 40)
		addStreaks(root, scale * 0.7, Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 120, 40), 25)
	elseif tier.aura == "Lightning" then
		-- energy streaks + limb-to-limb lightning (each client makes it crackle);
		-- the spinning ground glyph (50x+) is drawn by each client
		addOutline(character, tier.color, ELECTRIC_CYAN, RADIANT_GOLD)
		addLight(root, tier.color, scale)
		addStreaks(root, scale, Color3.fromRGB(150, 235, 255), Color3.new(1, 1, 1), 45)
		addArcs(character, root, scale, Color3.fromRGB(120, 210, 255), 5)
		addEmitter(root, SPARKLE_TEXTURE, tier.color, scale, 20, false)
	elseif tier.aura == "Super" then
		-- full super aura; the orbiting void, ground glyph and footstep shockwaves are drawn by each client
		addOutline(character, Color3.fromRGB(20, 8, 35), COSMIC_VIOLET, OBSIDIAN)
		addStreaks(root, scale, Color3.fromRGB(160, 80, 255), Color3.fromRGB(60, 0, 90), 55)
		addStreaks(root, scale * 1.3, Color3.fromRGB(40, 10, 70), Color3.fromRGB(0, 0, 0), 20, 0) -- dark void streaks
		addCosmicSparks(root, scale)
		addArcs(character, root, scale, Color3.fromRGB(150, 70, 255), 6)
		local pulse = Instance.new("PointLight")
		pulse.Name = AURA_NAME
		pulse.Color = Color3.fromRGB(150, 70, 255)
		pulse.Brightness = 3
		pulse.Range = 60
		pulse:SetAttribute("Pulse", true) -- each client pulses it
		pulse.Parent = root
	end
end

---------------------------------------------------------------------
-- RESIZING THE CHARACTER
---------------------------------------------------------------------
-- Mist barriers (collision group "MistBarrier") stop normal-sized players at
-- the cloud edges; characters MIST_PASS_SCALE+ are in "Giants" and walk through.
local PhysicsService = game:GetService("PhysicsService")
local MIST_GROUP, GIANT_GROUP = "MistBarrier", "Giants"
for _, groupName in ipairs({ MIST_GROUP, GIANT_GROUP }) do
	if not PhysicsService:IsCollisionGroupRegistered(groupName) then
		PhysicsService:RegisterCollisionGroup(groupName)
	end
end
PhysicsService:CollisionGroupSetCollidable(MIST_GROUP, GIANT_GROUP, false)

local function collisionGroupFor(character)
	return character:GetScale() >= MIST_PASS_SCALE and GIANT_GROUP or "Default"
end

local function setCharacterGroup(character)
	local group = collisionGroupFor(character)
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.CollisionGroup = group
		end
	end
end

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
	setCharacterGroup(character)

	humanoid.HipHeight = character:GetAttribute("BaseHipHeight") * scale
	humanoid.WalkSpeed = math.clamp(BASE_WALKSPEED * scale ^ WALKSPEED_EXPONENT, BASE_WALKSPEED, MAX_WALKSPEED)
	humanoid.UseJumpPower = false
	local fx = effects[player]
	local jumpBoost = (fx and os.clock() < fx.skyJumpUntil) and SKY_JUMP_MULT or 1
	humanoid.JumpHeight = BASE_JUMP_HEIGHT * scale ^ 0.75 * jumpBoost

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
	character.DescendantAdded:Connect(function(obj) -- hats etc. that load late
		if obj:IsA("BasePart") then
			obj.CollisionGroup = collisionGroupFor(character)
		end
	end)
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
		if fx.throne then
			bonus(THRONE_LUCK, ("Apex Luck +%d%%"):format(pct(THRONE_LUCK)))
		elseif throneTaken then
			bonus(FAVOR_LUCK, ("Titan's Favor +%d%%"):format(pct(FAVOR_LUCK)))
		end
		if fx.sky then
			bonus(SKY_BLESSING, ("Sky Blessing +%d%%"):format(pct(SKY_BLESSING)))
		end
		if now < fx.wheelLuckUntil then
			bonus(WHEEL_LUCK_BOOST, ("Wheel +%d%% (%ds)"):format(pct(WHEEL_LUCK_BOOST), math.ceil(fx.wheelLuckUntil - now)))
		end
		if fx.overchargeRolls > 0 then
			bonus(OVERCHARGE_BOOST, ("Growth Overcharge +%d%% (%s)"):format(pct(OVERCHARGE_BOOST), rollsLeft(fx.overchargeRolls)))
		end
		if fx.passes.Luck2x then
			mult *= 2
			table.insert(parts, "2x Luck Pass")
		end
		if now < fx.orbUntil then
			mult *= ORB_LUCK_MULT
			table.insert(parts, ("Orb Surge x%s (%ds)"):format(tostring(ORB_LUCK_MULT), math.ceil(fx.orbUntil - now)))
		end
		if fx.godspeedRolls > 0 then
			mult *= GODSPEED_MULT
			table.insert(parts, ("GODSPEED x%d (%s)"):format(GODSPEED_MULT, rollsLeft(fx.godspeedRolls)))
		end
		if now < fx.skyJumpUntil then -- not luck, but shown on the badge with the other boosts
			table.insert(parts, ("Sky Jump x%d (%ds)"):format(SKY_JUMP_MULT, math.ceil(fx.skyJumpUntil - now)))
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

-- opts.ignoreCooldown: free/surge rolls skip the cooldown
-- opts.minOneIn: only land on tiers at least this rare (Titan Surge)
-- opts.fast: use the short Fast Roll spin
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
		if fx.overchargeRolls > 0 then
			fx.overchargeRolls -= 1
		end
		if fx.godspeedRolls > 0 then
			fx.godspeedRolls -= 1
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
	local spinTime = (opts.fast or hasPass(player, "FastRoll")) and FAST_SPIN_TIME or SPIN_TIME
	fx.lastSpinTime = spinTime
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
-- fast = use the short Fast Roll spin (the spinner's "5 Instant Fast Rolls").
local function queueBonusRolls(player, count, fast)
	local fx = effects[player]
	if not fx then
		return
	end
	for _ = 1, count do
		table.insert(fx.bonusQueue, fast == true)
	end
	if fx.bonusRunning then
		return
	end
	fx.bonusRunning = true
	task.spawn(function()
		while #fx.bonusQueue > 0 and player.Parent do
			local waitFor = (lastRollTime[player] or 0) + fx.lastSpinTime + 0.4 - os.clock()
			if waitFor > 0 then
				task.wait(waitFor)
			end
			if not player.Parent then
				break
			end
			local isFast = table.remove(fx.bonusQueue, 1)
			doRoll(player, nil, { ignoreCooldown = true, fast = isFast })
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

-- Re-apply jump height after Sky Jump starts or ends.
local function refreshJump(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local fx = effects[player]
	if humanoid and fx then
		local jumpBoost = os.clock() < fx.skyJumpUntil and SKY_JUMP_MULT or 1
		humanoid.JumpHeight = BASE_JUMP_HEIGHT * character:GetScale() ^ 0.75 * jumpBoost
	end
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
	orb.Transparency = visible and (orb:GetAttribute("BaseTransparency") or 0) or 1
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

---------------------------------------------------------------------
-- TITAN'S THRONE (tag "ApexPedestal", Y = 950): a 50x+ player standing on it
-- gets +50% Apex Luck, and everyone else gets +10% "Titan's Favor" while it's taken
---------------------------------------------------------------------
local throneRay = RaycastParams.new()
throneRay.FilterType = Enum.RaycastFilterType.Include

local function isOnThrone(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 or character:GetScale() < THRONE_MIN_SCALE then
		return false
	end
	throneRay.FilterDescendantsInstances = CollectionService:GetTagged("ApexPedestal")
	local reach = root.Size.Y / 2 + humanoid.HipHeight + 30 -- just below the feet
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), throneRay) ~= nil
end

local function updateThrone()
	local anyone = false
	for player, fx in pairs(effects) do
		local was = fx.throne
		fx.throne = player.Parent ~= nil and isOnThrone(player.Character)
		anyone = anyone or fx.throne
		if fx.throne ~= was then
			local text = fx.throne and (player.DisplayName .. " took the TITAN'S THRONE!  Everyone gets +10% Luck")
				or (player.DisplayName .. " left the Titan's Throne.")
			for _, other in ipairs(Players:GetPlayers()) do
				tell(other, text, fx.throne and GOLD or GREY)
			end
		end
	end
	throneTaken = anyone
end

---------------------------------------------------------------------
-- WIND LAUNCHERS (tag "WindLauncher"): fling normal-sized players along an
-- arc that lands on the pad's Target after FlightTime seconds
---------------------------------------------------------------------
local function connectLauncher(pad)
	pad.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		local fx = player and effects[player]
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local target, flightTime = pad:GetAttribute("Target"), pad:GetAttribute("FlightTime")
		if not (fx and root and target and flightTime) or character:GetScale() > LAUNCH_MAX_SCALE then
			return
		end
		if os.clock() - fx.lastLaunch < LAUNCH_COOLDOWN then
			return
		end
		fx.lastLaunch = os.clock()
		local offset = target - root.Position
		local g = workspace.Gravity
		local velocity = Vector3.new(offset.X / flightTime, (offset.Y + 0.5 * g * flightTime ^ 2) / flightTime, offset.Z / flightTime)
		bounce:FireClient(player, velocity, flightTime, "launch")
	end)
end
for _, pad in ipairs(CollectionService:GetTagged("WindLauncher")) do
	connectLauncher(pad)
end
CollectionService:GetInstanceAddedSignal("WindLauncher"):Connect(connectLauncher)

---------------------------------------------------------------------
-- UPDRAFT VOID CATCHER: a normal-sized player who falls off a cloud is
-- caught by a soft updraft once they drop below CATCH_Y, then set down at
-- the spawn plaza instead of free-falling all the way to the grass
---------------------------------------------------------------------
-- What's under the feet? (The server can't trust Humanoid.FloorMaterial: each
-- client simulates its own character, so we look with a ray instead.)
local floorRay = RaycastParams.new()
floorRay.FilterType = Enum.RaycastFilterType.Exclude
floorRay.RespectCanCollide = true -- see-through cloud puffs don't count as floor

local function plazaPoint()
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	return spawn and spawn.Position + Vector3.new(0, spawn.Size.Y / 2, 0) or Vector3.zero
end

local function catchFall(player, fx, character, root, humanoid)
	fx.catching = true
	fx.cloudFeetY = nil
	-- the server takes over the character's physics for the catch, so the
	-- updraft grabs it right away instead of a network round trip later
	pcall(root.SetNetworkOwner, root, nil)
	local fallSpeed = root.AssemblyLinearVelocity.Y * 0.5 -- halve the fall at once, then ease into the float
	local lift = Instance.new("BodyVelocity") -- eases the fall into a gentle upward float
	lift.Name = "UpdraftCatch"
	lift.MaxForce = Vector3.one * 1e7
	lift.Velocity = Vector3.new(0, fallSpeed, 0)
	lift.Parent = root
	task.spawn(function()
		for step = 1, 5 do
			task.wait(0.04)
			lift.Velocity = Vector3.new(0, fallSpeed + (8 - fallSpeed) * step / 5, 0)
		end
	end)
	local wind = Instance.new("ParticleEmitter")
	wind.Name = "UpdraftCatch"
	wind.Texture = SPARKLE_TEXTURE
	wind.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255))
	wind.LightEmission = 0.6
	wind.Orientation = Enum.ParticleOrientation.VelocityParallel
	wind.Squash = NumberSequence.new(2)
	wind.Transparency = NumberSequence.new(0.2, 1)
	wind.Size = NumberSequence.new(1.2, 0)
	wind.Lifetime = NumberRange.new(0.6, 1)
	wind.Rate = 60
	wind.Speed = NumberRange.new(25, 40)
	wind.EmissionDirection = Enum.NormalId.Top
	wind.SpreadAngle = Vector2.new(25, 25)
	wind.Parent = root
	tell(player, "An updraft caught you!  Floating back to the plaza...", SKY_BLUE)
	task.delay(1.6, function()
		lift:Destroy()
		wind:Destroy()
		if character.Parent and humanoid.Health > 0 then
			local feetOffset = root.Size.Y / 2 + humanoid.HipHeight
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(CFrame.new(plazaPoint() + Vector3.new(0, feetOffset + 0.5, 0)))
			pcall(root.SetNetworkOwner, root, player)
		end
		fx.catching = false
	end)
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local characters = {}
		for _, player in ipairs(Players:GetPlayers()) do
			table.insert(characters, player.Character)
		end
		floorRay.FilterDescendantsInstances = characters
		for player, fx in pairs(effects) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 and skyRealm and not fx.catching then
				local feetOffset = root.Size.Y / 2 + humanoid.HipHeight
				local feetY = root.Position.Y - feetOffset
				local floor = workspace:Raycast(root.Position, Vector3.new(0, -(feetOffset + 4), 0), floorRay)
				if character:GetScale() >= CATCH_MAX_SCALE then
					fx.cloudFeetY = nil
				elseif floor then
					-- standing: on a cloud (remember how high) or on the ground (forget)
					fx.cloudFeetY = floor.Instance:IsDescendantOf(skyRealm) and feetY or nil
				elseif fx.cloudFeetY and feetY < math.min(CATCH_Y, fx.cloudFeetY - CATCH_DROP) and root.AssemblyLinearVelocity.Y < 0 then
					catchFall(player, fx, character, root, humanoid)
				end
			end
		end
	end
end)

-- Twice a second: update the throne, end Sky Blessings for anyone who left
-- the clouds, and refresh everyone's luck badge (timers count down).
task.spawn(function()
	while true do
		task.wait(0.5)
		updateThrone()
		for player, fx in pairs(effects) do
			if fx.sky then
				if not isOverClouds(player.Character) then
					fx.sky = false
					tell(player, "Your Sky Blessing faded: you left the clouds.", GREY)
				end
			end
			if fx.skyJumpUntil > 0 and os.clock() >= fx.skyJumpUntil then
				fx.skyJumpUntil = 0
				refreshJump(player)
				tell(player, "Sky Jump wore off.", GREY)
			end
			if player.Parent then
				refreshLuckInfo(player)
			end
		end
	end
end)

---------------------------------------------------------------------
-- GROWTH SPINNER (Workspace.Lobby.GrowthSpinner, built in Studio)
---------------------------------------------------------------------
local WHEEL_TILES = 100
local HUB_TILT = CFrame.Angles(0, math.rad(90), 0) -- the hub is a cylinder, which spins around its X axis
local lobby = workspace:FindFirstChild("Lobby")
local wheelModel = lobby and lobby:FindFirstChild("GrowthSpinner")
local wheelHub = wheelModel and wheelModel:FindFirstChild("Hub")
local wheelBase = wheelModel and wheelModel:GetAttribute("BaseCFrame")
local wheelAngle = Instance.new("NumberValue")
local wheelTween = nil
if wheelHub and wheelBase then
	wheelAngle.Changed:Connect(function(angle)
		wheelHub.CFrame = wheelBase * CFrame.Angles(0, 0, angle) * HUB_TILT
	end)
end

-- The Mythic slice's tiles (attribute "Prismatic") slowly cycle through the rainbow.
local prismaticTiles = {}
for _, obj in ipairs(wheelModel and wheelModel:GetDescendants() or {}) do
	if obj:IsA("BasePart") and obj:GetAttribute("Prismatic") then
		table.insert(prismaticTiles, obj)
	end
end
if #prismaticTiles > 0 then
	task.spawn(function()
		local hue = 0
		while true do
			hue = (hue + 0.01) % 1
			for i, tile in ipairs(prismaticTiles) do
				tile.Color = Color3.fromHSV((hue + i * 0.12) % 1, 0.45, 1)
			end
			task.wait(0.1)
		end
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
	elseif key == "FastRolls" then
		queueBonusRolls(player, FAST_ROLL_PRIZE, true)
	elseif key == "SkyJump" then
		fx.skyJumpUntil = os.clock() + SKY_JUMP_TIME
		refreshJump(player)
	elseif key == "Overcharge" then
		fx.overchargeRolls += OVERCHARGE_ROLLS
	elseif key == "TitanSurge" then
		doRoll(player, nil, { ignoreCooldown = true, minOneIn = TITAN_SURGE_MIN_ONE_IN })
	elseif key == "Godspeed" then
		fx.godspeedRolls += GODSPEED_ROLLS
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				tell(other, player.DisplayName .. " hit GODSPEED on the Growth Spinner!", GOLD)
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
	if wheelModel then
		wheelModel:SetAttribute("SpinStarted", workspace:GetServerTimeNow()) -- clients ripple the platform floor
	end
	local swirl = wheelModel and wheelModel:FindFirstChild("SpinSwirl", true) -- glyphs swirling around the platform
	if swirl then
		swirl.Enabled = true
		task.delay(WHEEL_SPIN_TIME, function()
			swirl.Enabled = false
		end)
	end
	tell(player, "The Growth Spinner is spinning...", Color3.fromRGB(200, 190, 230))
	task.delay(WHEEL_SPIN_TIME, function()
		fx.wheelBusy = false
		if player.Parent and effects[player] then
			giveWheelPrize(player, WHEEL[index].key)
			tell(player, ("%s: %s"):format(WHEEL[index].rarity:upper(), WHEEL[index].label), WHEEL[index].color)
		end
	end)
end

spinWheel.OnServerEvent:Connect(spinWheelFor)
local wheelPrompt = wheelHub and wheelHub:FindFirstChildOfClass("ProximityPrompt")
if wheelPrompt then
	wheelPrompt.Triggered:Connect(spinWheelFor)
end

---------------------------------------------------------------------
-- GROUND SHAKER STOMP (F key, 50x+): boom + shockwave for everyone, and
-- players a tenth of the stomper's size (or smaller) nearby get popped up
---------------------------------------------------------------------
stomp.OnServerEvent:Connect(function(player)
	local fx = effects[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (fx and root and humanoid) or humanoid.Health <= 0 then
		return
	end
	local scale = character:GetScale()
	if scale < STOMP_MIN_SCALE then
		return
	end
	local remaining = STOMP_COOLDOWN - (os.clock() - fx.lastStomp)
	if remaining > 0 then
		tell(player, ("Stomp recharging: %ds"):format(math.ceil(remaining)), GREY)
		return
	end
	fx.lastStomp = os.clock()
	local ground = root.Position - Vector3.new(0, root.Size.Y / 2 + humanoid.HipHeight, 0)
	stompFx:FireAllClients(ground, scale)
	local popped = 0
	for _, other in ipairs(Players:GetPlayers()) do
		local otherCharacter = other.Character
		local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
		if other ~= player and otherRoot and otherCharacter:GetScale() <= scale * STOMP_SIZE_RATIO then
			local offset = (otherRoot.Position - ground) * Vector3.new(1, 0, 1)
			if offset.Magnitude <= scale * STOMP_RADIUS and math.abs(otherRoot.Position.Y - ground.Y) < scale then
				bounce:FireClient(other, Vector3.new(0, STOMP_POP, 0))
				popped += 1
			end
		end
	end
	if popped > 0 then
		tell(player, ("STOMP! You popped %d player%s"):format(popped, popped == 1 and "" or "s"), GOLD)
	end
end)

---------------------------------------------------------------------
-- SETTINGS (music / sfx / low gfx), saved with the player's data
---------------------------------------------------------------------
saveSettings.OnServerEvent:Connect(function(player, settings)
	local data = playerData[player]
	if not data or type(settings) ~= "table" then
		return
	end
	for key in pairs(data.settings) do
		if type(settings[key]) == "boolean" then
			data.settings[key] = settings[key]
		end
	end
end)

---------------------------------------------------------------------
-- CRUSH PIT (Workspace.Lobby.CrushPit, built in Studio)
-- Giants (10x+) walking through the pit bounce small players (2x or less)
-- off their feet: no damage, just a launch. Both sides earn Essence.
---------------------------------------------------------------------
local pitModel = lobby and lobby:FindFirstChild("CrushPit")
local pitCenter = pitModel and pitModel:GetAttribute("Center")
local pitRadius = pitModel and pitModel:GetAttribute("Radius")
local pitScores = {} -- [player] = bounces given + taken this server
local lastBounced = {} -- [player] = os.clock() of their last bounce

local function giveEssence(player, amount)
	local data = playerData[player]
	if data and amount > 0 then
		data.essence += amount
		player:SetAttribute("Essence", data.essence)
	end
end

local function updatePitBoard()
	local display = pitModel and pitModel:FindFirstChild("Display", true)
	if not display then
		return
	end
	local entries = {}
	for player, score in pairs(pitScores) do
		if player.Parent and score > 0 then
			table.insert(entries, { name = player.DisplayName, score = score })
		end
	end
	table.sort(entries, function(a, b)
		return a.score > b.score
	end)
	for i = 1, 3 do
		local row = display:FindFirstChild("Row" .. i, true)
		if row then
			local entry = entries[i]
			row.Text = entry and ("%d.  %s   %d bounces"):format(i, escapeRichText(entry.name), entry.score) or (i .. ".  ---")
		end
	end
end

local function inPit(position)
	local offset = position - pitCenter
	return Vector2.new(offset.X, offset.Z).Magnitude <= pitRadius
end

local function bounceSmall(victim, giant, foot)
	local root = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local away = (root.Position - foot.Position) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.1 then
		away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	end
	bounce:FireClient(victim, away.Unit * PIT_BOUNCE_OUT + Vector3.new(0, PIT_BOUNCE_UP, 0))
	giveEssence(victim, PIT_ESSENCE_BOUNCED)
	giveEssence(giant, PIT_ESSENCE_STOMPER)
	pitScores[victim] = (pitScores[victim] or 0) + 1
	pitScores[giant] = (pitScores[giant] or 0) + 1
	tell(victim, ("BOING! %s bounced you  +%d Essence"):format(giant.DisplayName, PIT_ESSENCE_BOUNCED), GOLD)
	tell(giant, ("STOMP! You bounced %s  +%d Essence"):format(victim.DisplayName, PIT_ESSENCE_STOMPER), GOLD)
	updatePitBoard()
end

if pitCenter and pitRadius then
	local pitOverlap = OverlapParams.new()
	pitOverlap.FilterType = Enum.RaycastFilterType.Include
	local nextParticipation = os.clock() + 10
	task.spawn(function()
		while true do
			task.wait(0.1)
			local smalls, smallCharacters, giants = {}, {}, {}
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and humanoid and humanoid.Health > 0 and playerData[player] then
					local scale = character:GetScale()
					if scale >= PIT_GIANT_MIN_SCALE then
						-- a giant is "in" when a foot is over the pit (its root can be far outside)
						local left, right = character:FindFirstChild("LeftFoot"), character:FindFirstChild("RightFoot")
						if (left and inPit(left.Position)) or (right and inPit(right.Position)) then
							table.insert(giants, player)
						end
					elseif scale <= PIT_SMALL_MAX_SCALE and inPit(root.Position) then
						table.insert(smalls, player)
						table.insert(smallCharacters, character)
					end
				end
			end
			if #giants > 0 and #smalls > 0 then
				pitOverlap.FilterDescendantsInstances = smallCharacters
				for _, giant in ipairs(giants) do
					for _, footName in ipairs({ "LeftFoot", "RightFoot" }) do
						local foot = giant.Character and giant.Character:FindFirstChild(footName)
						if foot then
							local zone = foot.Size * 1.4 + Vector3.new(4, 4, 4)
							for _, part in ipairs(workspace:GetPartBoundsInBox(foot.CFrame, zone, pitOverlap)) do
								local victim = playerFromHit(part)
								if victim and os.clock() - (lastBounced[victim] or 0) > PIT_BOUNCE_COOLDOWN then
									lastBounced[victim] = os.clock()
									bounceSmall(victim, giant, foot)
								end
							end
						end
					end
				end
				if os.clock() >= nextParticipation then
					nextParticipation = os.clock() + 10
					for _, player in ipairs(smalls) do
						giveEssence(player, PIT_PARTICIPATION_ESSENCE)
					end
					for _, player in ipairs(giants) do
						giveEssence(player, PIT_PARTICIPATION_ESSENCE)
					end
				end
			else
				nextParticipation = os.clock() + 10
			end
		end
	end)
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
		if RunService:IsStudio() and DEBUG_UNLOCK_PASSES then
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
		if type(saved.settings) == "table" then
			for key in pairs(data.settings) do
				if type(saved.settings[key]) == "boolean" then
					data.settings[key] = saved.settings[key]
				end
			end
		end
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
	player:SetAttribute("Settings", HttpService:JSONEncode(data.settings)) -- the client applies these once on join
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
	pitScores[player] = nil
	lastBounced[player] = nil
	updateBoard()
	updatePitBoard()
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
