--!strict
-- SkipVote: majority fast-forward voting for the shared reveal. Pure logic.
--
-- Votes are kept per scope ("Entry" = the step on screen, "Book" = the rest of the current
-- sketchbook). A scope passes when a strict majority of the *currently eligible* voters has
-- voted for it, so one player can never advance everyone (except when playing alone), and
-- votes from players who left stop counting.

local SkipVote = {}
SkipVote.__index = SkipVote

SkipVote.Scopes = { Entry = true, Book = true }

function SkipVote.needed(eligibleCount: number): number
	return eligibleCount // 2 + 1
end

function SkipVote.new()
	local self = setmetatable({}, SkipVote)
	self.votes = {} :: { [string]: { [number]: boolean } }
	return self
end

-- Returns true if this is a new vote.
function SkipVote.cast(self, scope: any, userId: number): boolean
	if type(scope) ~= "string" or not SkipVote.Scopes[scope] then
		return false
	end
	local set = self.votes[scope]
	if not set then
		set = {}
		self.votes[scope] = set
	end
	if set[userId] then
		return false
	end
	set[userId] = true
	return true
end

function SkipVote.reset(self, scope: string)
	self.votes[scope] = nil
end

function SkipVote.count(self, scope: string, eligible: { number }): number
	local set = self.votes[scope]
	if not set then
		return 0
	end
	local c = 0
	for _, userId in eligible do
		if set[userId] then
			c += 1
		end
	end
	return c
end

function SkipVote.passed(self, scope: string, eligible: { number }): boolean
	local n = #eligible
	return n > 0 and self:count(scope, eligible) >= SkipVote.needed(n)
end

return SkipVote
