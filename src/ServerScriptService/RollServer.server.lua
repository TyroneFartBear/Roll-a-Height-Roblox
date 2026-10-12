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

local RarityTable = require(ReplicatedStorage:WaitForChild("RarityTable"))
local Tiers = RarityTable.Tiers

---------------------------------------------------------------------
-- SETTINGS (safe to tweak)
---------------------------------------------------------------------
local ROLL_COOLDOWN = 1.6 -- seconds between rolls per player
local SPIN_TIME = 1.2 -- how long the "slot machine" spins before the reveal
local AUTOSAVE_INTERVAL = 90 -- seconds
local DATASTORE_NAME = "RollYourHeight_v1" -- change this to wipe everyone's saves
local BASE_WALKSPEED = 16
local BASE_JUMP_HEIGHT = 7.2

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
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- PLAYER DATA
---------------------------------------------------------------------
local store = DataStoreService:GetDataStore(DATASTORE_NAME)
local rng = Random.new()
local playerData = {} -- [player] = { currentId, currentScale, bestId, bestScale, rolls, canSave }
local lastRollTime = {} -- [player] = os.clock() of their last roll

local function defaultData()
	return {
		currentId = RarityTable.FallbackId,
		currentScale = 1,
		bestId = RarityTable.FallbackId,
		bestScale = 1,
		rolls = 0,
		canSave = false,
	}
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
	elseif tier.aura == "Cosmic" then
		addGlow(character, root, tier.color, scale)
		addEmitter(root, FIRE_TEXTURE, tier.color, scale, 25, true)
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
	end
end

---------------------------------------------------------------------
-- ROLLING
---------------------------------------------------------------------
local function getLuck(player)
	-- Hook for later: luck potions / VIP gamepass set this attribute.
	return player:GetAttribute("Luck") or 1
end

local function tryStartCooldown(player)
	local now = os.clock()
	if lastRollTime[player] and now - lastRollTime[player] < ROLL_COOLDOWN then
		return false
	end
	lastRollTime[player] = now
	return true
end

local function doRoll(player, forcedTierId)
	local data = playerData[player]
	if not data or not tryStartCooldown(player) then
		return
	end

	local tierId, scale
	if forcedTierId then
		tierId, scale = forcedTierId, RarityTable.ScaleFor(forcedTierId, rng)
	else
		tierId, scale = RarityTable.Roll(getLuck(player), rng)
	end
	local tier = Tiers[tierId]

	local isNewBest = RarityTable.IsBetter(tierId, scale, data.bestId, data.bestScale)
	data.rolls += 1
	data.currentId, data.currentScale = tierId, scale
	if isNewBest then
		data.bestId, data.bestScale = tierId, scale
	end

	-- Tell the roller right away so their spin animation can start...
	rollResult:FireClient(player, tierId, scale, isNewBest, SPIN_TIME)

	-- ...and only change the body when the spin finishes, for the big reveal.
	task.delay(SPIN_TIME, function()
		if not player.Parent then
			return
		end
		applyHeight(player)
		refreshStats(player)
		if tier.announce then
			announce:FireAllClients(player.DisplayName, tierId, scale)
		end
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
-- JOIN / LEAVE
---------------------------------------------------------------------
local function onPlayerAdded(player)
	setupLeaderstats(player)

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
	end
	if not player.Parent then
		return -- left while we were loading
	end
	playerData[player] = data
	refreshStats(player)

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
	saveData(player)
	playerData[player] = nil
	lastRollTime[player] = nil
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
