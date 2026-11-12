--!strict
-- RewardManager: grants Doodle Points exactly once per match per player.
-- Eligibility and amounts come from the pure Rewards module; the client never sends
-- any reward-related values.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Rewards = require(script.Parent.Parent.Logic.Rewards)
local PlayerDataManager = require(script.Parent.PlayerDataManager)
local Net = require(script.Parent.Net)

local RewardManager = {}

local granted: { [string]: boolean } = {} -- "matchId:userId" -> true

local function isPresent(userId: number): boolean
	return Players:GetPlayerByUserId(userId) ~= nil
end

-- Returns { [userId]: grant } for display.
function RewardManager.grantMatch(matchId: number, core: any, awardCounts: { [number]: number })
	local participants = core:getParticipants(isPresent)
	local grants = Rewards.compute(participants, awardCounts, GameConfig.Rewards)
	for userId, grant in grants do
		local key = matchId .. ":" .. userId
		if not granted[key] then
			granted[key] = true
			local player = Players:GetPlayerByUserId(userId)
			if player then
				PlayerDataManager.applyGrant(player, grant)
				local text = string.format("+%d Doodle Points!", grant.points)
				if grant.awards > 0 then
					text ..= string.format(" (%d award bonus)", grant.awards)
				end
				Net.notify(player, text, "success")
			end
		end
	end
	for _, p in participants do
		if not grants[p.userId] then
			local player = Players:GetPlayerByUserId(p.userId)
			if player then
				Net.notify(player, "No points this time: submit more of your own work to earn Doodle Points.", "info")
			end
		end
	end
	return grants
end

return RewardManager
