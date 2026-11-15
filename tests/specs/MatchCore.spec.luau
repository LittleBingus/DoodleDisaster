local D = require(script.Parent.Parent.Deps)
local MatchCore, Rotation, DrawingTypes, GameConfig = D.MatchCore, D.Rotation, D.DrawingTypes, D.GameConfig

local function newCore(n: number)
	local ids, prompts = {}, {}
	for i = 1, n do
		ids[i] = 1000 + i
		prompts[i] = { Id = "p" .. i, Phrase = "Prompt " .. i }
	end
	return MatchCore.new({
		userIds = ids,
		prompts = prompts,
		Rotation = Rotation,
		validateDrawing = DrawingTypes.validate,
		isBlankDrawing = DrawingTypes.isBlank,
		emptyDrawing = DrawingTypes.empty,
		guessTimeoutText = GameConfig.Guess.TimeoutPlaceholder,
		guessLeftText = GameConfig.Guess.LeftPlaceholder,
	}), ids
end

local function sketch(tag: number)
	return { v = 1, strokes = { { c = 2, w = 2, p = { tag % 1000, 10, 500, 500 } } } }
end

-- Plays a full match where everyone submits; returns the core.
local function playFull(t, n: number)
	local core, ids = newCore(n)
	for step = 0, n - 1 do
		for _, uid in ids do
			local task = core:getTask(uid)
			t.truthy(task, "task exists")
			t.eq(task.step, step)
			local content = if task.kind == "Draw" then sketch(uid + step) else ("guess " .. uid .. "@" .. step)
			local ok, err = core:submit(uid, step, task.kind, content)
			t.truthy(ok, err)
		end
		t.truthy(core:allSubmitted())
		core:finalizeStep()
	end
	t.truthy(core:isComplete())
	return core, ids
end

