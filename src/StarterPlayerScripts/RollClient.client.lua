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
local stomp = remotes:WaitForChild("Stomp")
local stompFx = remotes:WaitForChild("StompFx")
local saveSettings = remotes:WaitForChild("SaveSettings")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local POPUP_HOLD_TIME = 2.5 -- how long the result stays on screen
local BIG_REVEAL_ONE_IN = 1000 -- the rare chime at this rarity or rarer
local FLASH_REVEAL_ONE_IN = 100 -- this rare or rarer: 0.35s camera shake, color flash and a low impact
local AUTO_ROLL_INTERVAL = 1.5 -- seconds between auto-rolls
local FAST_AUTO_ROLL_INTERVAL = 0.75 -- with the Fast Roll pass
local GLYPH_MIN_SCALE = 50 -- characters this big get a spinning glyph on the ground under them
local FOOTSTEP_MIN_SCALE = 10 -- characters this big (or bigger) shake the ground
local SHOCKWAVE_MIN_SCALE = 150 -- god tiers send a shockwave ring out on every footstep
local STOMP_MIN_SCALE = 50 -- F key / STOMP button
local VIEWPORT_MIN_SCALE = 10 -- V key / VIEW button
local CAMERA_ZOOM_PER_SCALE = 35 -- max zoom = scale x 35, kept between the two limits below
local CAMERA_MAX_ZOOM_LOW = 128
local CAMERA_MAX_ZOOM_HIGH = 5000
local CAMERA_MIN_ZOOM = 0.5
local CAMERA_PUSH_MIN_SCALE = 5 -- past this size the camera is kept outside the body...
local BODY_CLEARANCE = 4.2 -- ...this many studs per 1x of scale (a 1x body's bounding box, from the head)
local CAMERA_GLIDE_TIME = 0.6
local HIGH_TIER_MIN_SCALE = 35 -- Colossus and up get the cinematic reveal sound

-- Sound effects: Roblox UI sounds and Roblox-licensed Pro Sound Effects /
-- APM Music audio. Empty string = no sound. Every UI / result sound plays
-- as a 2D sound (SoundService:PlayLocalSound), and each one here was
-- measured to be balanced left/right, so it lands dead-center in both ears.
local SOUNDS = {
	tick = "rbxassetid://15675059323", -- each step of the roll spin and the Growth Spinner (Roblox UI bright click)
	reveal = "rbxassetid://15675085146", -- normal result (Roblox UI indicator chime)
	rare = "rbxassetid://1841209900", -- 1 in 1,000+ reveal / server announcement (APM "Cheerful Chimes")
	drop = "rbxassetid://9126009582", -- Colossus+ reveal: sub-bass drop (Pro Sound Effects subwoofer impact)
	riser = "rbxassetid://9125635285", -- Colossus+ reveal: shimmer on top (Pro Sound Effects sparkling chimes)
	click = "rbxassetid://15675059323", -- UI buttons (Roblox UI bright click)
	footstep = "rbxassetid://9126009589", -- giant footsteps (Pro Sound Effects subwoofer impact, pitched down + reverb)
	stomp = "rbxassetid://9043341776", -- Titan Stomp: sub-bass shockwave boom (APM "Sine Boom")
	launch = "rbxassetid://9113840530", -- Updraft Launcher whoosh (Pro Sound Effects)
}
-- Sounds that get a reverb tail in the world.
local REVERB_SOUNDS = { footstep = true, stomp = true }
-- Background music: Roblox-licensed tracks (DistroKid), shuffled without
-- repeats and crossfaded. gain evens out how loud each track was mastered.
local MUSIC = {
	{ id = "rbxassetid://136995974791747", gain = 1 }, -- Memories Beyond the Journey (anime lo-fi)
	{ id = "rbxassetid://89791562526654", gain = 1 }, -- Dreaming of Vinland (anime lo-fi)
	{ id = "rbxassetid://139421275515323", gain = 1.15 }, -- Neon Skyline (synthwave)
	{ id = "rbxassetid://121013346303842", gain = 0.85 }, -- Electronic Palm Shadows (synthwave)
	{ id = "rbxassetid://138551890276730", gain = 0.7 }, -- Adrenaline Arcade Synthwave
	{ id = "rbxassetid://140486290054589", gain = 1.6 }, -- Insert Coin (synthwave)
}
local MUSIC_VOLUME = 0.15
local MUSIC_CROSSFADE = 1 -- seconds

-- The player's SETTINGS (loaded from their save, see AUDIO & SETTINGS).
local settings = { music = true, sfx = true, lowGfx = false }

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

-- Menus (Index, Shop, Settings) open and close with a quick 0.2s slide +
-- grow (Quad, Out). Each panel remembers its normal position and size.
local PANEL_TIME = 0.2
local panelHome = {} -- [panel] = { position, size, uiScale, open, token }
local function setPanelOpen(panel, open)
	local home = panelHome[panel]
	if not home then
		home = { position = panel.Position, size = panel.Size, open = false, token = 0 }
		home.uiScale = make("UIScale", { Parent = panel })
		panelHome[panel] = home
	end
	if home.open == open then
		return
	end
	home.open = open
	home.token += 1
	local token = home.token
	local shrunk = UDim2.new(home.size.X.Scale * 0.9, home.size.X.Offset * 0.9, home.size.Y.Scale * 0.9, home.size.Y.Offset * 0.9)
	local lowered = home.position + UDim2.fromOffset(0, 24)
	if open then
		panel.Position, panel.Size, home.uiScale.Scale = lowered, shrunk, 0.9
		panel.Visible = true
		panel:TweenSizeAndPosition(home.size, home.position, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, PANEL_TIME, true)
		tween(home.uiScale, PANEL_TIME, { Scale = 1 })
	else
		panel:TweenSizeAndPosition(shrunk, lowered, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, PANEL_TIME, true)
		tween(home.uiScale, PANEL_TIME, { Scale = 0.9 })
		task.delay(PANEL_TIME, function()
			if home.token == token then
				panel.Visible = false
			end
		end)
	end
end

local function isPanelOpen(panel)
	return panelHome[panel] ~= nil and panelHome[panel].open
end

local soundCache = {}
local function playSound(name, volume, speed)
	local id = SOUNDS[name]
	if not id or id == "" or not settings.sfx then
		return
	end
	local sound = soundCache[name]
	if not sound then
		sound = make("Sound", { SoundId = id, Parent = SoundService })
		soundCache[name] = sound
	end
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = speed or 1
	SoundService:PlayLocalSound(sound)
end

-- A sound in the world (louder when you're closer), e.g. footsteps and stomps.
local function play3D(name, parent, volume, speed, rollMin, rollMax)
	local id = SOUNDS[name]
	if not id or id == "" or not settings.sfx then
		return
	end
	local sound = make("Sound", {
		SoundId = id,
		Volume = volume,
		PlaybackSpeed = speed,
		RollOffMinDistance = rollMin,
		RollOffMaxDistance = rollMax,
		Parent = parent,
	})
	if REVERB_SOUNDS[name] then
		make("ReverbSoundEffect", { DecayTime = 2.5, Density = 1, Diffusion = 1, DryLevel = 0, WetLevel = -4, Parent = sound })
	end
	sound:Play()
	task.delay(6, sound.Destroy, sound)
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

-- Compact "🍀 1.2x LUCK (i)" pill above the status line. The breakdown of
-- active boosts shows in a tooltip on hover, or on click / tap (pins it open).
local luckPill = make("TextButton", {
	Name = "LuckPill",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -142),
	Size = UDim2.new(0, 0, 0, 28),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.35,
	AutoButtonColor = false,
	Text = "",
	Parent = gui,
}, {
	corner(14),
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 6) }),
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local luckLabel = make("TextLabel", {
	LayoutOrder = 1,
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "🍀 1x LUCK",
	Parent = luckPill,
})
make("TextLabel", { -- the info icon
	LayoutOrder = 2,
	Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.8,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "i",
	Parent = luckPill,
}, { corner(9) })
local luckTooltip = make("TextLabel", {
	Name = "LuckTooltip",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -176),
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundColor3 = Color3.fromRGB(20, 20, 30),
	BackgroundTransparency = 0.15,
	Font = FONT,
	RichText = true,
	TextSize = 15,
	LineHeight = 1.15,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
	ZIndex = 5,
	Parent = gui,
}, {
	corner(10),
	stroke(1.5, Color3.fromRGB(120, 255, 150)),
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}),
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
	return math.clamp(12.5 * scale, 0.6, CAMERA_MAX_ZOOM_HIGH)
