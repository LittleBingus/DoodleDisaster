--!strict
-- MovementController: mirrors the server's seating lock on the client so input feels
-- right (the server independently zeroes WalkSpeed/JumpHeight, which is authoritative).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Phases = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Phases"))
local ClientState = require(script.Parent.ClientState)

local MovementController = {}

local controls: any = nil

local function getControls()
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local playerModule = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript)
		return (playerModule :: any):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function apply()
	local c = getControls()
	if not c then
		return
	end
	local seated = Phases.Seated[ClientState.phase()] == true and ClientState.isParticipant()
	if seated then
		c:Disable()
	else
		c:Enable()
	end
end

function MovementController.start()
	ClientState.Changed:Connect(apply)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		apply()
	end)
	task.defer(apply)
end

return MovementController
