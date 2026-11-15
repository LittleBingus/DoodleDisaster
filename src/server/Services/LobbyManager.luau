--!strict
-- LobbyManager: waiting room, ready toggles, host controls and the start countdown.
--
-- Public servers: when enough ready players are present a 15 s countdown starts; it
--   cancels if the count drops below the minimum.
-- Private servers: the private server owner (or longest-present player if the owner
--   isn't here) is the host. Nothing starts automatically; the host presses Start once
--   enough players are present, followed by a short countdown.
-- Studio dev mode: like public, with a lower minimum, and the host may also start early.
--
-- Game mode: every ready player has one changeable vote (ModeVote). The votes of the players
-- who actually start are tallied when the countdown ends and the result is locked for the
-- match. The host can start a private match but has no say over the mode beyond their vote.

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
local modeRng = Random.new()

-- Tallies the starters' votes and locks the mode for the match about to begin.
local function lockMode(starters: { Player })
	local ids = {}
	for _, p in starters do
		table.insert(ids, p.UserId)
	end
	local winner, info = GameState.modeVote:pick(ids, function()
		return modeRng:NextNumber()
	end)
	GameState.difficulty = winner
	GameState.modeResult = { votes = info.votes, tie = #info.tied > 1 }
	GameState.modeVote:clear() -- everyone votes afresh for the next match
end

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
				lockMode(eligible)
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
		GameState.modeVote:remove(p.UserId)
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

	Net.on("VoteDifficulty", limit, function(player, difficultyId)
		if GameState.phase ~= Phases.WaitingForPlayers and GameState.phase ~= Phases.Countdown then
			Net.notify(player, "The mode is locked until the next class.", "info")
			return
		end
		if GameState.ready[player.UserId] == false then
			Net.notify(player, "Sitting-out students can't vote. Tap Ready to join in!", "info")
			return
		end
		if GameState.modeVote:cast(player.UserId, difficultyId) then
			GameState.broadcast()
		end
	end)
end

return LobbyManager