end

-- Max zoom grows with size (128 up to 3.6x, 7000 -> capped 5000 at World Eater).
-- Min zoom is 0.5 (first person), but past 5x the camera is pushed back
-- outside the avatar's bounding box, so it never ends up in a giant's head or torso.
local function cameraLimits(scale)
	local maxZoom = math.clamp(scale * CAMERA_ZOOM_PER_SCALE, CAMERA_MAX_ZOOM_LOW, CAMERA_MAX_ZOOM_HIGH)
	local minZoom = CAMERA_MIN_ZOOM
	if scale > CAMERA_PUSH_MIN_SCALE then
		minZoom = BODY_CLEARANCE * scale
	end
	return math.min(minZoom, maxZoom), maxZoom
end

-- Giants: aim the camera above and a little behind the head, so their own
-- torso sits low and small instead of filling the middle of the screen.
-- (shake() adds its wobble on top of this.)
local cameraBaseOffset = Vector3.zero
local function giantCameraOffset(scale)
	if scale < 2 then
		return Vector3.zero
	end
	return Vector3.new(0, 0.8 * scale, 1 * scale)
end

-- The camera glides to its new zoom: min and max zoom are pinned together
-- and tweened from where the camera is now to the target, then released.
-- snap = also zoom to fit the new size; otherwise it only moves if the
-- current zoom is outside the new limits (e.g. pushed out of a giant's body).
local zoomGlide = nil
local function applyCamera(snap)
	local scale = player:GetAttribute("HeightScale") or 1
	local minZoom, maxZoom = cameraLimits(scale)
	cameraBaseOffset = giantCameraOffset(scale)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = cameraBaseOffset
	end
	if zoomGlide then
		zoomGlide:Cancel()
		zoomGlide = nil
	end
	local camera = workspace.CurrentCamera
	local current = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	local target = math.clamp(snap and zoomFor(scale) or current, minZoom, maxZoom)
	if math.abs(target - current) < 0.5 then
		player.CameraMaxZoomDistance = maxZoom
		player.CameraMinZoomDistance = minZoom
		return
	end
	local pin = Instance.new("NumberValue")
	pin.Value = current
	pin.Changed:Connect(function(zoom)
		player.CameraMaxZoomDistance = zoom
		player.CameraMinZoomDistance = zoom
	end)
	local glide = TweenService:Create(pin, TweenInfo.new(CAMERA_GLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
	glide.Completed:Connect(function(state)
		pin:Destroy()
		if state == Enum.PlaybackState.Completed then
			zoomGlide = nil
			player.CameraMaxZoomDistance = maxZoom
			player.CameraMinZoomDistance = minZoom
		end
	end)
	zoomGlide = glide
	glide:Play()
end

-- No tripping, no ragdolls: big falls and launches never knock the
-- character over (Roblox has no fall damage, so landings are always safe).
local function setupHumanoid(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
end

player:GetAttributeChangedSignal("HeightScale"):Connect(function()
	refreshStatus()
	applyCamera(true)
end)
player:GetAttributeChangedSignal("BestTier"):Connect(refreshStatus)
player.CharacterAdded:Connect(function(character)
	setupHumanoid(character)
	task.delay(1.5, applyCamera, true) -- after the server re-sizes the new body
end)
if player.Character then
	task.spawn(setupHumanoid, player.Character)
end
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
-- Rare-roll screen flash: a ColorCorrection tint in the tier's color that
-- fades out (a local effect: only this player's screen).
local flashCorrection = make("ColorCorrectionEffect", {
	Name = "RollFlash",
	Enabled = false,
	Parent = game:GetService("Lighting"),
})
local flashTween = nil

local function doFlash(color, duration)
	duration = duration or 0.35
	if flashTween then
		flashTween:Cancel()
	end
	flashCorrection.TintColor = Color3.new(1, 1, 1):Lerp(color, 0.65)
	flashCorrection.Brightness = 0.3
	flashCorrection.Saturation = 0.25
	flashCorrection.Enabled = true
	flashTween = tween(flashCorrection, duration, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Saturation = 0 })
	flashTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			flashCorrection.Enabled = false
		end
	end)
end

-- Camera shake: smooth Perlin-noise wobble (not random jitter) that fades out.
local shakeSeed = 0
local function shake(duration, strength)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	-- Scale the shake to how far the camera is, so giants feel it too.
	local amount = strength * zoomFor(player:GetAttribute("HeightScale") or 1) / 12.5
	shakeSeed += 10
	local seed = shakeSeed
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= duration or not humanoid.Parent then
			humanoid.CameraOffset = cameraBaseOffset
			connection:Disconnect()
			return
		end
		local fade = (1 - t / duration) ^ 2
		local n = t * 18 -- noise frequency
		humanoid.CameraOffset = cameraBaseOffset + Vector3.new(
			math.noise(n, seed, 0.5),
			math.noise(seed, n, 1.5),
			math.noise(seed + 3, 2.5, n) * 0.5
		) * amount * fade
	end)
end

local function pop(fromScale, time)
	popupScale.Scale = fromScale
	tween(popupScale, time, { Scale = 1 }, Enum.EasingStyle.Back)
end

---------------------------------------------------------------------
-- TIER EFFECTS drawn on this screen only (not replicated): the spinning
-- ground glyph under 50x+ characters, the orbiting void around "Super",
-- footstep and stomp shockwaves, flickering arcs and pulsing lights.
-- Low GFX mode skips other players' effects.
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

local GLYPH_TRANSPARENCY = 0.4

local function buildOrbiters(aura, scale)
	local parts, specs = {}, {}
	if scale >= GLYPH_MIN_SCALE then
		-- flat neon magic circle on the ground: an outer ring and a six-sided
		-- star, counter-spinning (violet for the Super aura, cyan/gold otherwise)
		local super = aura == "Super"
		for i = 1, 16 do
			table.insert(parts, effectPart({
				Size = Vector3.new(0.9 * scale, 0.2, 0.12 * scale),
				Material = Enum.Material.Neon,
				Color = super and Color3.fromRGB(150, 80, 255) or Color3.fromRGB(150, 220, 255),
				Transparency = GLYPH_TRANSPARENCY,
			}))
			table.insert(specs, { ground = true, radius = 2.2 * scale, angle = i / 16 * math.pi * 2, speed = 0.5 })
		end
		for i = 1, 6 do
			table.insert(parts, effectPart({
				Size = Vector3.new(1.9 * scale, 0.2, 0.1 * scale),
				Material = Enum.Material.Neon,
				Color = super and Color3.fromRGB(255, 60, 110) or Color3.fromRGB(255, 220, 120),
				Transparency = GLYPH_TRANSPARENCY,
			}))
			table.insert(specs, { ground = true, radius = 1.1 * scale, angle = i / 6 * math.pi * 2, speed = -0.8 })
		end
	end
	if aura == "Super" then
		-- orbiting void: two tilted rings of dark violet orbs
		for ring = 1, 2 do
			for i = 1, 18 do
				table.insert(parts, effectPart({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.3 * scale,
					Material = Enum.Material.Neon,
					Color = ring == 1 and Color3.fromRGB(120, 60, 200) or Color3.fromRGB(70, 30, 130),
					Transparency = 0.35,
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
		local skip = settings.lowGfx and other ~= player
		if o and (skip or o.character ~= character or o.aura ~= aura or math.abs(o.scale - scale) > 0.01) then
			clearOrbiters(other)
			o = nil
		end
		if not o and not skip and aura and (scale >= GLYPH_MIN_SCALE or aura == "Super") then
			local parts, specs = buildOrbiters(aura, scale)
			o = { character = character, aura = aura, scale = scale, parts = parts, specs = specs, t = 0 }
			orbiters[other] = o
		end
		if o and root then
			o.t += dt
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local groundY = root.Position.Y - root.Size.Y / 2 - (humanoid and humanoid.HipHeight or 0) + 0.3
			local airborne = humanoid and humanoid.FloorMaterial == Enum.Material.Air
			for i, part in ipairs(o.parts) do
				local spec = o.specs[i]
				local a = spec.angle + o.t * spec.speed
				if spec.ground then
					-- lying flat on the ground, along the circle; hidden while jumping / falling
					local pos = Vector3.new(root.Position.X + math.cos(a) * spec.radius, groundY, root.Position.Z + math.sin(a) * spec.radius)
					part.CFrame = CFrame.new(pos) * CFrame.Angles(0, -a - math.pi / 2, 0)
					part.Transparency = airborne and 1 or GLYPH_TRANSPARENCY
				else
					local offset = CFrame.Angles(spec.tilt, 0, 0) * Vector3.new(math.cos(a) * spec.radius, 0, math.sin(a) * spec.radius)
					part.CFrame = CFrame.new(root.Position + offset)
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(clearOrbiters)

-- Every 0.1s the lightning arcs jump to a new random pair of limbs and
-- re-bend (crackle), outlines pulse between their two colors and Super
-- auras' lights pulse. Low GFX mode switches off other players' aura
-- particles and lights, and every Beam and Highlight (yours too).
local crackleRng = Random.new()
local function setAuraEnabled(obj, enabled)
	if obj:IsA("ParticleEmitter") or obj:IsA("Light") then
		obj.Enabled = enabled
	end
end

local function arcPointsOf(character)
	local points = {}
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("Attachment") and obj:GetAttribute("ArcPoint") then
			table.insert(points, obj)
		end
	end
	return points
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local now = os.clock()
		for _, other in ipairs(Players:GetPlayers()) do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local show = not (settings.lowGfx and other ~= player)
				local showBeams = not settings.lowGfx
				local points = nil
				for _, obj in ipairs(root:GetChildren()) do
					if obj.Name == "HeightAura" then
						if obj:IsA("Beam") then
							local s = obj:GetAttribute("Crackle") or 1
							points = points or arcPointsOf(character)
							if #points >= 2 then
								local a = crackleRng:NextInteger(1, #points)
								local b = crackleRng:NextInteger(1, #points - 1)
								if b >= a then
									b += 1
								end
								obj.Attachment0, obj.Attachment1 = points[a], points[b]
							end
							obj.CurveSize0 = crackleRng:NextNumber(-1.5, 1.5) * s
							obj.CurveSize1 = crackleRng:NextNumber(-1.5, 1.5) * s
							obj.TextureSpeed = crackleRng:NextNumber(2, 6)
							obj.Enabled = showBeams and crackleRng:NextNumber() < 0.85
						elseif obj:IsA("PointLight") and obj:GetAttribute("Pulse") then
							obj.Brightness = 2 + 1.5 * math.sin(now * 4)
							obj.Enabled = show
						else
							setAuraEnabled(obj, show)
							for _, child in ipairs(obj:GetChildren()) do
								setAuraEnabled(child, show)
							end
						end
					end
				end
				local highlight = character:FindFirstChild("HeightAura")
				if highlight and highlight:IsA("Highlight") then
					highlight.Enabled = showBeams
					local a, b = highlight:GetAttribute("OutlineA"), highlight:GetAttribute("OutlineB")
					if a and b then
						highlight.OutlineColor = a:Lerp(b, 0.5 + 0.5 * math.sin(now * 2.5))
					end
				end
			end
		end
	end
end)

-- An expanding, fading ring on the ground (footsteps, stomps).
local function spawnShockwave(position, scale, reach, color)
	local ring = effectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, scale * 0.5, scale * 0.5),
		CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = color or Color3.fromRGB(200, 170, 255),
		Transparency = 0.5,
	})
	tween(ring, 1.2, { Size = Vector3.new(0.4, scale * reach, scale * reach), Transparency = 1 })
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
			-- stride grows with size, speed is capped: bigger = slower steps (max 4s apart)
			local interval = math.min(0.35 * scale * 16 / math.max(humanoid.WalkSpeed, 1), 4)
			local t = (stepTimers[other] or interval) + dt
			if t >= interval then
				t = 0
				if scale >= SHOCKWAVE_MIN_SCALE and not (settings.lowGfx and other ~= player) then
					local groundY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
					spawnShockwave(Vector3.new(root.Position.X, groundY, root.Position.Z), scale, 10)
				end
				local range = scale * 12
				local distance = (root.Position - myRoot.Position).Magnitude
				if distance < range then
					local closeness = 1 - distance / range
					play3D("footstep", root, 0.6 + 0.6 * closeness, math.clamp(0.75 - scale / 500, 0.45, 0.75), scale * 2, range)
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
		playSound("tick", 0.4, 1.1 + math.random() * 0.15)
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
	local hype = rarity >= FLASH_REVEAL_ONE_IN
	if hype then
		-- 0.35s cinematic pulse in the tier's color; harder for rarer tiers
		doFlash(tier.color, 0.35)
		shake(0.35, tier.scale >= HIGH_TIER_MIN_SCALE and 1.6 or rarity >= BIG_REVEAL_ONE_IN and 1.2 or 0.8)
	end
	if tier.scale >= HIGH_TIER_MIN_SCALE then
		playSound("drop", 1, 0.85)
		playSound("riser", 0.7)
	else
		if hype then
			playSound("drop", 0.6, 0.7) -- low-frequency impact under the chime
		end
		if rarity >= BIG_REVEAL_ONE_IN then
			playSound("rare", 0.6)
		else
			playSound("reveal", hype and 0.6 or 0.45)
		end
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
	local active = type(info.parts) == "table" and #info.parts > 0
	luckLabel.Text = "🍀 " .. formatLuck(info.total or 1) .. " LUCK"
	luckLabel.TextColor3 = active and Color3.fromRGB(120, 255, 150) or Color3.new(1, 1, 1)
	local lines = { "<b>Luck " .. formatLuck(info.total or 1) .. "</b>" }
	if active then
		for _, part in ipairs(info.parts) do
			table.insert(lines, "•  " .. escapeRichText(tostring(part)))
		end
	else
		table.insert(lines, '<font color="#AAAAB4">No boosts active</font>')
	end
	luckTooltip.Text = table.concat(lines, "\n")
end
player:GetAttributeChangedSignal("LuckInfo"):Connect(refreshLuck)
refreshLuck()

-- Tooltip: shows while hovering, a click / tap pins it open (click again to close).
local tooltipPinned = false
local function refreshTooltip(hovering)
	luckTooltip.Visible = tooltipPinned or hovering
end
luckPill.MouseEnter:Connect(function()
	refreshTooltip(true)
end)
luckPill.MouseLeave:Connect(function()
	refreshTooltip(false)
end)
luckPill.Activated:Connect(function()
	tooltipPinned = not tooltipPinned
	refreshTooltip(tooltipPinned)
end)

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

-- Every row is color-coded by rarity class (RarityTable.Classes): grey
-- Common, blue Rare, purple Epic, gold Colossal, prismatic violet/red Mythic.
local ROW_BASE = Color3.fromRGB(30, 30, 46)
local function prismatic(class)
	return make("UIGradient", { Color = ColorSequence.new(class.color, class.color2), Rotation = 0 })
end

local indexRows = {} -- [tierId] = { name, info, button, canEquip, class }
for order, id in ipairs(indexOrder) do
	local class = RarityTable.ClassOf(id)
	local rowStroke = stroke(2, class.color2 and Color3.new(1, 1, 1) or class.color)
	local row = make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, 54),
		BackgroundColor3 = class.color2 and Color3.new(1, 1, 1) or ROW_BASE:Lerp(class.color, 0.22),
		Parent = indexList,
	}, { corner(10), rowStroke })
	if class.color2 then
		-- Mythic: a dark violet -> red background and a prismatic border
		make("UIGradient", {
			Color = ColorSequence.new(ROW_BASE:Lerp(class.color, 0.35), ROW_BASE:Lerp(class.color2, 0.35)),
			Parent = row,
		})
		prismatic(class).Parent = rowStroke
	end
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
		class = class,
	}
	if class.color2 then
		prismatic(class).Parent = entry.name
	end
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
		local class = entry.class
		-- the name takes its rarity color (Mythic: white text under the prismatic gradient)
		local classColor = class.color2 and Color3.new(1, 1, 1) or class.color
		if scale then
			found += 1
			entry.name.Text = tier.name:upper()
			entry.name.TextColor3 = classColor
			entry.info.Text = ("%s  •  %s  •  best %s"):format(class.name:upper(), RarityTable.FormatOdds(id), RarityTable.FormatScale(scale))
			entry.button.Visible = true
			entry.canEquip = id ~= current
			entry.button.Text = entry.canEquip and "EQUIP" or "EQUIPPED"
			entry.button.BackgroundColor3 = entry.canEquip and Color3.fromRGB(50, 200, 110) or Color3.fromRGB(80, 80, 100)
			entry.button.AutoButtonColor = entry.canEquip
		else
			entry.name.Text = "???"
			entry.name.TextColor3 = classColor:Lerp(Color3.fromRGB(60, 60, 75), 0.45)
			entry.info.Text = ("%s  •  Not discovered yet"):format(class.name:upper())
			entry.button.Visible = false
			entry.canEquip = false
		end
	end
	indexTitle.Text = ("INDEX   %d / %d found"):format(found, #Tiers)
end

indexButton.Activated:Connect(function()
	setPanelOpen(indexPanel, not isPanelOpen(indexPanel))
end)
closeButton.Activated:Connect(function()
	setPanelOpen(indexPanel, false)
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

-- The server launched us: a giant's foot (Crush Pit), a stomp, or a Wind
-- Launcher. No damage. With flightTime we hold the arc for that long, because
-- the character would otherwise brake itself in mid-air.
bounce.OnClientEvent:Connect(function(velocity, flightTime, kind)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		return
	end
	if kind == "launch" then
		playSound("launch")
	else
		shake(0.3, 0.6)
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	root.AssemblyLinearVelocity = velocity
	if flightTime then
		local start = os.clock()
		local gravity = workspace.Gravity
		local connection
		connection = RunService.Heartbeat:Connect(function()
			local t = os.clock() - start
			if t >= flightTime or not root.Parent then
				connection:Disconnect()
				return
			end
			root.AssemblyLinearVelocity = velocity - Vector3.new(0, gravity * t, 0)
		end)
	end
end)

-- Someone 50x+ stomped: boom + shockwave where it hit, camera shake if we're close.
stompFx.OnClientEvent:Connect(function(position, scale)
	spawnShockwave(position, scale, 14, Color3.fromRGB(255, 220, 160))
	local holder = effectPart({ Size = Vector3.one, Transparency = 1, CFrame = CFrame.new(position) })
	play3D("stomp", holder, 1, 0.8, scale * 3, scale * 30)
	task.delay(6, holder.Destroy, holder)
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if myRoot then
		local range = scale * 20
		local distance = (myRoot.Position - position).Magnitude
		if distance < range then
			shake(0.6, 1.2 * (1 - distance / range))
		end
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
	{ key = "FastRoll", name = "Fast Roll", desc = "Halves your roll cooldown (0.65s instead of 1.3s), with a snappier spin. Auto-roll goes 2x faster.", color = Color3.fromRGB(80, 170, 255) },
	{ key = "VIP", name = "VIP Rank", desc = "+25% luck, a golden [VIP] tag over your head and a golden name in chat.", color = Color3.fromRGB(255, 215, 0) },
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
	setPanelOpen(shopPanel, not isPanelOpen(shopPanel))
	setPanelOpen(indexPanel, false)
end)
shopClose.Activated:Connect(function()
	setPanelOpen(shopPanel, false)
end)
indexButton.Activated:Connect(function()
	setPanelOpen(shopPanel, false) -- only one panel open at a time
end)

---------------------------------------------------------------------
-- GIANT CONTROLS: Ground Shaker Stomp (F, 50x+) and Colossal Viewport (V, 10x+)
---------------------------------------------------------------------
local function myScale()
	return player.Character and player.Character:GetScale() or 1
end

local function tryStomp()
	if myScale() < STOMP_MIN_SCALE then
		showToast(("Ground Shaker Stomp unlocks at %dx size"):format(STOMP_MIN_SCALE), Color3.fromRGB(190, 190, 205))
		return
	end
	stomp:FireServer()
end

-- Panoramic shoulder view: camera high above and behind the giant's shoulder,
-- looking out and down over the island.
local viewportOn = false
local viewportConnection = nil
local function setViewport(on)
	viewportOn = on
	local camera = workspace.CurrentCamera
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	if not on then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 85
	viewportConnection = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or character:GetScale() < VIEWPORT_MIN_SCALE then
			setViewport(false)
			return
		end
		local s = character:GetScale()
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
		local eye = root.Position + Vector3.new(0, 4.5 * s, 0) - look * 6 * s + root.CFrame.RightVector * 1.5 * s
		local focus = root.Position + look * 30 * s - Vector3.new(0, 3 * s, 0)
		camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(eye, focus), 0.15)
	end)
