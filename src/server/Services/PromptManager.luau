--!strict
-- PromptManager: builds the match prompt pool and picks prompts by difficulty.
-- Pool = the free Starter Chaos pack + every pack enabled by at least one participant,
-- so unlocked packs add variety without locking anyone out of normal play.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local PromptPacks = require(Shared.PromptPacks)
local PromptSelector = require(script.Parent.Parent.Logic.PromptSelector)
local PlayerDataManager = require(script.Parent.PlayerDataManager)

local PromptManager = {}

local rng = Random.new()
local recentQueue: { string } = {}

local function recentSet(): { [string]: boolean }
	local set = {}
	for _, id in recentQueue do
		set[id] = true
	end
	return set
end

local function remember(prompts: { any })
	for _, p in prompts do
		table.insert(recentQueue, p.Id)
	end
	while #recentQueue > GameConfig.PromptHistorySize do
		table.remove(recentQueue, 1)
	end
end

function PromptManager.buildPool(players: { Player }): ({ any }, { string })
	local packs: { [string]: boolean } = { [PromptPacks.FreePackId] = true }
	for _, player in players do
		for packId in PlayerDataManager.enabledPacks(player) do
			packs[packId] = true
		end
	end
	local pool = {}
	for _, prompt in PromptPacks.Prompts do
		if prompt.Enabled and packs[prompt.Pack] then
			table.insert(pool, prompt)
		end
	end
	local packNames = {}
	for _, pack in PromptPacks.Packs do
		if packs[pack.Id] then
			table.insert(packNames, pack.DisplayName)
		end
	end
	return pool, packNames
end

function PromptManager.pick(players: { Player }, difficultyId: string, count: number): ({ any }, { string })
	local difficulty = GameConfig.Difficulties[difficultyId] or GameConfig.Difficulties[GameConfig.DefaultDifficulty]
	local pool, packNames = PromptManager.buildPool(players)
	local picked = PromptSelector.select(pool, difficulty.Weights, count, function()
		return rng:NextNumber()
	end, recentSet())
	remember(picked)
	return picked, packNames
end

return PromptManager
