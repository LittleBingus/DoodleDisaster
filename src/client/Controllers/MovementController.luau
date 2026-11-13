--!strict
-- MovementController: mirrors the server's seating lock on the client so input feels
-- right (the server independently zeroes WalkSpeed/JumpHeight, which is authoritative).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Phases = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Phases"))
local ClientState = require(script.Parent.ClientState)

local MovementController = {}

local playerModule: any = nil

-- Roblox ships PlayerModule at StarterPlayer.PlayerModule; older layouts cloned it into
-- PlayerScripts. Never yields: apply() runs again on every state change, so a module that
-- isn't there yet is picked up later.
local function getPlayerModule(): any
	if playerModule then
		return playerModule
	end
	local playerScripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local module = StarterPlayer:FindFirstChild("PlayerModule")
		or (playerScripts and playerScripts:FindFirstChild("PlayerModule"))
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			playerModule = result
		end
	end
	return playerModule
end

local function setControlsEnabled(enabled: boolean)
	local module = getPlayerModule()
	if not module then
		return
	end
	local controlModule = module.ControlModule
	if type(controlModule) == "table" and type(controlModule.Enabled) == "boolean" then
		controlModule.Enabled = enabled
	elseif type(module.GetControls) == "function" then
		-- Legacy PlayerModule API.
		local controls = module:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function apply()
	local seated = Phases.Seated[ClientState.phase()] == true and ClientState.isParticipant()
	setControlsEnabled(not seated)
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