end

local function toggleViewport()
	if not viewportOn and myScale() < VIEWPORT_MIN_SCALE then
		showToast(("Colossal Viewport unlocks at %dx size"):format(VIEWPORT_MIN_SCALE), Color3.fromRGB(190, 190, 205))
		return
	end
	setViewport(not viewportOn)
end

-- On-screen buttons too (phones have no F / V keys); shown once you're big enough.
local function sideButton(text, y, color)
	return make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, y),
		Size = UDim2.new(0, 96, 0, 40),
		BackgroundColor3 = color,
		Font = FONT,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 18,
		Visible = false,
		Parent = gui,
	}, { corner(12), stroke(3, Color3.fromRGB(30, 30, 40)) })
end
local stompButton = sideButton("STOMP [F]", -120, Color3.fromRGB(200, 90, 50))
local viewButton = sideButton("VIEW [V]", -72, Color3.fromRGB(70, 110, 190))
stompButton.Activated:Connect(tryStomp)
viewButton.Activated:Connect(toggleViewport)
task.spawn(function()
	while true do
		local s = myScale()
		stompButton.Visible = s >= STOMP_MIN_SCALE
		viewButton.Visible = s >= VIEWPORT_MIN_SCALE
		task.wait(0.5)
	end
end)

-- Keyboard shortcuts: R to roll, F to stomp, V for the giant viewport
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		tryRoll()
	elseif input.KeyCode == Enum.KeyCode.F then
		tryStomp()
	elseif input.KeyCode == Enum.KeyCode.V then
		toggleViewport()
	end
