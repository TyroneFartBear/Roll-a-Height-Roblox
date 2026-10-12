--[[
	RollClient  (LocalScript)
	Goes in: StarterPlayer > StarterPlayerScripts   Name it: RollClient

	Everything the player SEES: the roll button, the slot-machine spin,
	the result popup, rare-roll banners, screen flash/shake and camera zoom.
	The UI is built from code, so there's nothing to draw by hand in Studio.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local HttpService = game:GetService("HttpService") -- only for JSONDecode, no web requests
local MarketplaceService = game:GetService("MarketplaceService")

local RarityTable = require(ReplicatedStorage:WaitForChild("RarityTable"))
local Tiers = RarityTable.Tiers

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rollRequest = remotes:WaitForChild("RollRequest")
local rollResult = remotes:WaitForChild("RollResult")
local announce = remotes:WaitForChild("Announce")
local equipBest = remotes:WaitForChild("EquipBest")
local devForceRoll = remotes:WaitForChild("DevForceRoll")
local equipTier = remotes:WaitForChild("EquipTier")
local spinWheel = remotes:WaitForChild("SpinWheel")
local shopRequest = remotes:WaitForChild("ShopRequest")
local notify = remotes:WaitForChild("Notify")
local bounce = remotes:WaitForChild("Bounce")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local POPUP_HOLD_TIME = 2.5 -- how long the result stays on screen
local BIG_REVEAL_ONE_IN = 1000 -- flash + strong shake at this rarity or rarer
local SMALL_REVEAL_ONE_IN = 100 -- light shake at this rarity or rarer
local AUTO_ROLL_INTERVAL = 1.5 -- seconds between auto-rolls
local FAST_AUTO_ROLL_INTERVAL = 0.45 -- with the Fast Roll pass
local FOOTSTEP_MIN_SCALE = 10 -- characters this big (or bigger) shake the ground
local THUD_SOUND = "rbxasset://sounds/action_footsteps_plastic.mp3" -- played slowed down = deep thud
local SHOCKWAVE_MIN_SCALE = 150 -- god tiers send a shockwave ring out on every footstep

-- Paste sound IDs from the Creator Store here, e.g. "rbxassetid://12345".
-- Left empty = no sound (nothing breaks).
local SOUNDS = {
	tick = "", -- each step of the spin
	reveal = "", -- normal result
	rare = "", -- big reveal / server announcement
}

---------------------------------------------------------------------
-- SMALL HELPERS
---------------------------------------------------------------------
local function make(className, props, children)
	local obj = Instance.new(className)
	for key, value in pairs(props) do
		obj[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = obj
	end
	return obj
end

local function corner(radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(thickness, color)
	return make("UIStroke", { Thickness = thickness, Color = color or Color3.new(0, 0, 0) })
end

local function tween(obj, time, props, style, direction)
	local t = TweenService:Create(
		obj,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	t:Play()
	return t
end

local soundCache = {}
local function playSound(name)
	local id = SOUNDS[name]
	if not id or id == "" then
		return
	end
	local sound = soundCache[name]
	if not sound then
		sound = make("Sound", { SoundId = id, Parent = SoundService })
		soundCache[name] = sound
	end
	SoundService:PlayLocalSound(sound)
end

local function escapeRichText(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

---------------------------------------------------------------------
-- BUILD THE SCREEN
---------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "RollGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- Full-screen flash for rare rolls
local flash = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Parent = gui,
})

-- Bottom bar: [EQUIP BEST] [ROLL]
local bottomBar = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(1, 0, 0, 76),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local equipButton = make("TextButton", {
	LayoutOrder = 1,
	Size = UDim2.new(0, 110, 0, 52),
	BackgroundColor3 = Color3.fromRGB(120, 80, 220),
	Font = FONT,
	Text = "EQUIP\nBEST",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 20,
	Parent = bottomBar,
}, { corner(14), stroke(3, Color3.fromRGB(40, 20, 80)) })

local rollButton = make("TextButton", {
	LayoutOrder = 2,
	Size = UDim2.new(0, 200, 0, 76),
	BackgroundColor3 = Color3.fromRGB(255, 70, 120),
	Font = FONT,
	Text = "ROLL",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 44,
	Parent = bottomBar,
}, {
	corner(18),
	stroke(4, Color3.fromRGB(90, 10, 40)),
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
	}),
})
local rollButtonScale = make("UIScale", { Parent = rollButton })

local AUTO_OFF_COLOR = Color3.fromRGB(70, 70, 90)
local AUTO_ON_COLOR = Color3.fromRGB(50, 200, 110)
local autoButton = make("TextButton", {
	LayoutOrder = 3,
	Size = UDim2.new(0, 110, 0, 52),
	BackgroundColor3 = AUTO_OFF_COLOR,
	Font = FONT,
	Text = "AUTO\nOFF",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 20,
	Parent = bottomBar,
}, { corner(14) })
local autoStroke = stroke(3, Color3.fromRGB(25, 25, 35))
autoStroke.Parent = autoButton

-- "Luck: 1.2x  •  Friend Boost +20%" pill above the status line
local luckLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -142),
	Size = UDim2.new(0, 0, 0, 26),
	AutomaticSize = Enum.AutomaticSize.XY, -- grows upward when active boosts add a second line
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.35,
	Font = FONT,
	RichText = true,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "Luck: 1.0x",
	Parent = gui,
}, {
	corner(13),
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
})

