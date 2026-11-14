--!strict
-- CameraController: locked 2.5D classroom camera (client-side presentation only).
-- The camera is Scriptable and re-asserted every frame, so players cannot rotate or zoom
-- it and it survives respawns. During the reveal it eases slightly toward the projector.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ClientState = require(script.Parent.ClientState)

local CameraController = {}

local camera = workspace.CurrentCamera
local LOOK_AT = Vector3.new(0, 2, -4)
local BASE_POS = Vector3.new(0, 74, 70)
-- The reveal view eases in only slightly: a tighter shot hid the suspicious button and the
-- trash can at every window size.
local REVEAL_POS = Vector3.new(0, 66, 64)
local REVEAL_LOOK = Vector3.new(0, 5, -8)
-- Horizontal half-extent (tan(fov/2) * aspect) of the reference 16:10 landscape view.
local REFERENCE_HALF_WIDTH = 0.746

local blend = Instance.new("NumberValue") -- 0 = classroom, 1 = reveal focus
blend.Value = 0

local function fovForViewport(): number
	local size = camera.ViewportSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	-- Narrow (portrait / tablet) screens need a wider vertical FOV to keep the room in view.
	if aspect >= 1.6 then
		return 50
	elseif aspect >= 1.2 then
		return 58
	end
	return 78
end

-- Narrow viewports see less of the room sideways, so the camera backs away to keep the whole
-- classroom (and its interactive props) in frame.
function CameraController.distanceScale(fovDegrees: number, aspect: number): number
	local halfWidth = math.tan(math.rad(fovDegrees / 2)) * aspect
	return math.clamp(REFERENCE_HALF_WIDTH / math.max(halfWidth, 0.01), 1, 2.4)
end

local function targetCFrame(): CFrame
	local t = blend.Value
	local pos = BASE_POS:Lerp(REVEAL_POS, t)
	local look = LOOK_AT:Lerp(REVEAL_LOOK, t)
	local size = camera.ViewportSize
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	local scale = CameraController.distanceScale(fovForViewport(), aspect)
	return CFrame.lookAt(look + (pos - look) * scale, look)
end

local function setFocus(reveal: boolean)
	TweenService:Create(blend, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Value = if reveal then 1 else 0 }):Play()
end

function CameraController.start()
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 128
	RunService:BindToRenderStep("DoodleCamera", Enum.RenderPriority.Camera.Value + 1, function()
		camera = workspace.CurrentCamera
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		camera.FieldOfView = fovForViewport()
		camera.CFrame = targetCFrame()
	end)
	ClientState.Changed:Connect(function(snapshot)
		setFocus(snapshot.phase == "Reveal")
	end)
end

return CameraController
