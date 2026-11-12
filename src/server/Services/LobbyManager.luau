--!strict
-- LobbyManager: waiting room, ready toggles, host controls and the start countdown.
--
-- Public servers: when enough ready players are present a 15 s countdown starts; it
--   cancels if the count drops below the minimum. The longest-present player is the
--   "class captain" and may change difficulty.
-- Private servers: the private server owner (or longest-present player if the owner
--   isn't here) is the host. Nothing starts automatically; the host presses Start once
--   enough players are present, followed by a short countdown.
-- Studio dev mode: like public, with a lower minimum, and the host may also start early.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)
local GameState = require(script.Parent.GameState)
local Net = require(script.Parent.Net)

local LobbyManager = {}

local joinOrder: { Player } = {}
local startRequested = false

local function refreshHost()
	local host: Player? = nil
	if GameState.isPrivate then
		host = Players:GetPlayerByUserId(game.PrivateServerOwnerId)
	end
	if not host then
		host = joinOrder[1]
	end
	local id = if host then host.UserId else nil
	if GameState.hostUserId ~= id then
		GameState.hostUserId = id
		GameState.broadcast()
	end
end

function LobbyManager.isHost(player: Player): boolean
	return GameState.hostUserId == player.UserId
end

function LobbyManager.eligiblePlayers(): { Player }
	local out = {}
	for _, p in joinOrder do
		if p.Parent == Players and GameState.ready[p.UserId] ~= false and p.Character then
			table.insert(out, p)
			if #out >= GameConfig.MaxPlayers then
				break
			end
		end
	end
	return out
end

local function canHostStart(): boolean
	return GameState.isPrivate or GameState.devMode
end

-- Blocks until a match should start; returns the participants (in join order).
function LobbyManager.waitForStart(): { Player }
	startRequested = false
	while true do
		local eligible = LobbyManager.eligiblePlayers()
		local enough = #eligible >= GameState.getMinPlayers()
		local phase = GameState.phase

		if phase == Phases.WaitingForPlayers then
			if enough and (startRequested or not GameState.isPrivate) then
				local duration = if startRequested then 5 else GameConfig.Timers.LobbyCountdown
				GameState.setPhase(Phases.Countdown, duration)
			end
			startRequested = false
		elseif phase == Phases.Countdown then
			if not enough then
				GameState.setPhase(Phases.WaitingForPlayers)
				Net.notifyAll("Not enough players. Countdown cancelled.", "warning")
			elseif startRequested and GameState.timeLeft() > 3 then
				-- host skipped the wait
				GameState.setTimer(3)
				startRequested = false
			elseif GameState.timeLeft() <= 0 then
				return eligible
			end
		end
		task.wait(0.2)
	end
end

function LobbyManager.init()
	Players.PlayerAdded:Connect(function(p)
		table.insert(joinOrder, p)
		refreshHost()
		GameState.broadcast()
	end)
	for _, p in Players:GetPlayers() do
		table.insert(joinOrder, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		local i = table.find(joinOrder, p)
		if i then
			table.remove(joinOrder, i)
		end
		GameState.ready[p.UserId] = nil
		refreshHost()
		GameState.broadcast()
	end)
	refreshHost()

	local limit = GameConfig.RateLimits.Lobby
	Net.on("SetReady", limit, function(player, ready)
		if type(ready) ~= "boolean" then
			return
		end
		GameState.ready[player.UserId] = ready
		GameState.broadcast()
	end)

	Net.on("HostStart", limit, function(player)
		if not LobbyManager.isHost(player) then
			Net.notify(player, "Only the host can start the class.", "warning")
			return
		end
		if not canHostStart() then
			Net.notify(player, "Public classes start automatically.", "info")
			return
		end
		if Phases.InMatch[GameState.phase] then
			return
		end
		if #LobbyManager.eligiblePlayers() < GameState.getMinPlayers() then
			Net.notify(player, string.format("Need at least %d ready players.", GameState.getMinPlayers()), "warning")
			return
		end
		startRequested = true
	end)

	Net.on("SetDifficulty", limit, function(player, difficultyId)
		if not LobbyManager.isHost(player) then
			return
		end
		if type(difficultyId) ~= "string" or not GameConfig.Difficulties[difficultyId] then
			return
		end
		if Phases.InMatch[GameState.phase] then
			Net.notify(player, "Difficulty can be changed between matches.", "info")
			return
		end
		GameState.difficulty = difficultyId
		GameState.broadcast()
		Net.notifyAll("Difficulty set to " .. GameConfig.Difficulties[difficultyId].DisplayName .. "!", "info")
	end)
end

return LobbyManager