end)

---------------------------------------------------------------------
-- AUDIO & SETTINGS: background music, MUTE, and the SETTINGS panel
-- (Music / SFX / Low GFX), saved with the player's data
---------------------------------------------------------------------
-- Two music players take turns: the next track fades in over the last
-- MUSIC_CROSSFADE seconds of the current one. Tracks are shuffled into a
-- "bag" and every track plays once before any repeats (never twice in a row).
local musicPlayers = {
	make("Sound", { Name = "BackgroundMusicA", Volume = 0, Parent = SoundService }),
	make("Sound", { Name = "BackgroundMusicB", Volume = 0, Parent = SoundService }),
}
local music = musicPlayers[1] -- the one playing now
local musicGain = 1
local musicBag = {}
local lastTrack = nil

local function drawTrack()
	if #musicBag == 0 then
		for _, track in ipairs(MUSIC) do
			table.insert(musicBag, track)
		end
		for i = #musicBag, 2, -1 do
			local j = math.random(i)
			musicBag[i], musicBag[j] = musicBag[j], musicBag[i]
		end
		if musicBag[#musicBag] == lastTrack and #musicBag > 1 then
			musicBag[1], musicBag[#musicBag] = musicBag[#musicBag], musicBag[1]
		end
	end
	lastTrack = table.remove(musicBag)
	return lastTrack
end

local crossfading = false
local function nextTrack()
	local track = drawTrack()
	local old = music
	music = old == musicPlayers[1] and musicPlayers[2] or musicPlayers[1]
	musicGain = track.gain
	music.SoundId = track.id
	music.TimePosition = 0
	music.Volume = 0
	if not settings.music then
		return
	end
	music:Play()
	crossfading = true
	tween(music, MUSIC_CROSSFADE, { Volume = MUSIC_VOLUME * musicGain }, Enum.EasingStyle.Sine)
	if old.IsPlaying then
		tween(old, MUSIC_CROSSFADE, { Volume = 0 }, Enum.EasingStyle.Sine)
		task.delay(MUSIC_CROSSFADE, function()
			if old ~= music then
				old:Stop()
			end
		end)
	end
	task.delay(MUSIC_CROSSFADE, function()
		crossfading = false
	end)
end

-- Start the next track a crossfade before this one ends.
RunService.Heartbeat:Connect(function()
	if crossfading or not settings.music or not music.IsPlaying then
		return
	end
	local length = music.TimeLength
	if length > MUSIC_CROSSFADE * 3 and music.TimePosition >= length - MUSIC_CROSSFADE then
		nextTrack()
	end
end)
for _, sound in ipairs(musicPlayers) do
	sound.Ended:Connect(function() -- safety net if a track ends before the crossfade started
		if sound == music and settings.music and not crossfading then
			nextTrack()
		end
	end)
end

-- Low GFX: no bloom / sun rays / depth of field / shadows / cloud mist on
-- this device (other players' auras are handled in TIER EFFECTS).
local lightingDefaults = {}
local function applyLowGfx()
	local lighting = game:GetService("Lighting")
	for _, effect in ipairs(lighting:GetChildren()) do
		if effect:IsA("PostEffect") and not effect:IsA("ColorCorrectionEffect") then
			if lightingDefaults[effect] == nil then
				lightingDefaults[effect] = effect.Enabled
			end
			effect.Enabled = lightingDefaults[effect] and not settings.lowGfx
		end
	end
	if lightingDefaults.shadows == nil then
		lightingDefaults.shadows = lighting.GlobalShadows
	end
	lighting.GlobalShadows = lightingDefaults.shadows and not settings.lowGfx
	local sky = workspace:FindFirstChild("MapSafety") and workspace.MapSafety:FindFirstChild("SkyRealm")
	for _, emitter in ipairs(sky and sky:GetDescendants() or {}) do
		if emitter:IsA("ParticleEmitter") and emitter.Name == "CloudMist" then
			emitter.Enabled = not settings.lowGfx
		end
	end
end

local GEAR_ICON = "rbxasset://textures/ui/Settings/MenuBarIcons/GameSettingsTab.png" -- Roblox's built-in gear

local muteButton = sideButton("MUTE", 24, Color3.fromRGB(90, 90, 110))
muteButton.Visible = true
local settingsButton = make("ImageButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, -24),
	Size = UDim2.new(0, 44, 0, 40),
	BackgroundColor3 = Color3.fromRGB(90, 90, 110),
	Image = "",
	Parent = gui,
}, {
	corner(12),
	stroke(3, Color3.fromRGB(30, 30, 40)),
	make("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 28, 0, 28),
		BackgroundTransparency = 1,
		Image = GEAR_ICON,
	}),
})

-- Modal: the screen dims behind the panel; clicking the dimmed area closes it.
local settingsBackdrop = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 24,
	Parent = gui,
})