-- "You: Tall (6 ft 3 in)  |  Best: Giant" line above the buttons
local statusLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -108),
	Size = UDim2.new(0.95, 0, 0, 28),
	BackgroundTransparency = 1,
	Font = FONT,
	RichText = true,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	Parent = gui,
}, { stroke(2) })

-- Center popup: spin + result
local popup = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.38),
	Size = UDim2.new(0.95, 0, 0, 230),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
}, {
	make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local popupScale = make("UIScale", { Parent = popup })

local newBestLabel = make("TextLabel", {
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	Text = "NEW BEST!",
	TextSize = 30,
	TextColor3 = Color3.fromRGB(255, 225, 60),
	Parent = popup,
}, { stroke(3) })

local nameLabel = make("TextLabel", {
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 100),
	BackgroundTransparency = 1,
	Font = FONT,
	TextScaled = true,
	Text = "",
	TextColor3 = Color3.new(1, 1, 1),
	Parent = popup,
}, { stroke(5), make("UITextSizeConstraint", { MaxTextSize = 96 }) })

local titleLabel = make("TextLabel", {
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 34,
	Text = "",
	TextColor3 = Color3.new(1, 1, 1),
	Parent = popup,
}, { stroke(3) })

local detailLabel = make("TextLabel", {
	LayoutOrder = 4,
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	Text = "",
	TextColor3 = Color3.fromRGB(230, 230, 230),
	Parent = popup,
}, { stroke(2) })

-- Top banner for server-wide announcements
local banner = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -100),
	Size = UDim2.new(0.9, 0, 0, 58),
	BackgroundColor3 = Color3.fromRGB(15, 15, 25),
	BackgroundTransparency = 0.15,
	Font = FONT,
	RichText = true,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	ZIndex = 40,
	Parent = gui,
}, {
	corner(14),
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	make("UITextSizeConstraint", { MaxTextSize = 30 }),
})
local bannerStroke = make("UIStroke", {
	Thickness = 3,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Parent = banner,
})

gui.Parent = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- STATUS LINE
---------------------------------------------------------------------
local function colored(text, color)
	return ('<font color="#%s">%s</font>'):format(color:ToHex(), text)
end

local function refreshStatus()
	local tierId = player:GetAttribute("HeightTier")
	local bestId = player:GetAttribute("BestTier")
	if not tierId or not bestId then
		return
	end
	local tier, best = Tiers[tierId], Tiers[bestId]
	statusLabel.Text = ("You: %s (%s)   |   Best: %s"):format(
		colored(tier.name, tier.color),
		RarityTable.FormatHeight(player:GetAttribute("HeightScale") or 1),
		colored(best.name, best.color)
	)
end

---------------------------------------------------------------------
-- CAMERA: zoom out for giants, zoom in for tiny players
---------------------------------------------------------------------
local function zoomFor(scale)
	return math.max(12.5 * scale, 0.6)
end

local function applyCamera(snap)
	local scale = player:GetAttribute("HeightScale") or 1
	local maxZoom = math.max(128, 30 * scale)
	player.CameraMaxZoomDistance = maxZoom
	player.CameraMinZoomDistance = 0.5
	if snap then
		-- Trick: pin min and max to the same value for a moment to force the zoom.
		local target = zoomFor(scale)
		player.CameraMinZoomDistance = target
		player.CameraMaxZoomDistance = target
		task.wait(0.05)
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = maxZoom
	end
end

player:GetAttributeChangedSignal("HeightScale"):Connect(function()
	refreshStatus()
	applyCamera(true)
end)
player:GetAttributeChangedSignal("BestTier"):Connect(refreshStatus)
player.CharacterAdded:Connect(function()
	task.delay(1.5, applyCamera, true) -- after the server re-sizes the new body
end)
refreshStatus()
applyCamera(false)

