--!strict
-- Doodle Disaster client entry point: starts controllers and routes personal tasks.

local StarterGui = game:GetService("StarterGui")

local Controllers = script.Parent:WaitForChild("Controllers")
local ClientState = require(Controllers.ClientState)
local CameraController = require(Controllers.CameraController)
local MovementController = require(Controllers.MovementController)
local UIController = require(Controllers.UIController)
local DrawingController = require(Controllers.DrawingController)
local GuessController = require(Controllers.GuessController)
local RevealController = require(Controllers.RevealController)
local VotingController = require(Controllers.VotingController)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

ClientState.start()
CameraController.start()
MovementController.start()
UIController.start()
DrawingController.start()
GuessController.start()
RevealController.start()
VotingController.start()

local function closeTasks()
	DrawingController.close()
	GuessController.close()
end

ClientState.remote("TaskAssigned").OnClientEvent:Connect(function(t)
	if type(t) ~= "table" then
		return
	end
	if t.submitted then
		closeTasks()
		UIController.setWaiting(true)
		return
	end
	UIController.setWaiting(false)
	if t.kind == "Draw" then
		GuessController.close()
		DrawingController.open(t)
	else
		DrawingController.close()
		GuessController.open(t)
	end
end)

ClientState.remote("TaskCleared").OnClientEvent:Connect(function()
	closeTasks()
	UIController.setWaiting(false)
end)

ClientState.Changed:Connect(function(snapshot)
	-- Safety net: never leave a task screen open outside drawing/guessing phases.
	if snapshot.phase ~= "Drawing" and snapshot.phase ~= "Guessing" then
		closeTasks()
		UIController.setWaiting(false)
	end
end)

ClientState.requestSync()
