--[[
	RarityTable  (ModuleScript)
	Goes in: ReplicatedStorage   Name it exactly: RarityTable

	Every height tier in the game lives here. The server reads it to roll,
	the client reads it to draw popups, so it sits in ReplicatedStorage
	where both sides can see it.

	To rebalance the game you only ever need to edit the Tiers list below.

	Tier fields:
	  name     - big name in the popup
	  title    - flavour text under the name
	  scale    - height multiplier (1 = normal Roblox size)
	  oneIn    - odds, "1 in N". Leave it out (nil) for exactly ONE tier:
	             that tier gets whatever chance is left over.
	  color    - main color for text and the aura
	  aura     - character effect. By bracket: "Earth" (small/common, earth-tone motes),
	             "Ki" (10x+, outline + rising flames), "Lightning" (Colossus and up:
	             crackling arcs + spinning ground glyph), "Super" (World Eater: cosmic
	             pillars, orbiting void, pulsing light, dark arcs, footstep shockwaves).
	             Tiny rare tiers keep their own: "Sparkles", "Glow", "Cosmic". Or "None".
	  announce - true = the whole server gets a banner when someone rolls it
]]

local RarityTable = {}

-- Height of a 1x character, used for the "6 ft 2 in" text.
RarityTable.BASE_HEIGHT_FEET = 5.75

-- Luck boosts only multiply tiers this rare or rarer (1 in 100+), so commons
-- stay balanced. Works cleanly up to about 25x luck.
RarityTable.LUCK_MIN_ONE_IN = 100

-- Common tiers wiggle +/- 6% so two "Tall" rolls aren't identical.
-- Tiers rarer than COMMON_ONE_IN_LIMIT are always exact (World Eater is always 200x).
RarityTable.COMMON_VARIATION = 0.06
RarityTable.COMMON_ONE_IN_LIMIT = 100

local rgb = Color3.fromRGB

-- Ordered smallest to tallest.
RarityTable.Tiers = {
	{ name = "Quantum",        title = "Smaller Than Physics", scale = 0.02, oneIn = 500000,  color = rgb(190, 120, 255), aura = "Cosmic",   announce = true },
	{ name = "Microbe",        title = "Germ of Legend",       scale = 0.05, oneIn = 50000,   color = rgb(90, 255, 140),  aura = "Glow",     announce = true },
	{ name = "Ant",            title = "Tiny Terror",          scale = 0.1,  oneIn = 5000,    color = rgb(255, 150, 70),  aura = "Glow",     announce = true },
	{ name = "Mouse",          title = "Cheese Seeker",        scale = 0.2,  oneIn = 750,     color = rgb(215, 215, 230), aura = "Sparkles", announce = false },
	-- small / common tiers: muted earth tones
	{ name = "Pebble",         title = "Kickable",             scale = 0.4,  oneIn = 60,      color = rgb(150, 145, 135), aura = "Earth",    announce = false },
	{ name = "Pocket-Sized",   title = "Fits in a Backpack",   scale = 0.65, oneIn = 15,      color = rgb(150, 185, 130), aura = "Earth",    announce = false },
	{ name = "Shorty",         title = "Fun-Sized",            scale = 0.85, oneIn = 5,       color = rgb(200, 175, 140), aura = "Earth",    announce = false },
	{ name = "Average",        title = "Perfectly Normal",     scale = 1,    oneIn = nil,     color = rgb(225, 215, 195), aura = "Earth",    announce = false },
	{ name = "Tall",           title = "Top Shelf Reacher",    scale = 1.15, oneIn = 5,       color = rgb(165, 195, 150), aura = "Earth",    announce = false },
	{ name = "Lanky",          title = "All Legs",             scale = 1.35, oneIn = 10,      color = rgb(175, 170, 110), aura = "Earth",    announce = false },
	{ name = "Towering",       title = "Door Ducker",          scale = 1.75, oneIn = 30,      color = rgb(190, 130, 90),  aura = "Earth",    announce = false },
	{ name = "Tree",           title = "Walking Timber",       scale = 2.5,  oneIn = 120,     color = rgb(110, 150, 80),  aura = "Earth",    announce = false },
	{ name = "Giant",          title = "Fee-Fi-Fo-Fum",        scale = 4,    oneIn = 400,     color = rgb(215, 180, 120), aura = "Earth",    announce = false },
	{ name = "Lighthouse",     title = "Beacon of the Coast",  scale = 7,    oneIn = 1500,    color = rgb(255, 240, 150), aura = "Glow",     announce = true },
	-- mid tiers (10x+): cyan / gold ki
	{ name = "Skyscraper",     title = "Cloud Scraper",        scale = 12,   oneIn = 6000,    color = rgb(70, 200, 255),  aura = "Ki",        announce = true },
	{ name = "Mountain",       title = "Peak Performer",       scale = 20,   oneIn = 25000,   color = rgb(255, 200, 70),  aura = "Ki",        announce = true },
	-- giant tiers (Colossus and up): lightning
	{ name = "Colossus",       title = "Earth Shaker",         scale = 35,   oneIn = 80000,   color = rgb(120, 210, 255), aura = "Lightning", announce = true },
	{ name = "Storm Titan",    title = "Lord of Thunder",      scale = 60,   oneIn = 200000,  color = rgb(255, 120, 50),  aura = "Lightning", announce = true },
	{ name = "Planet Breaker", title = "Moon Kicker",          scale = 100,  oneIn = 400000,  color = rgb(160, 90, 230),  aura = "Lightning", announce = true },
	-- god tier (150x+)
	{ name = "World Eater",    title = "Devourer of Worlds",   scale = 200,  oneIn = 1000000, color = rgb(255, 20, 60),   aura = "Super",     announce = true },
}

