local D = require(script.Parent.Parent.Deps)
local PromptSelector, PromptPacks, GameConfig = D.PromptSelector, D.PromptPacks, D.GameConfig

local function synthetic(perDifficulty: number)
	local list = {}
	for _, d in { "Easy", "Medium", "Hard" } do
		for i = 1, perDifficulty do
			table.insert(list, { Id = d .. i, Difficulty = d, Enabled = true })
		end
	end
	return list
end

return function(t)
	local rng = Random.new(42)
	local function r()
		return rng:NextNumber()
	end

	t.test("prompt library is well-formed and includes idioms and metaphors in the free pack", function()
		local ids, counts = {}, { Easy = 0, Medium = 0, Hard = 0 }
		for _, p in PromptPacks.Prompts do
			t.falsy(ids[p.Id], "duplicate id " .. p.Id)
			ids[p.Id] = true
			t.truthy(PromptPacks.getPack(p.Pack), "unknown pack " .. p.Pack)
			t.truthy(counts[p.Difficulty] ~= nil, "bad difficulty")
			t.truthy(type(p.Phrase) == "string" and #p.Phrase > 0)
			t.eq(p.Enabled, true)
			if p.Pack == PromptPacks.FreePackId then
				counts[p.Difficulty] += 1
			end
		end
		t.truthy(counts.Medium >= 8, "free idioms")
		t.truthy(counts.Hard >= 8, "free metaphors")
		t.truthy(counts.Easy >= 8, "free scenarios")
	end)

	t.test("every pack mixes difficulties", function()
		for _, pack in PromptPacks.Packs do
			local seen = {}
			for _, p in PromptPacks.Prompts do
				if p.Pack == pack.Id then
					seen[p.Difficulty] = true
				end
			end
			t.truthy(seen.Easy and seen.Medium and seen.Hard, pack.Id .. " should contain all difficulties")
		end
	end)

	t.test("no repeats within a match, even for 8 players", function()
		for _ = 1, 200 do
			local picked = PromptSelector.select(PromptPacks.Prompts, GameConfig.Difficulties.BrainMeltdown.Weights, 8, r)
			t.eq(#picked, 8)
			local seen = {}
			for _, p in picked do
				t.falsy(seen[p.Id], "repeat within a match")
				seen[p.Id] = true
			end
		end
	end)

	t.test("avoids prompts from the previous match while alternatives exist", function()
		local pool = synthetic(10)
		local recent = {}
		for i = 1, 5 do
			recent["Easy" .. i] = true
			recent["Medium" .. i] = true
			recent["Hard" .. i] = true
		end
		for _ = 1, 100 do
			for _, p in PromptSelector.select(pool, { Easy = 1, Medium = 1, Hard = 1 }, 8, r, recent) do
				t.falsy(recent[p.Id], "picked a recent prompt")
			end
		end
	end)

	t.test("falls back to repeats from earlier matches when the pool runs dry", function()
		local pool = synthetic(2)
		local recent = {}
		for _, p in pool do
			recent[p.Id] = true
		end
		t.eq(#PromptSelector.select(pool, { Easy = 1, Medium = 1, Hard = 1 }, 6, r, recent), 6)
	end)

	for _, id in GameConfig.DifficultyOrder do
		t.test("difficulty " .. id .. " matches its configured weights", function()
			local weights = GameConfig.Difficulties[id].Weights
			local pool = synthetic(50)
			local counts = { Easy = 0, Medium = 0, Hard = 0 }
			local trials = 20000
			for _ = 1, trials do
				local p = PromptSelector.select(pool, weights, 1, r)[1]
				counts[p.Difficulty] += 1
			end
			local total = weights.Easy + weights.Medium + weights.Hard
			for _, d in { "Easy", "Medium", "Hard" } do
				t.near(counts[d] / trials, weights[d] / total, 0.02, id .. " " .. d)
			end
		end)
	end

	t.test("redistributes weight when a difficulty is empty", function()
		local pool = { { Id = "e1", Difficulty = "Easy", Enabled = true }, { Id = "e2", Difficulty = "Easy", Enabled = true } }
		t.eq(#PromptSelector.select(pool, { Easy = 0, Medium = 50, Hard = 50 }, 2, r), 2)
	end)

	t.test("skips disabled prompts", function()
		local pool = { { Id = "a", Difficulty = "Easy", Enabled = false }, { Id = "b", Difficulty = "Easy", Enabled = true } }
		for _ = 1, 20 do
			t.eq(PromptSelector.select(pool, { Easy = 1 }, 1, r)[1].Id, "b")
		end
	end)
end
