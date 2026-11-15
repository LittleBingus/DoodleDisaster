--!strict
-- MatchCore: the authoritative sketchbook state for one match. Pure logic: no Roblox
-- APIs, no timers, no networking. RoundManager drives it with real time, remotes and
-- text filtering; the automated tests drive it directly.
--
-- Dependencies are injected (opts.Rotation, opts.validateDrawing, ...) so the module has
-- no require() calls and runs unchanged in Roblox and in the standalone Luau test runner.

local MatchCore = {}
MatchCore.__index = MatchCore

export type Entry = {
	kind: string, -- "Draw" | "Guess"
	author: number,
	content: any, -- Drawing table or filtered guess string
	auto: boolean, -- true when the server inserted a placeholder
	fallback: boolean?, -- guess replaced by a developer phrase (the filter left nothing usable)
	id: string?, -- drawings only: opaque id used for hide/report, never tied to the author publicly
}

export type Book = {
	owner: number,
	prompt: any,
	entries: { Entry },
}

export type Options = {
	userIds: { number },
	prompts: { any }, -- one per player, Phrase field required
	Rotation: any,
	validateDrawing: (any) -> (any, string?),
	isBlankDrawing: (any) -> boolean,
	emptyDrawing: () -> any,
	guessTimeoutText: string,
	guessLeftText: string,
	rng: (() -> number)?, -- 0..1, for drawing ids (defaults to math.random)
}

