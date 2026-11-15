local D = require(script.Parent.Parent.Deps)
local ModeVote, GameConfig = D.ModeVote, D.GameConfig

local ORDER = GameConfig.DifficultyOrder
local DEFAULT = GameConfig.DefaultDifficulty

local function fixed(value: number)
	return function()
		return value
	end
end

return function(t)
	t.test("highest vote count wins", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		v:cast(1, "BrainMeltdown")
		v:cast(2, "BrainMeltdown")
		v:cast(3, "CasualChaos")
		local winner, info = v:pick({ 1, 2, 3 }, fixed(0))
		t.eq(winner, "BrainMeltdown")
		t.eq(info.counts.BrainMeltdown, 2)
		t.eq(info.counts.CasualChaos, 1)
		t.eq(info.votes, 3)
		t.eq(#info.tied, 0)
	end)

	t.test("nobody voting gives Mixed Madness", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		local winner, info = v:pick({ 1, 2, 3 }, fixed(0.99))
		t.eq(winner, "MixedMadness")
		t.eq(info.votes, 0)
	end)

	t.test("one vote per player, and it can be changed", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		v:cast(1, "CasualChaos")
		v:cast(1, "CasualChaos")
		v:cast(1, "BrainMeltdown")
		local counts = v:tally({ 1 })
		t.eq(counts.CasualChaos, 0)
		t.eq(counts.BrainMeltdown, 1)
		t.eq(v:voteOf(1), "BrainMeltdown")
		t.eq(v:tally({ 1, 1, 1 }).BrainMeltdown, 1, "listing a voter twice doesn't count twice")
	end)

	t.test("Mixed Madness wins any tie it is part of", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		v:cast(1, "MixedMadness")
		v:cast(2, "BrainMeltdown")
		for _, r in { 0, 0.5, 0.99 } do
			t.eq((v:pick({ 1, 2 }, fixed(r))), "MixedMadness")
		end
		v:cast(3, "CasualChaos")
		local winner, info = v:pick({ 1, 2, 3 }, fixed(0.99))
		t.eq(winner, "MixedMadness", "three-way tie")
		t.eq(#info.tied, 3)
	end)

	t.test("other ties are broken at random between the tied modes only", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		v:cast(1, "CasualChaos")
		v:cast(2, "BrainMeltdown")
		t.eq((v:pick({ 1, 2 }, fixed(0))), "CasualChaos")
		t.eq((v:pick({ 1, 2 }, fixed(0.99))), "BrainMeltdown")
		t.eq((v:pick({ 1, 2 }, fixed(1))), "BrainMeltdown", "rng edge value stays in range")
		local rng = Random.new(3)
		local seen = {}
		for _ = 1, 200 do
			seen[(v:pick({ 1, 2 }, function()
				return rng:NextNumber()
			end))] = true
		end
		t.truthy(seen.CasualChaos and seen.BrainMeltdown, "both tied modes can win")
		t.falsy(seen.MixedMadness, "a mode with fewer votes never wins")
	end)

	t.test("only the players starting the match are counted", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		v:cast(1, "CasualChaos")
		v:cast(8, "BrainMeltdown") -- sitting out
		v:cast(9, "BrainMeltdown") -- spectator
		t.eq((v:pick({ 1, 2, 3 }, fixed(0))), "CasualChaos")
		v:remove(1) -- left the server
		t.eq((v:pick({ 1, 2, 3 }, fixed(0))), "MixedMadness")
	end)

	t.test("invalid votes are rejected and clear() resets for the next match", function()
		local v = ModeVote.new(ORDER, DEFAULT)
		t.falsy(v:cast(1, "UltraNightmare"))
		t.falsy(v:cast(1, nil))
		t.falsy(v:cast(1, 3))
		t.falsy(v:cast(1, {}))
		t.eq(v:voteOf(1), nil)
		t.truthy(v:cast(1, "CasualChaos"))
		v:clear()
		t.eq(v:voteOf(1), nil)
		t.eq((v:pick({ 1 }, fixed(0))), "MixedMadness")
	end)
end
