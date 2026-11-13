--!strict
-- GameState: the single source of truth for the current phase and lobby/match settings.
-- Validates every phase transition and broadcasts a snapshot to clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)
local Net = require(script.Parent.Net)

local GameState = {}

GameState.phase = Phases.WaitingForPlayers
GameState.endsAt = 0 -- workspace:GetServerTimeNow() timestamp, 0 = no timer
GameState.matchId = 0
GameState.step = 0
GameState.totalSteps = 0
GameState.participants = {} :: { [number]: boolean } -- userIds in the current match
GameState.stations = {} :: { [number]: number } -- userId -> station index
GameState.ready = {} :: { [number]: boolean }
GameState.submitted = {} :: { [number]: boolean } -- for "waiting on N players" UI
GameState.difficulty = GameConfig.DefaultDifficulty
GameState.isPrivate = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
GameState.hostUserId = nil :: number?
GameState.lastAwardText = "No awards yet. Be the first legend!"
GameState.devMode = false
if GameConfig.DevMode.Enabled and RunService:IsStudio() then
	-- Studio multiplayer tests can pass { devMode = false } as test args to exercise the
	-- real player minimum. Unreachable on live servers because of the IsStudio check.
	local ok, args = pcall(function()
		return game:GetService("StudioTestService"):GetTestArgs()
	end)
	GameState.devMode = not (ok and type(args) == "table" and args.devMode == false)
	-- { privateServer = true } lets the host-controlled lobby be tested in Studio, where real
	-- private servers don't exist. Also unreachable on live servers.
	if ok and type(args) == "table" and args.privateServer == true then
		GameState.isPrivate = true
	end
end

local changed = Instance.new("BindableEvent")
GameState.Changed = changed.Event -- fires (newPhase, oldPhase)

function GameState.getMinPlayers(): number
	-- Development mode can only lower the requirement inside Roblox Studio.
	if GameState.devMode then
		return GameConfig.DevMode.MinPlayers
	end
	return GameConfig.MinPlayers
end

function GameState.now(): number
	return workspace:GetServerTimeNow()
end

function GameState.timeLeft(): number
	if GameState.endsAt <= 0 then
		return 0
	end
	return math.max(0, GameState.endsAt - GameState.now())
end

function GameState.isParticipant(player: Player): boolean
	return GameState.participants[player.UserId] == true
end

function GameState.snapshot()
	local roster = {}
	for _, p in Players:GetPlayers() do
		table.insert(roster, {
			userId = p.UserId,
			name = p.DisplayName,
			ready = GameState.ready[p.UserId] ~= false,
			inMatch = GameState.participants[p.UserId] == true,
			station = GameState.stations[p.UserId],
			submitted = GameState.submitted[p.UserId] == true,
		})
	end
	return {
		phase = GameState.phase,
		phaseName = Phases.DisplayNames[GameState.phase],
		endsAt = GameState.endsAt,
		matchId = GameState.matchId,
		step = GameState.step,
		totalSteps = GameState.totalSteps,
		difficulty = GameState.difficulty,
		isPrivate = GameState.isPrivate,
		hostUserId = GameState.hostUserId,
		minPlayers = GameState.getMinPlayers(),
		maxPlayers = GameConfig.MaxPlayers,
		devMode = GameState.devMode,
		roster = roster,
		lastAwardText = GameState.lastAwardText,
	}
end

local broadcastQueued = false
-- Coalesces multiple changes in the same frame into one broadcast.
function GameState.broadcast()
	if broadcastQueued then
		return
	end
	broadcastQueued = true
	task.defer(function()
		broadcastQueued = false
		Net.fireAll("StateChanged", GameState.snapshot())
	end)
end

function GameState.sendTo(player: Player)
	Net.fire(player, "StateChanged", GameState.snapshot())
end

-- Validated phase transition. Returns false (and warns) on an illegal transition.
function GameState.setPhase(phase: string, duration: number?): boolean
	local old = GameState.phase
	if not Phases.canTransition(old, phase) then
		warn(string.format("[GameState] illegal transition %s -> %s", old, phase))
		return false
	end
	GameState.phase = phase
	GameState.endsAt = if duration and duration > 0 then GameState.now() + duration else 0
	GameState.submitted = {}
	changed:Fire(phase, old)
	GameState.broadcast()
	return true
end

function GameState.setTimer(duration: number)
	GameState.endsAt = GameState.now() + duration
	GameState.broadcast()
end

return GameState