return function(t)
	for _, n in { 3, 4, 5, 6, 7, 8 } do
		t.test(n .. " players complete a match; every player contributes once to every book", function()
			local core, ids = playFull(t, n)
			for b, book in core.books do
				t.eq(#book.entries, n, "entries in book " .. b)
				local authors = {}
				for j, e in book.entries do
					t.falsy(e.auto, "no placeholders when everyone submits")
					t.eq(e.kind, Rotation.kindForStep(j - 1))
					t.falsy(authors[e.author], "author repeated in book " .. b)
					authors[e.author] = true
				end
				t.eq(book.entries[1].author, book.owner, "owner draws first")
				for _, uid in ids do
					t.truthy(authors[uid], "player missing from book " .. b)
				end
			end
		end)
	end

	t.test("players only see the immediately preceding entry", function()
		local core, ids = newCore(4)
		local first = core:getTask(ids[1])
		t.eq(first.inputType, "Prompt")
		t.eq(first.text, "Prompt 1")
		for _, uid in ids do
			core:submit(uid, 0, "Draw", sketch(uid))
		end
		core:finalizeStep()
		local task = core:getTask(ids[2]) -- player 2 now holds book 1
		t.eq(task.kind, "Guess")
		t.eq(task.inputType, "Drawing")
		t.eq(task.drawing.strokes[1].p[1], ids[1] % 1000, "sees book 1's drawing")
		t.eq(task.text, nil, "no prompt text leaked to guesser")
		for _, uid in ids do
			core:submit(uid, 1, "Guess", "g" .. uid)
		end
		core:finalizeStep()
		local drawTask = core:getTask(ids[3]) -- player 3 holds book 1 at step 2
		t.eq(drawTask.inputType, "Guess")
		t.eq(drawTask.text, "g" .. ids[2])
		t.eq(drawTask.drawing, nil, "no earlier drawing leaked to drawer")
	end)

	t.test("rejects duplicate, wrong-step, wrong-kind and outsider submissions", function()
		local core, ids = newCore(3)
		t.truthy((core:submit(ids[1], 0, "Draw", sketch(1))))
		local ok, err = core:submit(ids[1], 0, "Draw", sketch(2))
		t.falsy(ok)
		t.eq(err, "already submitted")
		t.falsy((core:submit(ids[2], 1, "Draw", sketch(3))), "wrong step")
		t.falsy((core:submit(ids[2], 0, "Guess", "hi")), "wrong kind")
		t.falsy((core:submit(999, 0, "Draw", sketch(4))), "outsider")
		t.falsy((core:submit(ids[2], 0, "Draw", { strokes = { { c = 99, w = 1, p = { 1, 1 } } } })), "invalid drawing")
	end)

	t.test("timeouts insert placeholders and the match still completes", function()
		local core, ids = newCore(3)
		core:submit(ids[1], 0, "Draw", sketch(1))
		core:finalizeStep() -- ids[2], ids[3] timed out
		t.truthy(core.books[2].entries[1].auto)
		t.truthy(DrawingTypes.isBlank(core.books[2].entries[1].content))
		core:finalizeStep() -- nobody guessed
		t.eq(core.books[1].entries[2].content, GameConfig.Guess.TimeoutPlaceholder)
		-- drawer after a placeholder guess gets the latest real text (the prompt)
		local task = core:getTask(ids[3])
		t.eq(task.text, "Prompt 1")
		core:finalizeStep()
		t.truthy(core:isComplete())
		for _, book in core.books do
			t.eq(#book.entries, 3)
		end
	end)

	t.test("a disconnect mid-match is filled in and excluded from rewards", function()
		local core, ids = newCore(4)
		for _, uid in ids do
			core:submit(uid, 0, "Draw", sketch(uid))
		end
		core:finalizeStep()
		core:markLeft(ids[2])
		t.eq(core:connectedCount(), 3)
		t.eq(core:getTask(ids[2]), nil, "leaver gets no task")
		for _, uid in { ids[1], ids[3], ids[4] } do
			t.truthy((core:submit(uid, 1, "Guess", "x")))
		end
		t.truthy(core:allSubmitted(), "remaining players are enough to advance")
		core:finalizeStep()
		local leaverBook = core:bookIndexFor(ids[2], 1)
		t.eq(core.books[leaverBook].entries[2].content, GameConfig.Guess.LeftPlaceholder)
		while not core:isComplete() do
			for _, uid in { ids[1], ids[3], ids[4] } do
				local task = core:getTask(uid)
				core:submit(uid, task.step, task.kind, if task.kind == "Draw" then sketch(uid) else "y")
			end
			core:finalizeStep()
		end
		local participants = core:getParticipants(function()
			return true
		end)
		local byId = {}
		for _, p in participants do
			byId[p.userId] = p
		end
		t.falsy(byId[ids[2]].stillPresent)
		t.truthy(byId[ids[1]].stillPresent)
		t.eq(byId[ids[1]].activeSubmissions, 4)
	end)

	t.test("blank drawings don't count as active submissions", function()
		local core, ids = newCore(3)
		core:submit(ids[1], 0, "Draw", DrawingTypes.empty())
		core:submit(ids[2], 0, "Draw", sketch(2))
		t.eq(core.activeSubmissions[ids[1]], 0)
		t.eq(core.activeSubmissions[ids[2]], 1)
	end)

	t.test("a player who rejoins resumes from the current step", function()
		local core, ids = newCore(3)
		for _, uid in ids do
			core:submit(uid, 0, "Draw", sketch(uid))
		end
		core:finalizeStep()
		core:markLeft(ids[2])
		t.eq(core:connectedCount(), 2, "the match carries on with two")
		core:submit(ids[1], 1, "Guess", "a")
		t.falsy(core:markReturned(999), "outsiders can't join a running match")
		t.truthy(core:markReturned(ids[2]))
		t.falsy(core:markReturned(ids[2]), "already back")
		t.eq(core:connectedCount(), 3)
		local task = core:getTask(ids[2])
		t.eq(task.step, 1)
		t.falsy(core:allSubmitted(), "the returning player is waited for again")
		t.truthy((core:submit(ids[2], 1, "Guess", "b")))
		t.truthy((core:submit(ids[3], 1, "Guess", "c")))
		t.truthy(core:allSubmitted())
		core:finalizeStep()
		for _, book in core.books do
			t.eq(#book.entries, 2, "rotation stays consistent: one entry per book per step")
		end
	end)

	t.test("a step filled in while a player was away is not rewritten when they return", function()
		local core, ids = newCore(3)
		core:markLeft(ids[2])
		core:submit(ids[1], 0, "Draw", sketch(1))
		core:submit(ids[3], 0, "Draw", sketch(3))
		core:finalizeStep()
		core:markReturned(ids[2])
		local book = core:bookIndexFor(ids[2], 0)
		t.truthy(core.books[book].entries[1].auto)
		t.falsy((core:submit(ids[2], 0, "Draw", sketch(2))), "old step is closed")
		t.eq(core.activeSubmissions[ids[2]], 0)
	end)

	t.test("a replaced guess continues the chain but is never an award candidate", function()
		local core, ids = newCore(3)
		for _, uid in ids do
			core:submit(uid, 0, "Draw", sketch(uid))
		end
		core:finalizeStep()
		t.truthy((core:submit(ids[1], 1, "Guess", "a potato with a law degree", true)))
		core:submit(ids[2], 1, "Guess", "real guess")
		core:submit(ids[3], 1, "Guess", "another guess")
		core:finalizeStep()
		local book = core:bookIndexFor(ids[1], 1)
		t.truthy(core.books[book].entries[2].fallback)
		t.falsy(core.books[book].entries[2].auto)
		-- whoever draws in that book next is asked to draw the replacement phrase
		local drawer
		for _, uid in ids do
			if core:bookIndexFor(uid) == book then
				drawer = uid
			end
		end
		t.eq(core:getTask(drawer).text, "a potato with a law degree")
		t.eq(#core:getEntries("Guess"), 2, "the replacement is not votable")
		t.eq(core.activeSubmissions[ids[1]], 2, "the player still gets credit for taking part")
		local revealed = core:getRevealBooks()[book].entries[2]
		t.truthy(revealed.fallback)
	end)

	t.test("every drawing gets a unique opaque id that resolves to its author on the server only", function()
		local core, ids = playFull(t, 4)
		local seen, count = {}, 0
		for b, book in core:getRevealBooks() do
			for j, e in book.entries do
				if e.kind == "Draw" then
					t.truthy(type(e.id) == "string")
					t.falsy(seen[e.id], "ids are unique")
					seen[e.id] = true
					count += 1
					local info = core:getDrawing(e.id)
					t.eq(info.author, core.books[b].entries[j].author)
					t.eq(info.bookIndex, b)
					t.eq(info.entryIndex, j)
					t.falsy(e.id:find(tostring(info.author), 1, true), "id does not contain the author")
				else
					t.eq(e.id, nil)
				end
			end
		end
		t.eq(count, 8)
		t.eq(core:getDrawing("nope"), nil)
		t.eq(core:getDrawing(42), nil)
		for _, e in core:getEntries("Draw") do
			t.truthy(seen[e.id], "ballot entries carry the same id")
		end
	end)

	t.test("the guesser is told the id of the drawing in front of them", function()
		local core, ids = newCore(3)
		for _, uid in ids do
			core:submit(uid, 0, "Draw", sketch(uid))
		end
		core:finalizeStep()
		local task = core:getTask(ids[1])
		t.eq(task.kind, "Guess")
		local info = core:getDrawing(task.drawId)
		t.truthy(info and info.author ~= ids[1])
	end)

	t.test("reveal data contains no author ids", function()
		local core, ids = playFull(t, 3)
		local books = core:getRevealBooks()
		for _, book in books do
			for _, e in book.entries do
				t.eq(e.author, nil)
			end
		end
		t.eq(books[1].prompt, "Prompt 1")
	end)
end
