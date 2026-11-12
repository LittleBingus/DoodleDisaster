--!strict
-- ClassroomInteractionManager: harmless, cosmetic classroom toys driven by ProximityPrompts.
-- None of them affect scoring or fairness, and all prompts are disabled while players are
-- seated drawing or guessing.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)
local GameState = require(script.Parent.GameState)
local Net = require(script.Parent.Net)

local ClassroomInteractionManager = {}

local CHALKBOARD_LINES = {
	"Today's lesson: confidence > talent",
	"Homework: draw a horse. Any horse.",
	"Reminder: stick figures are a valid art style",
	"Rule #1: no crying over spilled paint",
	"Pop quiz: what is THAT supposed to be?",
	"Fun fact: every masterpiece started as a scribble",
}

local JOKES = {
	"The chalkboard whispers: 'Draw it like you mean it.'",
	"Someone wrote 'Ms. Doodle is the best teacher' in tiny letters.",
	"There's a doodle of a potato wearing sunglasses in the corner.",
	"It says: 'Erasers are for quitters.'",
}

local prompts: { ProximityPrompt } = {}
local classroom: any
local buttonReadyAt = 0
local lastThrow: { [number]: number } = {}
local activeBalls = 0
local rng = Random.new()

local function makePrompt(parent: Instance, action: string, object: string, distance: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	table.insert(prompts, prompt)
	return prompt
end

local function setPromptsEnabled(enabled: boolean)
	for _, p in prompts do
		p.Enabled = enabled
	end
end

local function chalkboardText(): string
	local phase = GameState.phase
	local line = CHALKBOARD_LINES[rng:NextInteger(1, #CHALKBOARD_LINES)]
	local players = #Players:GetPlayers()
	if phase == Phases.WaitingForPlayers or phase == Phases.Countdown then
		return string.format("%s\n\n%d/%d students • Need %d to start", line, players,
			GameConfig.MaxPlayers, GameState.getMinPlayers())
	end
	return string.format("%s\n\nNow: %s", line, Phases.DisplayNames[phase] or phase)
end

-- Throws a harmless paper ball from the player toward the trash can.
local function throwPaperBall(player: Player)
	local now = os.clock()
	if (lastThrow[player.UserId] or 0) + GameConfig.Interactions.PaperBallCooldown > now then
		return
	end
	if activeBalls >= GameConfig.Interactions.MaxPaperBalls then
		return
	end
	local char = player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	lastThrow[player.UserId] = now
	activeBalls += 1
	local ball = Instance.new("Part")
	ball.Name = "PaperBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(0.9, 0.9, 0.9)
	ball.Color = Color3.fromRGB(250, 250, 240)
	ball.Material = Enum.Material.Fabric
	ball.CanCollide = true
	ball.Massless = true
	ball.Position = head.Position + Vector3.new(0, 1.5, 0)
	ball.Parent = workspace
	ball:SetNetworkOwner(nil)
	-- Ballistic arc into the bin (projectile with fixed flight time).
	local target = (classroom.interactives.trashCan :: BasePart).Position + Vector3.new(0, 2.5, 0)
	local t = 0.9
	local g = workspace.Gravity
	local delta = target - ball.Position
	local velocity = Vector3.new(delta.X / t, (delta.Y + 0.5 * g * t * t) / t, delta.Z / t)
	ball.AssemblyLinearVelocity = velocity
	task.delay(t + 0.05, function()
		if ball.Parent then
			ball.Anchored = true
			TweenService:Create(ball, TweenInfo.new(0.3), { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }):Play()
		end
	end)
	task.delay(1.6, function()
		activeBalls -= 1
		ball:Destroy()
	end)
	local can = classroom.interactives.trashCan :: BasePart
	local original = can.CFrame
	task.delay(t, function()
		TweenService:Create(can, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 3, true),
			{ CFrame = original * CFrame.Angles(math.rad(8), 0, 0) }):Play()
		task.delay(0.6, function()
			can.CFrame = original
		end)
	end)
end

local function confetti(at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = at
	anchor.Parent = workspace
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 95)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 170, 255)),
	})
	emitter.Size = NumberSequence.new(0.6)
	emitter.Speed = NumberRange.new(20, 35)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(200)
	Debris:AddItem(anchor, 4)
end

local EFFECTS: { (Player) -> string } = {
	function()
		confetti(Vector3.new(0, 25, 0))
		return "CONFETTI EVERYWHERE!"
	end,
	function()
		local original = Lighting.Ambient
		task.spawn(function()
			for _ = 1, 12 do
				Lighting.Ambient = Color3.fromHSV(rng:NextNumber(), 0.8, 1)
				task.wait(0.35)
			end
			Lighting.Ambient = original
		end)
		return "DISCO MODE ACTIVATED!"
	end,
	function()
		for _ = 1, 14 do
			local duck = Instance.new("Part")
			duck.Name = "RubberDuck"
			duck.Shape = Enum.PartType.Ball
			duck.Size = Vector3.new(1.6, 1.6, 1.6)
			duck.Color = Color3.fromRGB(255, 220, 40)
			duck.Position = Vector3.new(rng:NextNumber(-40, 40), 32, rng:NextNumber(-25, 30))
			duck.CanCollide = true
			duck.Parent = workspace
			Debris:AddItem(duck, 6)
		end
		return "IT'S RAINING RUBBER DUCKS!"
	end,
	function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hum and root and not hum.SeatPart then
			root.AssemblyLinearVelocity = Vector3.new(0, 80, 0)
		end
		return player.DisplayName .. " got launched by the button!"
	end,
}

local function pressButton(player: Player)
	local now = os.clock()
	if now < buttonReadyAt then
		Net.notify(player, string.format("The button is recharging... (%ds)", math.ceil(buttonReadyAt - now)), "info")
		return
	end
	buttonReadyAt = now + GameConfig.Interactions.SuspiciousButtonCooldown
	local button = classroom.interactives.button :: BasePart
	local original = button.CFrame
	TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ CFrame = original * CFrame.new(-0.3, 0, 0) }):Play()
	local message = EFFECTS[rng:NextInteger(1, #EFFECTS)](player)
	Net.notifyAll("🔴 " .. message, "info")
	classroom.interactives.chalkboardText.Text = "WHO PRESSED THE BUTTON?!\n" .. message
end

function ClassroomInteractionManager.init(builtClassroom: any)
	classroom = builtClassroom
	local i = classroom.interactives

	makePrompt(i.chalkboardLedge, "Read", "Chalkboard").Triggered:Connect(function(player)
		Net.notify(player, JOKES[rng:NextInteger(1, #JOKES)], "info")
	end)
	makePrompt(i.trashCan, "Throw paper ball", "Trash Can", 25).Triggered:Connect(throwPaperBall)
	makePrompt(i.button, "Press", "Suspicious Button").Triggered:Connect(pressButton)
	makePrompt(i.pencil, "Inspect", "Golden Pencil").Triggered:Connect(function(player)
		Net.notify(player, "🏆 Latest legend: " .. GameState.lastAwardText:gsub("\n", " - "), "success")
	end)

	local function refresh()
		i.chalkboardText.Text = chalkboardText()
		i.pencilText.Text = "🏆 " .. GameState.lastAwardText
		setPromptsEnabled(not Phases.Seated[GameState.phase])
	end
	GameState.Changed:Connect(refresh)
	refresh()
	task.spawn(function()
		while true do
			task.wait(12)
			refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastThrow[player.UserId] = nil
	end)
end

return ClassroomInteractionManager