---------------------------------------------------------------------
-- GIANT ANIMATION FIX
-- Animations move the root joint a little (idle bob, walk sway). On a
-- scaled-up character Roblox blows that offset up far too much (it grows
-- with scale squared): at 35x+ the whole body sinks hundreds of studs
-- through the floor. For big characters we keep each joint's animated
-- rotation but drop its animated position. Every client animates every
-- character it can see, so this runs for all players (RollServer does the
-- same for the server's copy).
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
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
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
-- JUICE: flash + shake
---------------------------------------------------------------------
local function doFlash(color)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.1
	tween(flash, 0.6, { BackgroundTransparency = 1 })
end

local function shake(duration, strength)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- Scale the shake to how far the camera is, so giants feel it too.
	local amount = strength * zoomFor(player:GetAttribute("HeightScale") or 1) / 12.5
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= duration or not humanoid.Parent then
			humanoid.CameraOffset = Vector3.zero
			connection:Disconnect()
			return
		end
		local fade = 1 - t / duration
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * amount * fade,
			(math.random() - 0.5) * amount * fade,
			(math.random() - 0.5) * amount * fade
		)
	end)
end

local function pop(fromScale, time)
	popupScale.Scale = fromScale
	tween(popupScale, time, { Scale = 1 }, Enum.EasingStyle.Back)
end

---------------------------------------------------------------------
-- TIER EFFECTS drawn on this screen only (not replicated): void crystals
-- orbiting "Void" tiers, cosmic rings around "Godly" tiers, and the god
-- tier's footstep shockwaves.
---------------------------------------------------------------------
local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalTierEffects"
fxFolder.Parent = workspace
local orbiters = {} -- [player] = { character, aura, scale, parts, specs, t }

local function effectPart(props)
	props.Anchored = true
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	props.CastShadow = false
	props.Parent = fxFolder
	return make("Part", props)
end

local function buildOrbiters(aura, scale)
	local parts, specs = {}, {}
	if aura == "Void" then
		for i = 1, 6 do
			table.insert(parts, effectPart({
				Size = Vector3.new(0.5, 1.2, 0.5) * scale,
				Material = Enum.Material.Glass,
				Color = Color3.fromRGB(150, 90, 230),
				Transparency = 0.25,
			}))
			table.insert(specs, { radius = 2.6 * scale, angle = i / 6 * math.pi * 2, speed = 0.6, tilt = 0, bob = 0.6 * scale, spin = true })
		end
	elseif aura == "Godly" then
		for ring = 1, 2 do
			for i = 1, 18 do
				table.insert(parts, effectPart({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.3 * scale,
					Material = Enum.Material.Neon,
					Color = ring == 1 and Color3.fromRGB(190, 160, 255) or Color3.fromRGB(150, 220, 240),
					Transparency = 0.5,
				}))
				table.insert(specs, {
					radius = (ring == 1 and 3 or 3.6) * scale,
					angle = i / 18 * math.pi * 2,
					speed = ring == 1 and 0.35 or -0.25,
					tilt = math.rad(ring == 1 and 20 or -30),
				})
			end
		end
	end
	return parts, specs
end

local function clearOrbiters(other)
	local o = orbiters[other]
	if o then
		for _, part in ipairs(o.parts) do
			part:Destroy()
		end
		orbiters[other] = nil
	end
end

RunService.RenderStepped:Connect(function(dt)
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local tier = Tiers[other:GetAttribute("HeightTier") or 0]
		local aura = root and tier and tier.aura
		local scale = character and character:GetScale() or 1
		local o = orbiters[other]
		if o and (o.character ~= character or o.aura ~= aura or math.abs(o.scale - scale) > 0.01) then
			clearOrbiters(other)
			o = nil
		end
		if not o and (aura == "Void" or aura == "Godly") then
			local parts, specs = buildOrbiters(aura, scale)
			o = { character = character, aura = aura, scale = scale, parts = parts, specs = specs, t = 0 }
			orbiters[other] = o
		end
		if o and root then
			o.t += dt
			for i, part in ipairs(o.parts) do
				local spec = o.specs[i]
				local a = spec.angle + o.t * spec.speed
				local offset = CFrame.Angles(spec.tilt, 0, 0) * Vector3.new(math.cos(a) * spec.radius, 0, math.sin(a) * spec.radius)
				if spec.bob then
					offset += Vector3.new(0, math.sin(o.t * 1.5 + spec.angle) * spec.bob, 0)
				end
				local turn = spec.spin and CFrame.Angles(o.t, o.t * 0.7, 0) or CFrame.identity
				part.CFrame = CFrame.new(root.Position + offset) * turn
			end
		end
	end
end)
Players.PlayerRemoving:Connect(clearOrbiters)

