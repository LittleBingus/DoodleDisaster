--!strict
-- ModerationManager: player reports of drawings and per-viewer hiding.
--
-- Drawings can't go through Roblox's text filter, so players get two tools:
--   * Hide (client only): replaces one drawing with a placeholder for that viewer.
--   * Report (here): records the drawing, its author and the match for the owner to review,
--     and stops sending that author's drawings to the reporter for the rest of this server.
-- Reports never punish anyone automatically. Roblox's own Report Abuse menu is untouched
-- and is the way to report a player to Roblox.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local ReportLog = require(script.Parent.Parent.Logic.ReportLog)
local Net = require(script.Parent.Net)

local ModerationManager = {}

local cfg = GameConfig.Moderation
local log = ReportLog.new({ PerMatch = cfg.ReportsPerMatch, PerSession = cfg.ReportsPerSession })
local currentMatchId = 0
local currentCore: any = nil
local saved = 0

local MESSAGES = {
	["unknown drawing"] = "That drawing can't be reported any more.",
	["nothing to report"] = "There's nothing on that page to report.",
	["own drawing"] = "That one is yours!",
	["already reported"] = "You already reported that drawing.",
	["too many reports"] = "You've sent a lot of reports. Use the Roblox menu to report a player.",
}

local store: DataStore? = nil
local function getStore(): DataStore?
	if store == nil then
		local name = if RunService:IsStudio() then cfg.StudioReportStoreName else cfg.ReportStoreName
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(name)
		end)
		if ok then
			store = result
		else
			warn("[Moderation] report store unavailable: " .. tostring(result))
		end
	end
	return store
end

local function save(record: any)
	saved += 1
	local job = if game.JobId ~= "" then string.sub(game.JobId, 1, 8) else "studio"
	local key = string.format("%d_%s_%d", record.time, job, saved) -- well under the 50 character limit
	task.spawn(function()
		local s = getStore()
		if not s then
			return
		end
		for attempt = 1, 3 do
			local ok, err = pcall(function()
				s:SetAsync(key, record, { record.authorId, record.reporterId })
			end)
			if ok then
				return
			end
			warn(string.format("[Moderation] saving report %s failed (attempt %d): %s", key, attempt, tostring(err)))
			task.wait(attempt * 2)
		end
	end)
end

-- Called by RoundManager when a match starts (core) and when it is torn down (nil).
function ModerationManager.setMatch(matchId: number, core: any)
	currentMatchId = matchId
	currentCore = core
end

-- True when `viewer` asked (by reporting) not to see this author's drawings.
function ModerationManager.isBlocked(viewerId: number, authorId: number?): boolean
	return log:isBlocked(viewerId, authorId)
end

-- True when the drawing with this id must not be sent to `viewer`.
function ModerationManager.hiddenFor(viewerId: number, drawId: any): boolean
	if not currentCore or drawId == nil then
		return false
	end
	local target = currentCore:getDrawing(drawId)
	return target ~= nil and log:isBlocked(viewerId, target.author)
end

local function onReport(player: Player, drawId: any)
	local target = if currentCore then currentCore:getDrawing(drawId) else nil
	local ok, reason = log:submit(player.UserId, currentMatchId, drawId, target)
	if not ok then
		Net.fire(player, "ReportResult", drawId, false, MESSAGES[reason :: string] or "That report didn't go through.")
		return
	end
	save({
		time = os.time(),
		placeVersion = game.PlaceVersion,
		matchId = currentMatchId,
		drawId = drawId,
		bookIndex = target.bookIndex,
		entryIndex = target.entryIndex,
		authorId = target.author,
		reporterId = player.UserId,
		reportersOfAuthorThisServer = log:reporterCount(target.author),
		drawing = target.content,
	})
	print(string.format("[Moderation] drawing %s (match %d) by %d reported by %d", drawId, currentMatchId,
		target.author, player.UserId))
	Net.fire(player, "ReportResult", drawId, true,
		"Report saved. You won't be shown that artist's drawings for the rest of this class. To report a player to Roblox, use the Roblox menu.")
end

function ModerationManager.init()
	Net.on("ReportDrawing", GameConfig.RateLimits.Report, onReport)
end

return ModerationManager
