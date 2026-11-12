--!strict
-- GameManager: boots every service and runs the endless lobby -> match -> lobby loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)

local GameState = require(script.Parent.GameState)
local Net = require(script.Parent.Net)
local ClassroomBuilder = require(script.Parent.ClassroomBuilder)
local StationManager = require(script.Parent.StationManager)
local PlayerDataManager = require(script.Parent.PlayerDataManager)
local LobbyManager = require(script.Parent.LobbyManager)
local RoundManager = require(script.Parent.RoundManager)
local VotingManager = require(script.Parent.VotingManager)
local ClassroomInteractionManager = require(script.Parent.ClassroomInteractionManager)

local GameManager = {}

local function setupRemotes()
	Net.on("RequestSync", { Count = 5, Window = 5 }, function(player)
		GameState.sendTo(player)
		PlayerDataManager.push(player)
		RoundManager.syncPlayer(player)
	end)

	Net.on("SendReaction", GameConfig.RateLimits.Reaction, function(player, index)
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #GameConfig.Reactions then
			return
		end
		Net.fireAll("ReactionShown", player.UserId, index)
	end)

	Net.on("UnlockPack", GameConfig.RateLimits.Packs, function(player, packId)
		local ok, message = PlayerDataManager.unlockPack(player, packId)
		Net.notify(player, message, if ok then "success" else "warning")
	end)

	Net.on("TogglePack", GameConfig.RateLimits.Packs, function(player, packId, enabled)
		PlayerDataManager.setPackEnabled(player, packId, enabled)
	end)
end

function GameManager.start()
	local classroom = ClassroomBuilder.build()
	StationManager.setStations(classroom.stations)

	setupRemotes()
	PlayerDataManager.init()
	StationManager.init()
	LobbyManager.init()
	RoundManager.init()
	VotingManager.init()
	ClassroomInteractionManager.init(classroom)

	Players.PlayerAdded:Connect(function()
		GameState.broadcast()
	end)
	Players.PlayerRemoving:Connect(function()
		GameState.broadcast()
	end)

	if GameState.devMode then
		print(string.format("[DoodleDisaster] Studio dev mode: matches can start with %d player(s).",
			GameConfig.DevMode.MinPlayers))
	end

	task.spawn(function()
		while true do
			local participants = LobbyManager.waitForStart()
			local ok, err = pcall(RoundManager.runMatch, participants)
			if not ok then
				warn("[GameManager] match crashed: " .. tostring(err))
				Net.notifyAll("The class hamster chewed through a cable. Returning to the lobby.", "warning")
				GameManager.recover()
			end
		end
	end)
end

-- Emergency recovery after an unexpected error: force everyone back to the lobby.
function GameManager.recover()
	StationManager.unlockAll()
	StationManager.clear()
	GameState.participants = {}
	Net.fireAll("TaskCleared")
	GameState.phase = Phases.ReturningToLobby
	GameState.endsAt = 0
	GameState.broadcast()
	task.wait(2)
	GameState.setPhase(Phases.WaitingForPlayers)
end

return GameManager