-- An expanding, fading ring on the ground under a god-tier footstep.
local function spawnShockwave(root, humanoid, scale)
	local groundY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, scale * 0.5, scale * 0.5),
		CFrame = CFrame.new(root.Position.X, groundY + 0.5, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(200, 170, 255),
		Transparency = 0.5,
	})
	tween(ring, 1.2, { Size = Vector3.new(0.4, scale * 10, scale * 10), Transparency = 1 })
	task.delay(1.3, ring.Destroy, ring)
end

---------------------------------------------------------------------
-- GIANT FOOTSTEPS: characters 10x+ thud and shake the camera of anyone near
---------------------------------------------------------------------
local stepTimers = {} -- [player] = seconds since that giant's last step

RunService.Heartbeat:Connect(function(dt)
	local myCharacter = player.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	if not myRoot then
		return
	end
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local scale = character and character:GetScale() or 1
		local walking = humanoid
			and root
			and scale >= FOOTSTEP_MIN_SCALE
			and humanoid.MoveDirection.Magnitude > 0.1
			and humanoid.FloorMaterial ~= Enum.Material.Air
		if walking then
			-- bigger strides = slower steps (0.35s at 1x, ~1.1s at 10x, ~5s at 200x)
			local interval = 0.35 * math.sqrt(scale)
			local t = (stepTimers[other] or interval) + dt
			if t >= interval then
				t = 0
				if scale >= SHOCKWAVE_MIN_SCALE then
					spawnShockwave(root, humanoid, scale)
				end
				local range = scale * 12
				local distance = (root.Position - myRoot.Position).Magnitude
				if distance < range then
					local closeness = 1 - distance / range
					local sound = make("Sound", {
						SoundId = THUD_SOUND,
						Volume = 0.4 + 0.6 * closeness,
						PlaybackSpeed = math.clamp(0.6 - scale / 500, 0.25, 0.6),
						RollOffMinDistance = scale * 2,
						RollOffMaxDistance = range,
						Parent = root,
					})
					sound:Play()
					task.delay(3, sound.Destroy, sound)
					shake(0.25, 0.35 * closeness)
				end
			end
			stepTimers[other] = t
		else
			stepTimers[other] = nil
		end
	end
end)
Players.PlayerRemoving:Connect(function(other)
	stepTimers[other] = nil
end)

---------------------------------------------------------------------
-- ROLL FLOW: click -> server rolls -> spin -> reveal
---------------------------------------------------------------------
local rolling = false
local popupToken = 0
local autoOn = false
local lastRollFire = 0

local function setRolling(isRolling)
	rolling = isRolling
	rollButton.Text = isRolling and "..." or "ROLL"
	rollButton.AutoButtonColor = not isRolling
end