local settingsPanel = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.45),
	Size = UDim2.new(0, 320, 0, 290),
	BackgroundColor3 = Color3.fromRGB(20, 20, 32),
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 25,
	Parent = gui,
}, { corner(16), stroke(3, Color3.fromRGB(70, 70, 110)) })
make("ImageLabel", {
	Position = UDim2.new(0, 14, 0, 12),
	Size = UDim2.new(0, 30, 0, 30),
	BackgroundTransparency = 1,
	Image = GEAR_ICON,
	Parent = settingsPanel,
})
make("TextLabel", {
	Position = UDim2.new(0, 52, 0, 10),
	Size = UDim2.new(1, -106, 0, 34),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 26,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "SETTINGS",
	Parent = settingsPanel,
})
make("TextLabel", {
	Position = UDim2.new(0, 20, 0, 228),
	Size = UDim2.new(1, -40, 0, 44),
	BackgroundTransparency = 1,
	Font = FONT,
	TextSize = 14,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Color3.fromRGB(150, 150, 170),
	Text = "Low GFX hides other players' auras, turns off beams, outlines and post-processing for a smooth 60 FPS on phones.",
	Parent = settingsPanel,
})
local settingsClose = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.new(0, 36, 0, 36),
	BackgroundColor3 = Color3.fromRGB(200, 60, 80),
	Font = FONT,
	Text = "X",
	TextSize = 22,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = settingsPanel,
}, { corner(10) })

