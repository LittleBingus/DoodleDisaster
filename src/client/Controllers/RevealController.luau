--!strict
-- RevealController: presents the server-paced shared reveal. The server decides what is
-- shown and when (RevealEvent); every client renders the same step on a full-screen
-- overlay and on the classroom projector. Players can hide the overlay to watch the
-- projector while walking around and reacting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local ClientState = require(script.Parent.ClientState)
local UIController = require(script.Parent.UIController)
local Ui = require(script.Parent.Ui)
local DrawingGuard = require(script.Parent.DrawingGuard)

local T = Ui.Theme
local RevealController = {}

type View = { root: GuiObject, title: TextLabel, stage: Frame, caption: TextLabel, dots: Frame }

local gui: ScreenGui
local overlay: View
local projector: View?
local hideButton: TextButton
local overlayHidden = false
local floatLayer: Frame
local skipBar: Frame
local skipEntryButton: TextButton
local skipBookButton: TextButton
local skipState = { entrySeq = -1, bookSeq = -1, votedEntry = false, votedBook = false }

local function refreshSkip(status: any?)
	if status then
		if status.entrySeq ~= skipState.entrySeq then
			skipState.entrySeq = status.entrySeq
			skipState.votedEntry = false
		end
		if status.bookSeq ~= skipState.bookSeq then
			skipState.bookSeq = status.bookSeq
			skipState.votedBook = false
		end
		skipEntryButton.Text = string.format("⏩ Skip %d/%d", status.entry, status.needed)
		skipBookButton.Text = string.format("⏭ Next book %d/%d", status.book, status.needed)
	end
	skipEntryButton.BackgroundColor3 = if skipState.votedEntry then T.Grey else T.Orange
	skipBookButton.BackgroundColor3 = if skipState.votedBook then T.Grey else T.Blue
	-- Only people who played this match can vote; spectators just watch.
	skipBar.Visible = ClientState.isParticipant()
end

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

local function drawing(view: View, ev: any)
	Ui.clear(view.stage)
	-- Hide / Report sit on the overlay only; the projector follows the same hidden state.
	local canvas = DrawingGuard.mount(view.stage, ev.content, {
		drawId = ev.drawId,
		serverHidden = ev.hidden == true,
		controls = view == overlay,
		blankText = "(the artist stared at the blank page...)",
		stroke = 4,
	})
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
				drawing(v, ev)
				v.caption.Text = if ev.entryIndex == 1 then "...which was drawn as:" else "...which became:"
			elseif ev.fallback then
				-- The filter blocked the real guess; the server picked a random phrase.
				bubble(v, "“" .. tostring(ev.content) .. "”", T.Orange)
				v.caption.Text = "🎲 ...the hall monitor ate the guess, so the gremlin wrote:"
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

-- Mode announcement ------------------------------------------------------------------------
-- Shown on the projector while sketchbooks are handed out (StartingMatch), so it adds no
-- time to the match. A short sound and a gentle tint of the room go with it.
local MODE_STYLE = {
	CasualChaos = { color = T.Green, tint = Color3.fromRGB(255, 244, 205), speed = 1.15 },
	MixedMadness = { color = T.Yellow, tint = Color3.fromRGB(232, 222, 255), speed = 1 },
	BrainMeltdown = { color = T.Red, tint = Color3.fromRGB(255, 190, 190), speed = 0.72 },
}
local announcedMatch = -1
local tintEffect: ColorCorrectionEffect? = nil
local announceSound: Sound? = nil

local function announceMode(snapshot: any)
	if announcedMatch == snapshot.matchId then
		return
	end
	local mode = GameConfig.Difficulties[snapshot.difficulty]
	local style = MODE_STYLE[snapshot.difficulty] or MODE_STYLE.MixedMadness
	if not mode or not projector then
		return
	end
	announcedMatch = snapshot.matchId
	local view = projector :: View
	view.title.Text = "THE CLASS HAS CHOSEN:"
	bubble(view, string.format("%s %s!", mode.Emoji, string.upper(mode.DisplayName)), style.color)
	local result = snapshot.modeResult
	view.caption.Text = if result and result.votes == 0 then "Nobody voted, so the teacher picked. " .. mode.Subtitle
		elseif result and result.tie then "It was a tie! " .. mode.Subtitle
		else mode.Subtitle
	Ui.clear(view.dots, { "UIListLayout" })
	if not announceSound then
		announceSound = Ui.new("Sound", { Name = "ModeAnnouncement", SoundId = "rbxasset://sounds/victory.wav", Volume = 0.45,
			Parent = SoundService })
	end
	local sound = announceSound :: Sound
	sound.PlaybackSpeed = style.speed
	sound:Play()
	-- One slow fade in and out: no flashing.
	if not tintEffect then
		tintEffect = Ui.new("ColorCorrectionEffect", { Name = "ModeTint", Parent = Lighting })
	end
	local effect = tintEffect :: ColorCorrectionEffect
	TweenService:Create(effect, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { TintColor = style.tint }):Play()
	task.delay(2.4, function()
		TweenService:Create(effect, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ TintColor = Color3.new(1, 1, 1) }):Play()
	end)
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

	skipBar = Ui.new("Frame", { Name = "SkipBar", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10),
		Size = UDim2.fromOffset(190, 100), BackgroundTransparency = 1, Parent = gui })
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = skipBar
	skipEntryButton = Ui.button("⏩ Skip", T.Orange, function()
		if not skipState.votedEntry then
			skipState.votedEntry = true
			ClientState.remote("RevealSkipVote"):FireServer("Entry")
			refreshSkip(nil)
		end
	end, { Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 1, MaxTextSize = 20, Parent = skipBar })
	skipBookButton = Ui.button("⏭ Next book", T.Blue, function()
		if not skipState.votedBook then
			skipState.votedBook = true
			ClientState.remote("RevealSkipVote"):FireServer("Book")
			refreshSkip(nil)
		end
	end, { Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 2, MaxTextSize = 20, Parent = skipBar })
	ClientState.remote("RevealSkipStatus").OnClientEvent:Connect(function(status)
		if type(status) == "table" then
			refreshSkip(status)
		end
	end)

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
			if snapshot.phase == "StartingMatch" then
				announceMode(snapshot)
			elseif snapshot.phase ~= "AwardVoting" then
				showIdleProjector()
			end
		end
	end)
end

return RevealController