local function spin(duration)
	popupToken += 1
	popup.Visible = true
	newBestLabel.TextTransparency = 1
	newBestLabel:FindFirstChildOfClass("UIStroke").Transparency = 1
	titleLabel.Text = ""
	detailLabel.Text = ""

	local start = os.clock()
	local step = 0.04
	local lastId = nil
	while os.clock() - start < duration - 0.03 do
		local id
		repeat
			id = math.random(#Tiers)
		until id ~= lastId
		lastId = id
		nameLabel.Text = Tiers[id].name:upper()
		nameLabel.TextColor3 = Tiers[id].color
		pop(1.12, 0.08)
		playSound("tick")
		task.wait(math.min(step, duration - (os.clock() - start)))
		step *= 1.2 -- slow down like a wheel
	end
end

local function reveal(tierId, scale, isNewBest, essence)
	local tier = Tiers[tierId]
	local rarity = RarityTable.Rarity(tierId)

	nameLabel.Text = tier.name:upper()
	nameLabel.TextColor3 = tier.color
	titleLabel.Text = tier.title
	titleLabel.TextColor3 = tier.color
	detailLabel.Text = ("%s   •   %s   •   %s"):format(
		RarityTable.FormatOdds(tierId),
		RarityTable.FormatScale(scale),
		RarityTable.FormatHeight(scale)
	)
	if essence and essence > 0 then
		detailLabel.Text ..= ("   •   +%d Essence"):format(essence)
	end
	local showNewBest = isNewBest and rarity > 1
	newBestLabel.TextTransparency = showNewBest and 0 or 1
	newBestLabel:FindFirstChildOfClass("UIStroke").Transparency = showNewBest and 0 or 1

	pop(0.3, 0.4)
	if rarity >= BIG_REVEAL_ONE_IN then
		doFlash(tier.color)
		shake(0.7, 1.2)
		playSound("rare")
	elseif rarity >= SMALL_REVEAL_ONE_IN then
		shake(0.3, 0.4)
		playSound("reveal")
	else
		playSound("reveal")
	end

	local myToken = popupToken
	task.delay(POPUP_HOLD_TIME, function()
		if popupToken == myToken then
			popup.Visible = false
		end
	end)
end

local requestToken = 0
local function tryRoll(forcedTierId)
	if rolling then
		return
	end
	setRolling(true)
	lastRollFire = os.clock()
	requestToken += 1
	local myToken = requestToken
	if forcedTierId then
		devForceRoll:FireServer(forcedTierId)
	else
		rollRequest:FireServer()
	end
	-- Safety net: if the server ignored us (cooldown), unlock the button.
	task.delay(3, function()
		if requestToken == myToken and rolling then
			setRolling(false)
		end
	end)
end

rollResult.OnClientEvent:Connect(function(tierId, scale, isNewBest, spinTime, essence)
	requestToken += 1 -- cancels the safety net; we got an answer
	setRolling(true)
	spin(spinTime)
	reveal(tierId, scale, isNewBest, essence)
	-- shorter pause keeps auto-roll on its beat
	local pause = 0.5
	if autoOn then
		pause = player:GetAttribute("Pass_FastRoll") and 0.05 or 0.15
	end
	task.wait(pause)
	setRolling(false)
end)

rollButton.Activated:Connect(function()
	tryRoll()
end)
rollButton.MouseEnter:Connect(function()
	tween(rollButtonScale, 0.1, { Scale = 1.06 })
end)
rollButton.MouseLeave:Connect(function()
	tween(rollButtonScale, 0.1, { Scale = 1 })
end)

equipButton.Activated:Connect(function()
	if not rolling then
		equipBest:FireServer()
	end
end)

---------------------------------------------------------------------
-- AUTO-ROLL
---------------------------------------------------------------------
local autoToken = 0

local function setAuto(on)
	autoOn = on
	autoToken += 1
	autoButton.Text = on and "AUTO\nON" or "AUTO\nOFF"
	autoButton.BackgroundColor3 = on and AUTO_ON_COLOR or AUTO_OFF_COLOR
	autoStroke.Color = on and Color3.fromRGB(15, 80, 40) or Color3.fromRGB(25, 25, 35)
	if not on then
		return
	end
	local myToken = autoToken
	task.spawn(function()
		while autoOn and autoToken == myToken do
			local interval = player:GetAttribute("Pass_FastRoll") and FAST_AUTO_ROLL_INTERVAL or AUTO_ROLL_INTERVAL
			if not rolling and os.clock() - lastRollFire >= interval then
				tryRoll()
			end
			task.wait(0.05)
		end
	end)
end

-- AUTO needs the Auto Roll pass. Without it, clicking opens the purchase prompt
-- (in Studio the server just switches the pass on for testing).
local function refreshAutoLock()
	if player:GetAttribute("Pass_AutoRoll") then
		if not autoOn then
			autoButton.Text = "AUTO\nOFF"
		end
	else
		setAuto(false)
		autoButton.Text = "AUTO\nLOCKED"
	end
end

autoButton.Activated:Connect(function()
	if not autoOn and not player:GetAttribute("Pass_AutoRoll") then
		shopRequest:FireServer("AutoRoll")
		return
	end
	setAuto(not autoOn)
end)
player:GetAttributeChangedSignal("Pass_AutoRoll"):Connect(refreshAutoLock)
refreshAutoLock()

---------------------------------------------------------------------
-- LUCK BADGE
---------------------------------------------------------------------
local function formatLuck(luck)
	-- 1.0x, 1.2x, 1.35x
	return (("%.2f"):format(luck):gsub("0$", "")) .. "x"
end

-- The server works out total luck and what's active, and sends it as "LuckInfo".
local function refreshLuck()
	local ok, info = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("LuckInfo") or "")
	if not ok or type(info) ~= "table" then
		info = { total = 1, parts = {} }
	end
	local text = "Luck: " .. formatLuck(info.total or 1)
	local active = type(info.parts) == "table" and #info.parts > 0
	if active then
		text ..= '\n<font size="14">' .. table.concat(info.parts, "  •  ") .. "</font>"
	end
	luckLabel.Text = text
	luckLabel.TextColor3 = active and Color3.fromRGB(120, 255, 150) or Color3.new(1, 1, 1)
end
player:GetAttributeChangedSignal("LuckInfo"):Connect(refreshLuck)
refreshLuck()

