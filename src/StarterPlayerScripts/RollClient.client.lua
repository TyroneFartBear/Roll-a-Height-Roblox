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

local RarityTable = require(ReplicatedStorage:WaitForChild("RarityTable"))
local Tiers = RarityTable.Tiers

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rollRequest = remotes:WaitForChild("RollRequest")
local rollResult = remotes:WaitForChild("RollResult")
local announce = remotes:WaitForChild("Announce")
local equipBest = remotes:WaitForChild("EquipBest")
local devForceRoll = remotes:WaitForChild("DevForceRoll")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local POPUP_HOLD_TIME = 2.5 -- how long the result stays on screen
local BIG_REVEAL_ONE_IN = 1000 -- flash + strong shake at this rarity or rarer
local SMALL_REVEAL_ONE_IN = 100 -- light shake at this rarity or rarer
local AUTO_ROLL_INTERVAL = 1.5 -- seconds between auto-rolls

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
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.35,
	Font = FONT,
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
-- rotation but drop its animated position. Each client fixes its own
-- character, which is the one it animates.
---------------------------------------------------------------------
local ANIM_FIX_MIN_SCALE = 2
local myMotors = {}

local function trackMotors(character)
	myMotors = {}
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("Motor6D") then
			table.insert(myMotors, obj)
		end
	end
	character.DescendantAdded:Connect(function(obj)
		if obj:IsA("Motor6D") then
			table.insert(myMotors, obj)
		end
	end)
end

player.CharacterAdded:Connect(trackMotors)
if player.Character then
	trackMotors(player.Character)
end

RunService.PreSimulation:Connect(function()
	local character = player.Character
	if not character or character:GetScale() < ANIM_FIX_MIN_SCALE then
		return
	end
	for _, motor in ipairs(myMotors) do
		local transform = motor.Transform
		if transform.Position.Magnitude > 0 then
			motor.Transform = transform.Rotation
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

local function reveal(tierId, scale, isNewBest)
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

rollResult.OnClientEvent:Connect(function(tierId, scale, isNewBest, spinTime)
	requestToken += 1 -- cancels the safety net; we got an answer
	setRolling(true)
	spin(spinTime)
	reveal(tierId, scale, isNewBest)
	task.wait(autoOn and 0.15 or 0.5) -- shorter pause keeps auto-roll on its 1.5s beat
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
			if not rolling and os.clock() - lastRollFire >= AUTO_ROLL_INTERVAL then
				tryRoll()
			end
			task.wait(0.05)
		end
	end)
end

autoButton.Activated:Connect(function()
	setAuto(not autoOn)
end)

---------------------------------------------------------------------
-- LUCK BADGE
---------------------------------------------------------------------
local function refreshLuck()
	local boost = player:GetAttribute("FriendBoost") or 0
	local luck = (player:GetAttribute("Luck") or 1) + boost
	local pct = math.floor(boost * 100 + 0.5)
	if pct > 0 then
		luckLabel.Text = ("Luck: %.1fx  •  Friend Boost +%d%%"):format(luck, pct)
		luckLabel.TextColor3 = Color3.fromRGB(120, 255, 150)
	else
		luckLabel.Text = ("Luck: %.1fx"):format(luck)
		luckLabel.TextColor3 = Color3.new(1, 1, 1)
	end
end
player:GetAttributeChangedSignal("FriendBoost"):Connect(refreshLuck)
player:GetAttributeChangedSignal("Luck"):Connect(refreshLuck)
refreshLuck()

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