local toggleButtons = {} -- [settingKey] = button
local function refreshSettingsUi()
	for key, button in pairs(toggleButtons) do
		button.Text = settings[key] and "ON" or "OFF"
		button.BackgroundColor3 = settings[key] and Color3.fromRGB(50, 200, 110) or Color3.fromRGB(80, 80, 100)
	end
	muteButton.Text = (settings.music or settings.sfx) and "MUTE" or "UNMUTE"
end

local function applySettings(save)
	if settings.music and not music.IsPlaying then
		if music.SoundId == "" then
			nextTrack()
		else
			music.Volume = MUSIC_VOLUME * musicGain
			music:Resume()
		end
	elseif not settings.music then
		for _, sound in ipairs(musicPlayers) do
			if sound == music then
				sound:Pause()
			else
				sound:Stop() -- a track that was fading out
			end
		end
	end
	applyLowGfx()
	refreshSettingsUi()
	if save then
		saveSettings:FireServer(settings)
	end
end

for row, entry in ipairs({ { "music", "Music" }, { "sfx", "SFX" }, { "lowGfx", "Low GFX Mode" } }) do
	local key, label = entry[1], entry[2]
	make("TextLabel", {
		Position = UDim2.new(0, 20, 0, 54 + (row - 1) * 60),
		Size = UDim2.new(1, -140, 0, 44),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(220, 220, 235),
		Text = label,
		Parent = settingsPanel,
	})
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 58 + (row - 1) * 60),
		Size = UDim2.new(0, 90, 0, 36),
		Font = FONT,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Parent = settingsPanel,
	}, { corner(10) })
	button.Activated:Connect(function()
		settings[key] = not settings[key]
		applySettings(true)
	end)
	toggleButtons[key] = button