---------------------------------------------------------------------
-- INDEX: every tier, shown as "???" until you've rolled it
---------------------------------------------------------------------
local indexButton = make("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, -54),
	Size = UDim2.new(0, 96, 0, 44),
	BackgroundColor3 = Color3.fromRGB(40, 150, 230),
	Font = FONT,
	Text = "INDEX",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 22,
	Parent = gui,
}, { corner(12), stroke(3, Color3.fromRGB(15, 50, 90)) })

local indexPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromScale(0.9, 0.7),
	BackgroundColor3 = Color3.fromRGB(20, 20, 32),
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
}, {
	corner(16),
	stroke(3, Color3.fromRGB(70, 70, 110)),
	make("UISizeConstraint", { MaxSize = Vector2.new(460, 540) }),
})

local indexTitle = make("TextLabel", {
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(1, -70, 0, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "INDEX",
	Parent = indexPanel,
})

local closeButton = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.new(0, 36, 0, 36),
	BackgroundColor3 = Color3.fromRGB(200, 60, 80),
	Font = FONT,
	Text = "X",
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = indexPanel,
}, { corner(10) })

local indexList = make("ScrollingFrame", {
	Position = UDim2.new(0, 10, 0, 54),
	Size = UDim2.new(1, -20, 1, -64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = indexPanel,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})

-- Most common first, rarest last
local indexOrder = {}
for id in ipairs(Tiers) do
	table.insert(indexOrder, id)
end
table.sort(indexOrder, function(a, b)
	local ra, rb = RarityTable.Rarity(a), RarityTable.Rarity(b)
	if ra ~= rb then
		return ra < rb
	end
	return a < b
end)

local indexRows = {} -- [tierId] = { name, info, button, canEquip }
for order, id in ipairs(indexOrder) do
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 54),
		BackgroundColor3 = Color3.fromRGB(35, 35, 52),
		Parent = indexList,
	}, { corner(10) })
	local entry = {
		name = make("TextLabel", {
			Position = UDim2.new(0, 12, 0, 4),
			Size = UDim2.new(1, -120, 0, 26),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}),
		info = make("TextLabel", {
			Position = UDim2.new(0, 12, 0, 29),
			Size = UDim2.new(1, -120, 0, 20),
			BackgroundTransparency = 1,
			Font = FONT,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(190, 190, 205),
			Parent = row,
		}),
		button = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 96, 0, 36),
			Font = FONT,
			TextSize = 18,
			TextColor3 = Color3.new(1, 1, 1),
			Parent = row,
		}, { corner(10) }),
		canEquip = false,
	}
	entry.button.Activated:Connect(function()
		if entry.canEquip and not rolling then
			equipTier:FireServer(id)
		end
	end)
	indexRows[id] = entry
end

local function refreshIndex()
	local ok, discovered = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Discovered") or "{}")
	if not ok or type(discovered) ~= "table" then
		discovered = {}
	end
	local current = player:GetAttribute("HeightTier")
	local found = 0
	for id, entry in pairs(indexRows) do
		local tier = Tiers[id]
		local scale = discovered[tier.name]
		if scale then
			found += 1
			entry.name.Text = tier.name:upper()
			entry.name.TextColor3 = tier.color
			entry.info.Text = ("%s  •  best %s"):format(RarityTable.FormatOdds(id), RarityTable.FormatScale(scale))
			entry.button.Visible = true
			entry.canEquip = id ~= current
			entry.button.Text = entry.canEquip and "EQUIP" or "EQUIPPED"
			entry.button.BackgroundColor3 = entry.canEquip and Color3.fromRGB(50, 200, 110) or Color3.fromRGB(80, 80, 100)
			entry.button.AutoButtonColor = entry.canEquip
		else
			entry.name.Text = "???"
			entry.name.TextColor3 = Color3.fromRGB(110, 110, 130)
			entry.info.Text = "Not discovered yet"
			entry.button.Visible = false
			entry.canEquip = false
		end
	end
	indexTitle.Text = ("INDEX   %d / %d found"):format(found, #Tiers)
end

indexButton.Activated:Connect(function()
	indexPanel.Visible = not indexPanel.Visible
end)
closeButton.Activated:Connect(function()
	indexPanel.Visible = false
end)
player:GetAttributeChangedSignal("Discovered"):Connect(refreshIndex)
player:GetAttributeChangedSignal("HeightTier"):Connect(refreshIndex)
refreshIndex()

---------------------------------------------------------------------
-- TOAST: short messages from the server (wheel prizes, orbs, blessings)
---------------------------------------------------------------------
local toast = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 122),
	Size = UDim2.new(0, 0, 0, 34),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(15, 15, 25),
	BackgroundTransparency = 0.2,
	Font = FONT,
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	Visible = false,
	ZIndex = 30,
	Parent = gui,
}, {
	corner(12),
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
})
local toastToken = 0

