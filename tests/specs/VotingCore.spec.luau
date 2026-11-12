local D = require(script.Parent.Parent.Deps)
local VotingCore, GameConfig = D.VotingCore, D.GameConfig

local function entries(kind: string, authors: { number })
	local list = {}
	for i, a in authors do
		table.insert(list, { author = a, content = kind .. i, bookIndex = i, entryIndex = 1 })
	end
	return list
end

local function setup(seed: number?)
	local rng = Random.new(seed or 7)
	local ballot, authorOf = VotingCore.buildBallot({
		Draw = entries("Draw", { 1, 2, 3, 4 }),
		Guess = entries("Guess", { 1, 2, 3, 4 }),
	}, GameConfig.Voting.Categories, GameConfig.Voting.MaxCandidatesPerCategory, function()
		return rng:NextNumber()
	end)
	return ballot, authorOf, VotingCore.new(ballot, authorOf, { 1, 2, 3, 4 })
end

local function candidateBy(authorOf, author: number, prefix: string): string
	for cid, a in authorOf do
		if a == author and cid:sub(1, 1) == prefix then
			return cid
		end
	end
	error("no candidate")
end

return function(t)
	t.test("public ballot carries no authorship", function()
		local ballot = setup()
		for cid, c in ballot.candidates do
			t.eq(c.author, nil)
			t.eq(c.userId, nil)
			t.eq(c.bookIndex, nil, "book index could reveal the owner")
			t.truthy(c.label:match("^Doodle %d+$") or c.label:match("^Guess %d+$"), "generic label")
		end
		t.eq(#ballot.categories, 4)
	end)

	t.test("rejects self votes, duplicates, unknown ids and non-voters", function()
		local _, authorOf, session = setup()
		local own = candidateBy(authorOf, 1, "D")
		local other = candidateBy(authorOf, 2, "D")
		local ok, err = session:cast(1, "Funniest", own)
		t.falsy(ok)
		t.eq(err, "you can't vote for yourself")
		t.truthy((session:cast(1, "Funniest", other)))
		t.falsy((session:cast(1, "Funniest", candidateBy(authorOf, 3, "D"))), "duplicate")
		t.falsy((session:cast(1, "Nope", other)), "unknown category")
		t.falsy((session:cast(1, "Disaster", "D99")), "unknown candidate")
		t.falsy((session:cast(1, "Confusing", other)), "drawing in guess category")
		t.falsy((session:cast(42, "Disaster", other)), "not a voter")
		t.falsy((session:cast(1, "Disaster", 5)), "bad type")
	end)

	t.test("rejects votes after voting closes", function()
		local _, authorOf, session = setup()
		session:close()
		t.falsy((session:cast(1, "Funniest", candidateBy(authorOf, 2, "D"))))
	end)

	t.test("tallies winners and shares tied awards", function()
		local _, authorOf, session = setup()
		local d2, d3 = candidateBy(authorOf, 2, "D"), candidateBy(authorOf, 3, "D")
		session:cast(1, "Funniest", d2)
		session:cast(4, "Funniest", d2)
		session:cast(2, "Funniest", d3)
		session:cast(1, "Disaster", d2)
		session:cast(4, "Disaster", d3)
		local results, awards = session:close()
		local byId = {}
		for _, r in results do
			byId[r.categoryId] = r
		end
		t.eq(byId.Funniest.authorIds, { 2 })
		t.eq(byId.Funniest.votes, 2)
		t.eq(#byId.Disaster.authorIds, 2, "tie shares the award")
		t.eq(#byId.Confusing.authorIds, 0, "no votes, no winner")
		t.eq(awards[2], 2)
		t.eq(awards[3], 1)
		t.eq(awards[1], nil)
	end)

	t.test("categories with fewer than two candidates are skipped", function()
		local ballot = VotingCore.buildBallot({ Draw = entries("Draw", { 1 }), Guess = {} }, GameConfig.Voting.Categories, 8,
			function()
				return 0.5
			end)
		t.eq(#ballot.categories, 0)
	end)

	t.test("candidate count is capped", function()
		local many = {}
		for i = 1, 30 do
			many[i] = i
		end
		local ballot = VotingCore.buildBallot({ Draw = entries("Draw", many), Guess = {} }, GameConfig.Voting.Categories, 8,
			function()
				return 0.3
			end)
		t.eq(#ballot.categories[1].candidateIds, 8)
	end)

	t.test("allVoted ignores categories where only your own entries exist", function()
		local ballot, authorOf = VotingCore.buildBallot({ Draw = entries("Draw", { 1, 1 }), Guess = {} },
			GameConfig.Voting.Categories, 8, function()
				return 0.5
			end)
		local session = VotingCore.new(ballot, authorOf, { 1 })
		t.truthy(session:allVoted())
	end)

	t.test("leaving voters' votes are discarded", function()
		local _, authorOf, session = setup()
		session:cast(1, "Funniest", candidateBy(authorOf, 2, "D"))
		session:removeVoter(1)
		local results = session:close()
		t.eq(results[1].votes, 0)
	end)
end