function MatchCore.new(opts: Options)
	local n = #opts.userIds
	assert(n >= 1, "MatchCore needs at least one player")
	assert(#opts.prompts >= n, "MatchCore needs one prompt per player")
	local self = setmetatable({}, MatchCore)
	self.opts = opts
	self.Rotation = opts.Rotation
	self.n = n
	self.userIds = table.clone(opts.userIds)
	self.indexOf = {} :: { [number]: number }
	self.left = {} :: { [number]: boolean }
	self.submitted = {} :: { [number]: boolean }
	self.activeSubmissions = {} :: { [number]: number }
	self.step = 0
	self.drawings = {} :: { [string]: { bookIndex: number, entryIndex: number } }
	self.books = {} :: { Book }
	for i, userId in self.userIds do
		assert(self.indexOf[userId] == nil, "duplicate user in match")
		self.indexOf[userId] = i
		self.activeSubmissions[userId] = 0
		self.books[i] = { owner = userId, prompt = opts.prompts[i], entries = {} }
	end
	return self
end

function MatchCore.isParticipant(self, userId: number): boolean
	return self.indexOf[userId] ~= nil
end

function MatchCore.isComplete(self): boolean
	return self.step >= self.n
end

function MatchCore.currentKind(self): string
	return self.Rotation.kindForStep(self.step)
end

function MatchCore.connectedCount(self): number
	local c = 0
	for _, userId in self.userIds do
		if not self.left[userId] then
			c += 1
		end
	end
	return c
end

function MatchCore.markLeft(self, userId: number)
	if self.indexOf[userId] then
		self.left[userId] = true
	end
end

-- A participant who left and came back resumes from the current step. Entries already
-- filled in for them stay as they are.
function MatchCore.markReturned(self, userId: number): boolean
	if self.indexOf[userId] and self.left[userId] then
		self.left[userId] = nil
		return true
	end
	return false
end

-- Gives a drawing entry an opaque random id. Ids are random (not sequential) so they
-- reveal nothing about who drew what or in which order.
function MatchCore._registerDrawing(self, bookIndex: number, entryIndex: number): string
	local rng = self.opts.rng or math.random
	local id
	repeat
		id = string.format("d%06d", math.floor(rng() * 999999))
	until not self.drawings[id]
	self.drawings[id] = { bookIndex = bookIndex, entryIndex = entryIndex }
	return id
end

-- Server-only lookup for moderation: who drew it and whether there is anything to see.
function MatchCore.getDrawing(self, id: any)
	local ref = if type(id) == "string" then self.drawings[id] else nil
	if not ref then
		return nil
	end
	local e = self.books[ref.bookIndex].entries[ref.entryIndex]
	return {
		author = e.author,
		auto = e.auto,
		blank = self.opts.isBlankDrawing(e.content),
		content = e.content,
		bookIndex = ref.bookIndex,
		entryIndex = ref.entryIndex,
	}
end

function MatchCore.bookIndexFor(self, userId: number, step: number?): number?
	local p = self.indexOf[userId]
	if not p then
		return nil
	end
	return self.Rotation.bookForPlayer(p, step or self.step, self.n)
end

-- The text a drawer should illustrate: the previous guess, or (if that guess was a
-- placeholder) the most recent real text in the chain, falling back to the prompt.
local function textToDraw(book: Book, step: number): string
	for i = step, 1, -1 do
		local e = book.entries[i]
		if e.kind == "Guess" and not e.auto then
			return e.content
		end
	end
	return book.prompt.Phrase
end

-- Returns the task for this player at the current step, or nil if they have none.
-- Only the immediately preceding entry is exposed; never the full history.
function MatchCore.getTask(self, userId: number)
	if self:isComplete() or not self.indexOf[userId] or self.left[userId] then
		return nil
	end
	local bookIndex = self:bookIndexFor(userId) :: number
	local book = self.books[bookIndex]
	local kind = self:currentKind()
	local task = {
		step = self.step,
		totalSteps = self.n,
		kind = kind,
		submitted = self.submitted[userId] == true,
	} :: { [string]: any }
	if kind == "Draw" then
		if self.step == 0 then
			task.inputType = "Prompt"
			task.text = book.prompt.Phrase
		else
			task.inputType = "Guess"
			task.text = textToDraw(book, self.step)
		end
	else
		local prev = book.entries[self.step]
		task.inputType = "Drawing"
		task.drawing = prev and prev.content or self.opts.emptyDrawing()
		task.drawId = prev and prev.id
	end
	return task
end

-- Records a submission. `content` is a raw drawing (validated here) or an already
-- sanitised + filtered guess string. `fallback` marks a guess the server replaced with a
-- developer phrase: it continues the chain but is not the player's own words, so it is
-- never an award candidate. Returns ok, errorReason.
function MatchCore.submit(self, userId: number, step: any, kind: any, content: any, fallback: boolean?): (boolean, string?)
	if not self.indexOf[userId] then
		return false, "not in this match"
	end
	if self.left[userId] then
		return false, "player left"
	end
	if self:isComplete() then
		return false, "match finished"
	end
	if step ~= self.step then
		return false, "wrong step"
	end
	if kind ~= self:currentKind() then
		return false, "wrong submission type"
	end
	if self.submitted[userId] then
		return false, "already submitted"
	end
	local value: any
	if kind == "Draw" then
		local clean, err = self.opts.validateDrawing(content)
		if not clean then
			return false, err
		end
		value = clean
	else
		if type(content) ~= "string" or content == "" then
			return false, "bad guess"
		end
		value = content
	end
	local bookIndex = self:bookIndexFor(userId) :: number
	self.books[bookIndex].entries[self.step + 1] = {
		kind = kind,
		author = userId,
		content = value,
		auto = false,
		fallback = if kind == "Guess" and fallback then true else nil,
		id = if kind == "Draw" then self:_registerDrawing(bookIndex, self.step + 1) else nil,
	}
	self.submitted[userId] = true
	-- Blank pages don't count toward the participation requirement (anti-AFK).
	if kind ~= "Draw" or not self.opts.isBlankDrawing(value) then
		self.activeSubmissions[userId] += 1
	end
	return true, nil
end

-- True once every connected participant has submitted for the current step.
function MatchCore.allSubmitted(self): boolean
	for _, userId in self.userIds do
		if not self.left[userId] and not self.submitted[userId] then
			return false
		end
	end
	return true
end

-- Fills any missing entries with placeholders and advances to the next step.
-- Returns true when the match's drawing/guessing rounds are complete.
function MatchCore.finalizeStep(self): boolean
	if self:isComplete() then
		return true
	end
	local kind = self:currentKind()
	for _, userId in self.userIds do
		if not self.submitted[userId] then
			local bookIndex = self:bookIndexFor(userId) :: number
			local content
			if kind == "Draw" then
				content = self.opts.emptyDrawing()
			else
				content = if self.left[userId] then self.opts.guessLeftText else self.opts.guessTimeoutText
			end
			self.books[bookIndex].entries[self.step + 1] = {
				kind = kind,
				author = userId,
				content = content,
				auto = true,
				id = if kind == "Draw" then self:_registerDrawing(bookIndex, self.step + 1) else nil,
			}
		end
	end
	self.step += 1
	self.submitted = {}
	return self:isComplete()
end

-- Anonymous reveal data: prompts and entries only, no authors.
function MatchCore.getRevealBooks(self)
	local out = {}
	for i, book in self.books do
		local entries = {}
		for j, e in book.entries do
			entries[j] = { kind = e.kind, content = e.content, auto = e.auto, fallback = e.fallback, id = e.id }
		end
		out[i] = { index = i, prompt = book.prompt.Phrase, entries = entries }
	end
	return out
end

-- Server-only list of real (non-placeholder) entries of a kind, with authors.
function MatchCore.getEntries(self, kind: string)
	local out = {}
	for b, book in self.books do
		for j, e in book.entries do
			if e.kind == kind and not e.auto and not e.fallback
				and not (kind == "Draw" and self.opts.isBlankDrawing(e.content)) then
				table.insert(out, { author = e.author, content = e.content, bookIndex = b, entryIndex = j, id = e.id })
			end
		end
	end
	return out
end

-- Participation data for Rewards.compute.
function MatchCore.getParticipants(self, isPresent: (number) -> boolean)
	local out = {}
	for _, userId in self.userIds do
		table.insert(out, {
			userId = userId,
			stillPresent = not self.left[userId] and isPresent(userId),
			activeSubmissions = self.activeSubmissions[userId],
			totalTasks = self.n,
		})
	end
	return out
end

return MatchCore