local function showToast(text, color)
	toastToken += 1
	local myToken = toastToken
	toast.Text = text
	toast.TextColor3 = color or Color3.new(1, 1, 1)
	toast.Visible = true
	task.delay(3.5, function()
		if toastToken == myToken then
			toast.Visible = false
		end
	end)
end
notify.OnClientEvent:Connect(showToast)

-- Crush Pit: a giant's foot launched us. No damage, just a bounce.
bounce.OnClientEvent:Connect(function(velocity)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = velocity
		shake(0.3, 0.6)
	end
end)

---------------------------------------------------------------------
-- GROWTH SPINNER button (the physical spinner near spawn has a prompt too)
---------------------------------------------------------------------
local wheelButton = make("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 54),
	Size = UDim2.new(0, 96, 0, 52),
	BackgroundColor3 = Color3.fromRGB(150, 70, 230),
	Font = FONT,
	Text = "WHEEL",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 16,
	Parent = gui,
}, { corner(12), stroke(3, Color3.fromRGB(50, 20, 90)) })

local function refreshWheelButton()
	local cost = remotes:GetAttribute("EssencePerSpin") or 50
	wheelButton.Text = ("SPINNER\n%d/%d"):format(player:GetAttribute("Essence") or 0, cost)
end
wheelButton.Activated:Connect(function()
	spinWheel:FireServer()
end)
player:GetAttributeChangedSignal("Essence"):Connect(refreshWheelButton)
refreshWheelButton()

---------------------------------------------------------------------
-- SHOP: gamepasses (in Studio the button just toggles a pass for testing)
---------------------------------------------------------------------
local PASSES = {
	{ key = "AutoRoll", name = "Auto Roll", desc = "Unlocks the AUTO button: rolls for you every 1.5s.", color = Color3.fromRGB(80, 200, 160) },
	{ key = "Luck2x", name = "2x Luck", desc = "Permanently doubles your luck.", color = Color3.fromRGB(80, 220, 120) },
	{ key = "FastRoll", name = "Fast Roll", desc = "0.4s roll cooldown and spin. Auto-roll goes 3x faster.", color = Color3.fromRGB(80, 170, 255) },
	{ key = "VIP", name = "VIP Rank", desc = "+25% luck and a golden VIP tag over your head and in chat.", color = Color3.fromRGB(255, 215, 0) },
}
local IS_STUDIO = RunService:IsStudio()

local shopButton = make("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.new(0, 96, 0, 44),
	BackgroundColor3 = Color3.fromRGB(255, 180, 40),
	Font = FONT,
	Text = "SHOP",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 22,
	Parent = gui,
}, { corner(12), stroke(3, Color3.fromRGB(110, 60, 0)) })

local shopPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.fromScale(0.9, 0.7),
	BackgroundColor3 = Color3.fromRGB(20, 20, 32),
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
}, {
	corner(16),
	stroke(3, Color3.fromRGB(110, 90, 40)),
	make("UISizeConstraint", { MaxSize = Vector2.new(460, 420) }),
})

make("TextLabel", {
	Position = UDim2.new(0, 16, 0, 10),
	Size = UDim2.new(1, -70, 0, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 215, 0),
	Text = IS_STUDIO and "SHOP  (Studio: buttons toggle)" or "SHOP",
	Parent = shopPanel,
})

local shopClose = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.new(0, 36, 0, 36),
	BackgroundColor3 = Color3.fromRGB(200, 60, 80),
	Font = FONT,
	Text = "X",
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = shopPanel,
}, { corner(10) })

local shopList = make("ScrollingFrame", {
	Position = UDim2.new(0, 10, 0, 54),
	Size = UDim2.new(1, -20, 1, -64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = shopPanel,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})

local shopCards = {} -- [passKey] = { button, price, priceText }
for order, pass in ipairs(PASSES) do
	local card = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 96),
		BackgroundColor3 = Color3.fromRGB(35, 35, 52),
		Parent = shopList,
	}, { corner(12), stroke(2, pass.color) })
	make("TextLabel", {
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -130, 0, 28),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = pass.color,
		Text = pass.name,
		Parent = card,
	})
	make("TextLabel", {
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -130, 0, 38),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = Color3.fromRGB(200, 200, 215),
		Text = pass.desc,
		Parent = card,
	})
	local price = make("TextLabel", {
		Position = UDim2.new(0, 12, 1, -24),
		Size = UDim2.new(1, -130, 0, 20),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 230, 150),
		Text = "",
		Parent = card,
	})
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 104, 0, 40),
		Font = FONT,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, { corner(10) })
	button.Activated:Connect(function()
		shopRequest:FireServer(pass.key)
	end)
	shopCards[pass.key] = { button = button, price = price, priceText = "" }
