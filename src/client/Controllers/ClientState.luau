--!strict
-- ClientState: the client's read-only mirror of server state plus remote access.
-- Nothing here is authoritative; it only drives presentation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)

local ClientState = {}

local remotesFolder = ReplicatedStorage:WaitForChild(RemoteDefinitions.FolderName)
local cache: { [string]: RemoteEvent } = {}

function ClientState.remote(name: string): RemoteEvent
	local r = cache[name]
	if not r then
		r = remotesFolder:WaitForChild(name) :: RemoteEvent
		cache[name] = r
	end
	return r
end

ClientState.player = Players.LocalPlayer
ClientState.snapshot = nil :: any
ClientState.profile = nil :: any

local stateChanged = Instance.new("BindableEvent")
ClientState.Changed = stateChanged.Event -- (snapshot, previousPhase)
local profileChanged = Instance.new("BindableEvent")
ClientState.ProfileChanged = profileChanged.Event

function ClientState.phase(): string
	return if ClientState.snapshot then ClientState.snapshot.phase else "WaitingForPlayers"
end

function ClientState.timeLeft(): number
	local s = ClientState.snapshot
	if not s or not s.endsAt or s.endsAt <= 0 then
		return 0
	end
	return math.max(0, s.endsAt - workspace:GetServerTimeNow())
end

function ClientState.me()
	local s = ClientState.snapshot
	if not s then
		return nil
	end
	for _, r in s.roster do
		if r.userId == ClientState.player.UserId then
			return r
		end
	end
	return nil
end

function ClientState.isParticipant(): boolean
	local me = ClientState.me()
	return me ~= nil and me.inMatch == true
end

function ClientState.isHost(): boolean
	local s = ClientState.snapshot
	return s ~= nil and s.hostUserId == ClientState.player.UserId
end

function ClientState.nameOf(userId: number): string
	local s = ClientState.snapshot
	if s then
		for _, r in s.roster do
			if r.userId == userId then
				return r.name
			end
		end
	end
	return "Someone"
end

function ClientState.start()
	ClientState.remote("StateChanged").OnClientEvent:Connect(function(snapshot)
		local previous = ClientState.phase()
		ClientState.snapshot = snapshot
		stateChanged:Fire(snapshot, previous)
	end)
	ClientState.remote("ProfileUpdated").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		profileChanged:Fire(profile)
	end)
end

function ClientState.requestSync()
	ClientState.remote("RequestSync"):FireServer()
end

return ClientState
