--!strict
-- Net: creates the RemoteEvents listed in RemoteDefinitions and wraps client handlers
-- with per-remote rate limiting and error isolation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteDefinitions = require(Shared.RemoteDefinitions)
local RateLimiter = require(script.Parent.Parent.Logic.RateLimiter)

local Net = {}

local folder = Instance.new("Folder")
folder.Name = RemoteDefinitions.FolderName
local events: { [string]: RemoteEvent } = {}
for _, name in RemoteDefinitions.Events do
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = folder
	events[name] = ev
end
folder.Parent = ReplicatedStorage

function Net.event(name: string): RemoteEvent
	local ev = events[name]
	assert(ev, "unknown remote " .. name)
	return ev
end

function Net.fire(player: Player, name: string, ...)
	if player.Parent == Players then
		Net.event(name):FireClient(player, ...)
	end
end

function Net.fireAll(name: string, ...)
	Net.event(name):FireAllClients(...)
end

function Net.notify(player: Player, text: string, kind: string?)
	Net.fire(player, "Notify", text, kind or "info")
end

function Net.notifyAll(text: string, kind: string?)
	Net.fireAll("Notify", text, kind or "info")
end

local limiters: { RateLimiter.RateLimiter } = {}

-- Connects a client -> server handler. `limit` = { Count, Window } from GameConfig.RateLimits.
function Net.on(name: string, limit: { Count: number, Window: number }, handler: (Player, ...any) -> ())
	local limiter = RateLimiter.new(limit.Count, limit.Window)
	table.insert(limiters, limiter)
	Net.event(name).OnServerEvent:Connect(function(player: Player, ...)
		if not limiter:allow(player.UserId) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(string.format("[Net] %s handler error for %s: %s", name, player.Name, tostring(err)))
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	for _, limiter in limiters do
		limiter:forget(player.UserId)
	end
end)

return Net