end

local function refreshShop()
	for _, pass in ipairs(PASSES) do
		local card = shopCards[pass.key]
		local owned = player:GetAttribute("Pass_" .. pass.key) == true
		if IS_STUDIO then
			card.button.Text = owned and "TEST: ON" or "TEST: OFF"
		else
			card.button.Text = owned and "OWNED" or "BUY"
		end
		card.button.BackgroundColor3 = owned and Color3.fromRGB(80, 80, 100) or Color3.fromRGB(50, 200, 110)
		card.price.Text = owned and "Active" or card.priceText
	end
end

-- Prices come from Roblox once real gamepass ids are set in RollServer.
task.spawn(function()
	for _, pass in ipairs(PASSES) do
		local id = remotes:GetAttribute("PassId_" .. pass.key) or 0
		local text = "Coming soon"
		if id ~= 0 then
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, Enum.InfoType.GamePass)
			if ok and info and info.PriceInRobux then
				text = "R$ " .. info.PriceInRobux
			end
		end
		shopCards[pass.key].priceText = text
	end
	refreshShop()
end)

for _, pass in ipairs(PASSES) do
	player:GetAttributeChangedSignal("Pass_" .. pass.key):Connect(refreshShop)
end
refreshShop()

shopButton.Activated:Connect(function()
	shopPanel.Visible = not shopPanel.Visible
	indexPanel.Visible = false
end)
shopClose.Activated:Connect(function()
	shopPanel.Visible = false
end)
indexButton.Activated:Connect(function()
	shopPanel.Visible = false -- only one panel open at a time
end)

-- Keyboard shortcut: R to roll
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.R then
		tryRoll()
	end
end)

---------------------------------------------------------------------
-- SERVER-WIDE ANNOUNCEMENTS
---------------------------------------------------------------------
local bannerToken = 0

local function postToChat(text)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			general:DisplaySystemMessage(text)
		end
	end)
end

announce.OnClientEvent:Connect(function(displayName, tierId, scale)
	local tier = Tiers[tierId]
	local text = ("<b>%s</b> rolled %s  (%s, %s)"):format(
		escapeRichText(displayName),
		colored("<b>" .. tier.name:upper() .. "</b>", tier.color),
		RarityTable.FormatOdds(tierId),
		RarityTable.FormatHeight(scale)
	)

	bannerToken += 1
	local myToken = bannerToken
	banner.Text = text
	bannerStroke.Color = tier.color
	banner.Position = UDim2.new(0.5, 0, 0, -100)
	tween(banner, 0.4, { Position = UDim2.new(0.5, 0, 0, 56) }, Enum.EasingStyle.Back)
	postToChat(text)
	if displayName ~= player.DisplayName then
		playSound("rare")
	end

	task.delay(4, function()
		if bannerToken == myToken then
			tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -100) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end)

---------------------------------------------------------------------
-- VIP CHAT TAG: golden [VIP] in front of VIP players' chat messages
---------------------------------------------------------------------
TextChatService.OnIncomingMessage = function(message)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("VIP") then
		properties.PrefixText = '<font color="#FFD700">[VIP]</font> ' .. message.PrefixText
	end
	return properties
end

---------------------------------------------------------------------
-- STUDIO-ONLY TEST PANEL (never shows in the real game)
---------------------------------------------------------------------
if RunService:IsStudio() then
	local devPanel = make("Frame", {
		Position = UDim2.new(0, 12, 0, 70),
		Size = UDim2.new(0, 200, 0, 40),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BackgroundTransparency = 0.2,
		Parent = gui,
	}, { corner(8) })
	local tierBox = make("TextBox", {
		Position = UDim2.new(0, 6, 0, 6),
		Size = UDim2.new(0, 110, 0, 28),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
		PlaceholderText = ("Tier # 1-%d"):format(#Tiers),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		ClearTextOnFocus = false,
		Parent = devPanel,
	}, { corner(6) })
	local forceButton = make("TextButton", {
		Position = UDim2.new(0, 122, 0, 6),
		Size = UDim2.new(0, 72, 0, 28),
		BackgroundColor3 = Color3.fromRGB(255, 160, 40),
		Text = "FORCE",
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(0, 0, 0),
		Parent = devPanel,
	}, { corner(6) })
	forceButton.Activated:Connect(function()
		local id = tonumber(tierBox.Text)
		if id and Tiers[id] then
			tryRoll(id)
		end
	end)
end
