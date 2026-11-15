--!strict
-- ReportLog: accepts or rejects player reports of drawings and remembers who asked not to
-- see whose drawings. Pure logic: storage is done by ModerationManager.
--
-- Rules:
--   * A report must name a real, player-made drawing of the current match.
--   * Nobody can report their own drawing, or the same drawing twice.
--   * Each player has a per-match and a per-session report cap (anti-spam).
--   * A report never punishes anyone. Its only automatic effect is personal: the reporter
--     stops being sent that author's drawings for the rest of the server session.

local ReportLog = {}
ReportLog.__index = ReportLog

export type Limits = { PerMatch: number, PerSession: number }

function ReportLog.new(limits: Limits)
	local self = setmetatable({}, ReportLog)
	self.limits = limits
	self.seen = {} :: { [string]: boolean } -- "reporter:match:drawId"
	self.perMatch = {} :: { [string]: number } -- "reporter:match" -> count
	self.perSession = {} :: { [number]: number }
	self.blocked = {} :: { [number]: { [number]: boolean } } -- viewer -> author -> true
	self.distinctReporters = {} :: { [number]: { [number]: boolean } } -- author -> reporters
	return self
end

-- `target` is what the server resolved the drawing id to: { author, auto, blank } or nil.
-- Returns ok, reason. On success the report is counted and the author is blocked for the
-- reporter.
function ReportLog.submit(self, reporterId: number, matchId: number, drawId: any, target: any): (boolean, string?)
	if type(drawId) ~= "string" or target == nil then
		return false, "unknown drawing"
	end
	if target.auto or target.blank then
		return false, "nothing to report"
	end
	if target.author == reporterId then
		return false, "own drawing"
	end
	local key = string.format("%d:%d:%s", reporterId, matchId, drawId)
	if self.seen[key] then
		return false, "already reported"
	end
	local matchKey = string.format("%d:%d", reporterId, matchId)
	if (self.perMatch[matchKey] or 0) >= self.limits.PerMatch then
		return false, "too many reports"
	end
	if (self.perSession[reporterId] or 0) >= self.limits.PerSession then
		return false, "too many reports"
	end
	self.seen[key] = true
	self.perMatch[matchKey] = (self.perMatch[matchKey] or 0) + 1
	self.perSession[reporterId] = (self.perSession[reporterId] or 0) + 1
	self:block(reporterId, target.author)
	local reporters = self.distinctReporters[target.author]
	if not reporters then
		reporters = {}
		self.distinctReporters[target.author] = reporters
	end
	reporters[reporterId] = true
	return true, nil
end

function ReportLog.block(self, viewerId: number, authorId: number)
	local set = self.blocked[viewerId]
	if not set then
		set = {}
		self.blocked[viewerId] = set
	end
	set[authorId] = true
end

function ReportLog.isBlocked(self, viewerId: number, authorId: number?): boolean
	local set = self.blocked[viewerId]
	return authorId ~= nil and set ~= nil and set[authorId] == true
end

-- How many different players reported this author this session (for the owner's review;
-- never used to punish automatically).
function ReportLog.reporterCount(self, authorId: number): number
	local n = 0
	for _ in self.distinctReporters[authorId] or {} do
		n += 1
	end
	return n
end

return ReportLog