end

local function setSettingsOpen(open)
	setPanelOpen(settingsPanel, open)
	if open then
		settingsBackdrop.Visible = true
	end
	tween(settingsBackdrop, PANEL_TIME, { BackgroundTransparency = open and 0.55 or 1 })
	task.delay(PANEL_TIME, function()
		if not isPanelOpen(settingsPanel) then
			settingsBackdrop.Visible = false
		end
	end)
end
settingsButton.Activated:Connect(function()
	setSettingsOpen(not isPanelOpen(settingsPanel))
end)
settingsClose.Activated:Connect(function()
	setSettingsOpen(false)
end)
settingsBackdrop.Activated:Connect(function()
	setSettingsOpen(false)
end)
muteButton.Activated:Connect(function()
	local anyOn = settings.music or settings.sfx
	settings.music = not anyOn
	settings.sfx = not anyOn
	applySettings(true)
end)

-- Load the saved choices once the server sends them (start with defaults until then).
local function loadSettings()
	local ok, saved = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Settings") or "")
	if ok and type(saved) == "table" then
		for key in pairs(settings) do
			if type(saved[key]) == "boolean" then
				settings[key] = saved[key]
			end
		end
	end
	applySettings(false)
end
player:GetAttributeChangedSignal("Settings"):Connect(loadSettings)
loadSettings()