local Tiers = RarityTable.Tiers

-- Lookups built once from the list above.
RarityTable.ByName = {}
local rollOrder = {} -- ids of every tier with odds, rarest first
local fallbackId = nil

for id, tier in ipairs(Tiers) do
	tier.id = id
	RarityTable.ByName[tier.name] = tier
	if tier.oneIn then
		table.insert(rollOrder, id)
	else
		assert(fallbackId == nil, "RarityTable: only one tier may have no oneIn")
		fallbackId = id
	end
end
assert(fallbackId, "RarityTable: one tier needs oneIn = nil to be the fallback")
table.sort(rollOrder, function(a, b)
	return Tiers[a].oneIn > Tiers[b].oneIn
end)

RarityTable.FallbackId = fallbackId

-- The exact height multiplier for a tier (adds the small wiggle to commons).
function RarityTable.ScaleFor(tierId, rng)
	local tier = Tiers[tierId]
	if tier.oneIn and tier.oneIn >= RarityTable.COMMON_ONE_IN_LIMIT then
		return tier.scale
	end
	local v = RarityTable.COMMON_VARIATION
	return tier.scale * (1 + rng:NextNumber(-v, v))
end

-- One weighted roll. Each tier gets exactly 1/oneIn of the number line
-- (times luck, for rare tiers); the fallback tier gets what's left.
-- Returns tierId, scale.
function RarityTable.Roll(luck, rng)
	luck = luck or 1
	local r = rng:NextNumber()
	local cumulative = 0
	for _, id in ipairs(rollOrder) do
		local tier = Tiers[id]
		local chance = 1 / tier.oneIn
		if tier.oneIn >= RarityTable.LUCK_MIN_ONE_IN then
			chance *= luck
		end
		cumulative += chance
		if r < cumulative then
			return id, RarityTable.ScaleFor(id, rng)
		end
	end
	return fallbackId, RarityTable.ScaleFor(fallbackId, rng)
end

-- A roll that can only land on tiers at least 1 in minOneIn rare, keeping
-- their odds relative to each other. Used by the Growth Spinner's Titan Surge.
function RarityTable.RollAtLeast(minOneIn, rng)
	local total = 0
	local leastRare = nil
	for _, id in ipairs(rollOrder) do
		if Tiers[id].oneIn >= minOneIn then
			total += 1 / Tiers[id].oneIn
			leastRare = id -- rollOrder is rarest first, so this ends on the least rare
		end
	end
	assert(leastRare, "RarityTable.RollAtLeast: no tier is that rare")
	local r = rng:NextNumber() * total
	for _, id in ipairs(rollOrder) do
		local tier = Tiers[id]
		if tier.oneIn >= minOneIn then
			r -= 1 / tier.oneIn
			if r < 0 then
				return id, RarityTable.ScaleFor(id, rng)
			end
		end
	end
	return leastRare, RarityTable.ScaleFor(leastRare, rng) -- floating point leftovers
end

-- How rare a tier is, as N in "1 in N". The fallback counts as 1.
function RarityTable.Rarity(tierId)
	return Tiers[tierId].oneIn or 1
end

-- Is the new roll a better "best"? Rarer wins; same rarity -> more extreme size wins.
function RarityTable.IsBetter(newId, newScale, oldId, oldScale)
	local newRarity, oldRarity = RarityTable.Rarity(newId), RarityTable.Rarity(oldId)
	if newRarity ~= oldRarity then
		return newRarity > oldRarity
	end
	return math.abs(math.log(newScale)) > math.abs(math.log(oldScale))
end

local function commas(n)
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- Rarity classes: the color code used by the Index (and anything else that
-- wants one). Picked by odds; World Eater gets its own prismatic class.
RarityTable.Classes = {
	{ name = "Common",   minOneIn = 0,       color = rgb(160, 165, 175) },
	{ name = "Rare",     minOneIn = 100,     color = rgb(70, 150, 255) },
	{ name = "Epic",     minOneIn = 3000,    color = rgb(170, 90, 255) },
	{ name = "Colossal", minOneIn = 80000,   color = rgb(255, 200, 60) },
	{ name = "Mythic",   minOneIn = 1000000, color = rgb(190, 60, 255), color2 = rgb(255, 30, 70) }, -- prismatic violet -> red
}

function RarityTable.ClassOf(tierId)
	local rarity = RarityTable.Rarity(tierId)
	local found = RarityTable.Classes[1]
	for _, class in ipairs(RarityTable.Classes) do
		if rarity >= class.minOneIn then
			found = class
		end
	end
	return found
end

function RarityTable.FormatOdds(tierId)
	local oneIn = Tiers[tierId].oneIn
	return oneIn and ("1 in " .. commas(oneIn)) or "Common"
end

function RarityTable.FormatHeight(scale)
	local feet = RarityTable.BASE_HEIGHT_FEET * scale
	if feet >= 100 then
		return commas(feet + 0.5) .. " ft"
	elseif feet >= 1 then
		local inches = math.floor(feet * 12 + 0.5)
		return string.format("%d ft %d in", inches // 12, inches % 12)
	elseif feet * 12 >= 1 then
		return string.format("%.1f in", feet * 12)
	end
	return string.format("%.1f mm", feet * 304.8)
end

function RarityTable.FormatScale(scale)
	if scale >= 10 then
		return string.format("%dx", math.floor(scale + 0.5))
	end
	return string.format("%.2fx", scale)
end

return RarityTable
