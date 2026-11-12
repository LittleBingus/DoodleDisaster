local D = require(script.Parent.Parent.Deps)
local DrawingTypes = D.DrawingTypes

return function(t)
	local L = DrawingTypes.Limits

	t.test("accepts a normal drawing and strips unknown fields", function()
		local clean = DrawingTypes.validate({ strokes = { { c = 2, w = 3, p = { 0, 0, 1000, 1000 }, evil = true } }, x = 1 })
		t.truthy(clean)
		t.eq(clean.strokes[1].evil, nil)
		t.eq(clean.v, DrawingTypes.VERSION)
	end)

	t.test("accepts an empty drawing (timeouts / blank pages)", function()
		t.truthy(DrawingTypes.validate({ strokes = {} }))
		t.truthy(DrawingTypes.validate({}))
		t.truthy(DrawingTypes.isBlank(DrawingTypes.empty()))
	end)

	local bad = {
		{ "non-table", "hello" },
		{ "strokes not a table", { strokes = 5 } },
		{ "dictionary strokes", { strokes = { a = { c = 2, w = 1, p = { 1, 1 } } } } },
		{ "colour out of range", { strokes = { { c = 0, w = 1, p = { 1, 1 } } } } },
		{ "colour not integer", { strokes = { { c = 2.5, w = 1, p = { 1, 1 } } } } },
		{ "brush too big", { strokes = { { c = 2, w = 99, p = { 1, 1 } } } } },
		{ "odd coordinates", { strokes = { { c = 2, w = 1, p = { 1, 1, 1 } } } } },
		{ "coordinate > scale", { strokes = { { c = 2, w = 1, p = { 1001, 1 } } } } },
		{ "negative coordinate", { strokes = { { c = 2, w = 1, p = { -1, 1 } } } } },
		{ "NaN coordinate", { strokes = { { c = 2, w = 1, p = { 0 / 0, 1 } } } } },
		{ "infinite coordinate", { strokes = { { c = 2, w = 1, p = { math.huge, 1 } } } } },
		{ "string coordinate", { strokes = { { c = 2, w = 1, p = { "1", 1 } } } } },
	}
	for _, case in bad do
		t.test("rejects " .. case[1], function()
			local clean, err = DrawingTypes.validate(case[2])
			t.eq(clean, nil)
			t.truthy(err)
		end)
	end

	t.test("enforces stroke, point and payload limits", function()
		local strokes = {}
		for i = 1, L.MaxStrokes + 1 do
			strokes[i] = { c = 2, w = 1, p = { 1, 1 } }
		end
		t.falsy((DrawingTypes.validate({ strokes = strokes })), "too many strokes")

		local long = {}
		for i = 1, (L.MaxPointsPerStroke + 1) * 2 do
			long[i] = 5
		end
		t.falsy((DrawingTypes.validate({ strokes = { { c = 2, w = 1, p = long } } })), "too many points in a stroke")

		local many = {}
		local per = L.MaxPointsPerStroke
		for i = 1, math.ceil(L.MaxTotalPoints / per) + 1 do
			local p = {}
			for j = 1, per * 2 do
				p[j] = 5
			end
			many[i] = { c = 2, w = 1, p = p }
		end
		t.falsy((DrawingTypes.validate({ strokes = many })), "too many total points")
	end)

	t.test("isBlank ignores eraser-only strokes", function()
		local d = DrawingTypes.validate({ strokes = { { c = DrawingTypes.PAPER_INDEX, w = 3, p = { 5, 5, 9, 9 } } } })
		t.truthy(DrawingTypes.isBlank(d))
	end)

	t.test("quantize clamps to range", function()
		t.eq(DrawingTypes.quantize(-0.5), 0)
		t.eq(DrawingTypes.quantize(1.7), 1000)
		t.eq(DrawingTypes.quantize(0.1234), 123)
	end)
end