---------------------------------------------------------------------
-- GROWTH SPINNER ticks: a click each time a slice passes the pointer,
-- and energy ripples running across the platform floor while it spins
---------------------------------------------------------------------
task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby", 30)
	local spinner = lobby and lobby:WaitForChild("GrowthSpinner", 30)
	local platform = spinner and spinner:WaitForChild("Platform", 30)
	if spinner and platform then
		spinner:GetAttributeChangedSignal("SpinStarted"):Connect(function()
			if settings.lowGfx then
				return
			end
			local radius = math.max(platform.Size.Y, platform.Size.Z) / 2
			local center = platform.Position + Vector3.new(0, platform.Size.X / 2, 0)
			for _, delay in ipairs({ 0, 0.35, 0.7, 1.6, 2.6 }) do
				task.delay(delay, spawnShockwave, center, 2, radius, Color3.fromRGB(170, 140, 255))
			end
		end)
	end
	local hub = spinner and spinner:WaitForChild("Hub", 30)
	local base = spinner and spinner:GetAttribute("BaseCFrame")
	if not (hub and base) then
		return
	end
	local untilt = CFrame.Angles(0, math.rad(-90), 0)
	local lastTile = nil
	RunService.Heartbeat:Connect(function()
		local _, _, angle = base:ToObjectSpace(hub.CFrame * untilt):ToEulerAnglesXYZ()
		local tile = math.floor(angle / (2 * math.pi / 100))
		if lastTile and tile ~= lastTile then
			play3D("tick", hub, 0.6, 1.3, 10, 150)
		end
		lastTile = tile
	end)
end)

---------------------------------------------------------------------
-- SPINNING SKY DECOR (models tagged "SkySpin", attributes SpinAxis + SpinSpeed):
-- astrolabe rings, crystal rings and the throne crown turn slowly. Each
-- client turns them locally, so it costs the server nothing.
---------------------------------------------------------------------
local CollectionService = game:GetService("CollectionService")
local skySpinners = {} -- [model] = its original pivot
local function trackSkySpinner(model)
	if model:IsA("Model") then
		skySpinners[model] = model:GetPivot()
	end
end
for _, model in ipairs(CollectionService:GetTagged("SkySpin")) do
	trackSkySpinner(model)
end
CollectionService:GetInstanceAddedSignal("SkySpin"):Connect(trackSkySpinner)
CollectionService:GetInstanceRemovedSignal("SkySpin"):Connect(function(model)
	skySpinners[model] = nil
end)
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, base in pairs(skySpinners) do
		local axis = model:GetAttribute("SpinAxis") or Vector3.yAxis
		local speed = model:GetAttribute("SpinSpeed") or 0.2
		model:PivotTo(base * CFrame.fromAxisAngle(axis, t * speed))
	end
end)

---------------------------------------------------------------------
-- UI click sound on every button
---------------------------------------------------------------------
local function hookClick(obj)
	if obj:IsA("GuiButton") then
		obj.Activated:Connect(function()
			playSound("click", 0.35)
		end)
	end
end
for _, obj in ipairs(gui:GetDescendants()) do
	hookClick(obj)
end
gui.DescendantAdded:Connect(hookClick)

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
	-- chat gets the rarity class in its color first: "[EPIC] Name rolled ..."
	local class = RarityTable.ClassOf(tierId)
	postToChat(colored("<b>[" .. class.name:upper() .. "]</b>", class.color) .. " " .. text)
	if displayName ~= player.DisplayName then
		playSound("rare", 0.5)
	end

	task.delay(4, function()
		if bannerToken == myToken then
			tween(banner, 0.3, { Position = UDim2.new(0.5, 0, 0, -100) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
end)

---------------------------------------------------------------------
-- VIP CHAT TAG: golden [VIP] tag and golden name on VIP players' chat messages
---------------------------------------------------------------------
TextChatService.OnIncomingMessage = function(message)
	local properties = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("VIP") then
		properties.PrefixText = '<font color="#FFD700"><b>[VIP]</b> ' .. message.PrefixText .. "</font>"
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
