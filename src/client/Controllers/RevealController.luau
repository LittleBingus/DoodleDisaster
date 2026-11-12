--!strict
-- RevealController: presents the server-paced shared reveal. The server decides what is
-- shown and when (RevealEvent); every client renders the same step on a full-screen
-- overlay and on the classroom projector. Players can hide the overlay to watch the
-- projector while walking around and reacting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DrawingRenderer = require(Shared.DrawingRenderer)
local DrawingTypes = require(Shared.DrawingTypes)
local ClientState = require(script.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Ui = require(script.Parent.Ui)

local T = Ui.Theme
local RevealController = {}

type View = { root: GuiObject, title: TextLabel, stage: Frame, caption: TextLabel, dots: Frame }

local gui: ScreenGui
local overlay: View
local projector: View?
local hideButton: TextButton
local overlayHidden = false
local floatLayer: Frame

local function makeView(parent: Instance, isProjector: boolean): View
	local root = if isProjector
		then Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.Paper, Parent = parent })
		else Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.82, 0.74), BackgroundColor3 = T.Paper, Parent = parent })
	if not isProjector then
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(1100, 760), Parent = root })
	end
	Ui.padding(if isProjector then 20 else 12).Parent = root
	local title = Ui.label("📖 The Big Reveal", { Size = UDim2.new(1, 0, 0.11, 0), MaxTextSize = if isProjector then 80 else 34,
		Parent = root })
	local stage = Ui.new("Frame", { Position = UDim2.fromScale(0, 0.13), Size = UDim2.fromScale(1, 0.68),
		BackgroundTransparency = 1, Parent = root })
	local caption = Ui.label("", { Position = UDim2.fromScale(0, 0.82), Size = UDim2.fromScale(1, 0.1),
		MaxTextSize = if isProjector then 60 else 26, Parent = root })
	local dots = Ui.new("Frame", { Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.06),
		BackgroundTransparency = 1, Parent = root })
	Ui.list(Enum.FillDirection.Horizontal, 6).Parent = dots
	return { root = root, title = title, stage = stage, caption = caption, dots = dots }
end

local function setDots(view: View, count: number, current: number)
	Ui.clear(view.dots, { "UIListLayout" })
	for i = 1, count do
		local d = Ui.new("Frame", { Size = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = if i <= current then T.Pink else T.Grey,
			LayoutOrder = i, Parent = view.dots }, { Ui.corner(100) })
		Ui.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = d })
	end
end

local function bubble(view: View, text: string, color: Color3)
	Ui.clear(view.stage)
	local b = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.7), BackgroundColor3 = color, Parent = view.stage })
	Ui.padding(16).Parent = b
	Ui.label(text, { MaxTextSize = 90, Parent = b })
	Ui.pop(b)
end

local function drawing(view: View, data: any)
	Ui.clear(view.stage)
	local canvas = DrawingRenderer.makeCanvas({ Parent = view.stage })
	Ui.stroke(4).Parent = canvas
	DrawingRenderer.render(canvas, data)
	if type(data) ~= "table" or DrawingTypes.isBlank(data) then
		Ui.label("(the artist stared at the blank page...)", { Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.4),
			TextColor3 = Color3.fromRGB(150, 150, 160), MaxTextSize = 40, ZIndex = 5, Parent = canvas })
	end
	Ui.pop(canvas)
end

local function applyToViews(fn: (View) -> ())
	fn(overlay)
	if projector then
		fn(projector)
	end
end

local function onEvent(ev: any)
	if type(ev) ~= "table" then
		return
	end
	if ev.type == "Book" then
		gui.Enabled = true
		overlay.root.Visible = not overlayHidden
		applyToViews(function(v)
			v.title.Text = string.format("📖 Sketchbook %d of %d", ev.bookIndex, ev.bookCount)
			bubble(v, "“" .. tostring(ev.prompt) .. "”", T.Yellow)
			v.caption.Text = "It all started with..."
			setDots(v, ev.bookCount, 0)
		end)
	elseif ev.type == "Entry" then
		applyToViews(function(v)
			if ev.kind == "Draw" then
				drawing(v, ev.content)
				v.caption.Text = if ev.entryIndex == 1 then "...which was drawn as:" else "...which became:"
			else
				bubble(v, "“" .. tostring(ev.content) .. "”", if ev.auto then T.Grey else T.Blue)
				v.caption.Text = "...which someone guessed was:"
			end
			setDots(v, ev.entryCount, ev.entryIndex)
		end)
	elseif ev.type == "BookEnd" then
		applyToViews(function(v)
			local final = ev.final
			local ending = if final and final.kind == "Guess" then "“" .. tostring(final.content) .. "”" else "a drawing"
			bubble(v, string.format("Started as “%s”\n⬇️\nEnded as %s", tostring(ev.prompt), ending), T.Pink)
			v.caption.Text = "😂 What a journey!"
		end)
	elseif ev.type == "Finished" then
		applyToViews(function(v)
			bubble(v, "That's every sketchbook!\nTime to vote for the awards...", T.Green)
			v.caption.Text = ""
		end)
	end
end

local function floatReaction(_userId: number, emoji: string)
	if not gui.Enabled then
		return
	end
	local l = Ui.label(emoji, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(math.random(10, 90) / 100, 1),
		Size = UDim2.fromOffset(56, 56), MaxTextSize = 56, Parent = floatLayer })
	TweenService:Create(l, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(l.Position.X.Scale, 0.2), TextTransparency = 1 }):Play()
	task.delay(2.3, function()
		l:Destroy()
	end)
end

local function showIdleProjector()
	if not projector then
		return
	end
	local s = ClientState.snapshot
	projector.title.Text = "DOODLE DISASTER"
	bubble(projector, if s then (s.phaseName or s.phase) else "Welcome!", T.Yellow)
	projector.caption.Text = "✏️ Draw badly. Guess wildly. Laugh loudly."
	Ui.clear(projector.dots, { "UIListLayout" })
end

function RevealController.start()
	gui = Ui.screenGui("RevealGui", 8)
	gui.Enabled = false
	overlay = makeView(gui, false)
	floatLayer = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20, Parent = gui })
	hideButton = Ui.button("📽 Watch projector", T.Purple, function()
		overlayHidden = not overlayHidden
		overlay.root.Visible = not overlayHidden
		hideButton.Text = if overlayHidden then "🖼 Show overlay" else "📽 Watch projector"
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(190, 44), Parent = gui })

	task.spawn(function()
		local classroom = workspace:WaitForChild("Classroom", 30)
		local screen = classroom and classroom:WaitForChild("ProjectorScreen", 30)
		local surface = screen and screen:WaitForChild("ScreenGui", 30)
		if surface then
			projector = makeView(surface, true)
			showIdleProjector()
		end
	end)

	ClientState.remote("RevealEvent").OnClientEvent:Connect(onEvent)
	UIController.onReaction(floatReaction)
	ClientState.Changed:Connect(function(snapshot)
		if snapshot.phase ~= "Reveal" then
			gui.Enabled = false
			if snapshot.phase ~= "AwardVoting" then
				showIdleProjector()
			end
		end
	end)
end

return RevealController
