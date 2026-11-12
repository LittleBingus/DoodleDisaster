--!strict
-- StationManager: server-authoritative desk assignment, seating and movement locking.
-- During seated phases each participant is seated at their desk with walking/jumping
-- disabled on the server (clients also disable input locally for responsiveness).
-- Respawns are re-seated automatically; everyone is released when the phase ends.

local Players = game:GetService("Players")

local GameState = require(script.Parent.GameState)

local StationManager = {}

local stations: { any } = {}
local locked = false

local DEFAULT_WALKSPEED = 16
local DEFAULT_JUMPHEIGHT = 7.2
local DEFAULT_JUMPPOWER = 50

function StationManager.setStations(list: { any })
	stations = list
end

function StationManager.count(): number
	return #stations
end

local function updateLabels()
	local nameByStation: { [number]: string } = {}
	for userId, index in GameState.stations do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			nameByStation[index] = p.DisplayName
		end
	end
	for i, st in stations do
		st.label.Text = nameByStation[i] or ("Desk " .. i)
	end
end

-- Assigns participants to desks in match order (deterministic).
function StationManager.assign(players: { Player })
	GameState.stations = {}
	for i, p in players do
		if i <= #stations then
			GameState.stations[p.UserId] = i
		end
	end
	updateLabels()
	GameState.broadcast()
end

function StationManager.clear()
	GameState.stations = {}
	updateLabels()
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 or not root then
		return nil, nil
	end
	return hum, root
end

local function lockPlayer(player: Player)
	local index = GameState.stations[player.UserId]
	if not index then
		return
	end
	local st = stations[index]
	local hum, root = getHumanoid(player)
	if not st or not hum or not root then
		return
	end
	hum.WalkSpeed = 0
	hum.JumpHeight = 0
	hum.JumpPower = 0
	local seat = st.seat :: Seat
	if seat.Occupant == hum then
		return
	end
	if seat.Occupant then
		seat.Occupant.Sit = false
	end
	hum.Sit = false
	task.wait()
	root.AssemblyLinearVelocity = Vector3.zero
	;(player.Character :: Model):PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0))
	seat.Disabled = false
	seat:Sit(hum)
	task.delay(0.6, function()
		-- Fallback: if seating failed, hold the character in place next to the desk.
		if locked and seat.Occupant ~= hum and hum.Parent and root.Parent then
			root.Anchored = true
			;(player.Character :: Model):PivotTo(st.standCFrame)
		end
	end)
end

local function unlockPlayer(player: Player)
	local hum, root = getHumanoid(player)
	if not hum or not root then
		return
	end
	local index = GameState.stations[player.UserId]
	local wasSeated = hum.SeatPart ~= nil
	hum.Sit = false
	root.Anchored = false
	hum.WalkSpeed = DEFAULT_WALKSPEED
	hum.JumpHeight = DEFAULT_JUMPHEIGHT
	hum.JumpPower = DEFAULT_JUMPPOWER
	if wasSeated and index and stations[index] then
		task.defer(function()
			if player.Character and root.Parent then
				(player.Character :: Model):PivotTo(stations[index].standCFrame)
			end
		end)
	end
end

function StationManager.lockAll()
	locked = true
	for _, player in Players:GetPlayers() do
		if GameState.stations[player.UserId] then
			task.spawn(lockPlayer, player)
		end
	end
end

function StationManager.unlockAll()
	locked = false
	for _, st in stations do
		st.seat.Disabled = true
	end
	for _, player in Players:GetPlayers() do
		task.spawn(unlockPlayer, player)
	end
end

function StationManager.isLocked(): boolean
	return locked
end

function StationManager.init()
	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2)
			if locked and GameState.stations[player.UserId] then
				lockPlayer(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, p in Players:GetPlayers() do
		hookCharacter(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		if GameState.stations[player.UserId] then
			GameState.stations[player.UserId] = nil
			updateLabels()
		end
	end)
end

return StationManager
