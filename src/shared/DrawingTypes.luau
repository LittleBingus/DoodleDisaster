--!strict
-- DrawingTypes: the sketch data format and its validation. Pure logic.
--
-- A drawing is a list of strokes. Coordinates are normalized to the canvas and stored as
-- integers in [0, SCALE] (SCALE = 1000) to keep payloads small and resolution-independent.
--
--   Drawing = { v = 1, strokes = { Stroke } }
--   Stroke  = { c = colorIndex, w = sizeIndex, p = { x1, y1, x2, y2, ... } }
--
-- The eraser is simply the paper colour (index 1). Future "Chaos Events" (mirroring,
-- rotation, limited palettes) are applied as client-side input transforms or render
-- options, so the stored format never needs to change for them.

export type Stroke = { c: number, w: number, p: { number } }
export type Drawing = { v: number, strokes: { Stroke } }

local DrawingTypes = {}

DrawingTypes.VERSION = 1
DrawingTypes.SCALE = 1000
DrawingTypes.ASPECT = 4 / 3 -- canvas width / height
DrawingTypes.PAPER_INDEX = 1

DrawingTypes.Palette = {
	{ 255, 255, 255 }, -- 1 paper / eraser
	{ 25, 25, 35 }, -- 2 ink
	{ 235, 60, 60 }, -- 3 red
	{ 255, 140, 30 }, -- 4 orange
	{ 255, 215, 40 }, -- 5 yellow
	{ 60, 190, 90 }, -- 6 green
	{ 50, 140, 255 }, -- 7 blue
	{ 150, 80, 230 }, -- 8 purple
	{ 255, 120, 190 }, -- 9 pink
	{ 140, 90, 50 }, -- 10 brown
	{ 150, 150, 160 }, -- 11 grey
	{ 120, 225, 235 }, -- 12 sky
}

-- Brush thickness as a fraction of canvas width.
DrawingTypes.BrushSizes = { 0.006, 0.012, 0.022, 0.04, 0.07 }

DrawingTypes.Limits = {
	MaxStrokes = 250,
	MaxPointsPerStroke = 400, -- points, not numbers
	MaxTotalPoints = 3000,
	MaxPayloadNumbers = 6500, -- rough payload budget (coordinates + headers)
}

local function isInteger(x: any): boolean
	return type(x) == "number" and x == x and x % 1 == 0
end

-- Validates an untrusted drawing from a client. Returns a clean copy on success
-- (unknown fields stripped) or nil + reason. Never errors on malformed input.
function DrawingTypes.validate(raw: any): (Drawing?, string?)
	if type(raw) ~= "table" then
		return nil, "drawing must be a table"
	end
	local strokes = raw.strokes
	if strokes == nil then
		strokes = {}
	end
	if type(strokes) ~= "table" then
		return nil, "strokes must be a table"
	end
	local count = #strokes
	-- Reject sparse / dictionary-shaped stroke lists.
	for k in strokes do
		if not isInteger(k) or k < 1 or k > count then
			return nil, "strokes must be an array"
		end
	end
	if count > DrawingTypes.Limits.MaxStrokes then
		return nil, "too many strokes"
	end

	local clean: { Stroke } = {}
	local totalPoints = 0
	local payloadNumbers = 0
	for i = 1, count do
		local s = strokes[i]
		if type(s) ~= "table" then
			return nil, "stroke " .. i .. " is not a table"
		end
		local c, w, p = s.c, s.w, s.p
		if not isInteger(c) or c < 1 or c > #DrawingTypes.Palette then
			return nil, "stroke " .. i .. " has a bad colour"
		end
		if not isInteger(w) or w < 1 or w > #DrawingTypes.BrushSizes then
			return nil, "stroke " .. i .. " has a bad brush size"
		end
		if type(p) ~= "table" then
			return nil, "stroke " .. i .. " has no points"
		end
		local n = #p
		for k in p do
			if not isInteger(k) or k < 1 or k > n then
				return nil, "stroke " .. i .. " points must be an array"
			end
		end
		if n < 2 or n % 2 ~= 0 then
			return nil, "stroke " .. i .. " has an odd coordinate count"
		end
		local points = n // 2
		if points > DrawingTypes.Limits.MaxPointsPerStroke then
			return nil, "stroke " .. i .. " has too many points"
		end
		local copy = table.create(n)
		for j = 1, n do
			local v = p[j]
			if not isInteger(v) or v < 0 or v > DrawingTypes.SCALE then
				return nil, "stroke " .. i .. " has an out-of-range coordinate"
			end
			copy[j] = v
		end
		totalPoints += points
		payloadNumbers += n + 2
		if totalPoints > DrawingTypes.Limits.MaxTotalPoints then
			return nil, "too many points"
		end
		if payloadNumbers > DrawingTypes.Limits.MaxPayloadNumbers then
			return nil, "drawing too large"
		end
		clean[i] = { c = c, w = w, p = copy }
	end
	return { v = DrawingTypes.VERSION, strokes = clean }, nil
end

function DrawingTypes.empty(): Drawing
	return { v = DrawingTypes.VERSION, strokes = {} }
end

-- A drawing is "blank" if it has no visible ink (eraser-only strokes don't count).
function DrawingTypes.isBlank(drawing: Drawing): boolean
	for _, s in drawing.strokes do
		if s.c ~= DrawingTypes.PAPER_INDEX then
			return false
		end
	end
	return true
end

function DrawingTypes.pointCount(drawing: Drawing): number
	local total = 0
	for _, s in drawing.strokes do
		total += #s.p // 2
	end
	return total
end

-- Quantizes a normalized 0..1 value into the stored integer range.
function DrawingTypes.quantize(x: number): number
	local v = math.floor(x * DrawingTypes.SCALE + 0.5)
	if v < 0 then
		return 0
	elseif v > DrawingTypes.SCALE then
		return DrawingTypes.SCALE
	end
	return v
end

return DrawingTypes
