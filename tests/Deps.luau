-- Shared lookup for test specs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logic = ServerScriptService:WaitForChild("Server"):WaitForChild("Logic")

return {
	GameConfig = require(Shared.GameConfig),
	PromptPacks = require(Shared.PromptPacks),
	Rotation = require(Shared.Rotation),
	DrawingTypes = require(Shared.DrawingTypes),
	Phases = require(Shared.Phases),
	TextRules = require(Shared.TextRules),
	MatchCore = require(Logic.MatchCore),
	VotingCore = require(Logic.VotingCore),
	PromptSelector = require(Logic.PromptSelector),
	Rewards = require(Logic.Rewards),
	RateLimiter = require(Logic.RateLimiter),
}
