--!strict
-- UIController: HUD, lobby panel, packs, toasts, reactions, waiting screen and results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)
local DrawingRenderer = require(Shared.DrawingRenderer)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local T = Ui.Theme
local UIController = {}

local gui: ScreenGui
local hud: { [string]: any } = {}
local lobby: { [string]: any } = {}
local packsModal: Frame
local toastStack: Frame
local waitingPanel: Frame
local waitingText: TextLabel
local spectatorBanner: Frame
local reactionBar: Frame
local resultsPanel: Frame
local resultsList: ScrollingFrame
local waitingActive = false

-- HUD -----------------------------------------------------------------------------------
local function buildHud()
	local bar = Ui.panel({
		Name = "PhaseBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.5, 0, 0, 64),
		BackgroundColor3 = T.Yellow,
		Parent = gui,
	})
	Ui.new("UISizeConstraint", { MinSize = Vector2.new(280, 0), MaxSize = Vector2.new(560, 64), Parent = bar })
	hud.phase = Ui.label("Waiting for players", {
		Size = UDim2.new(0.68, 0, 0.62, 0), Position = UDim2.fromScale(0.03, 0.06), TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30, Parent = bar,
	})
	hud.sub = Ui.label("", {
		Size = UDim2.new(0.68, 0, 0.32, 0), Position = UDim2.fromScale(0.03, 0.64), TextXAlignment = Enum.TextXAlignment.Left,
		Font = T.BodyFont, MaxTextSize = 16, Parent = bar,
	})
	local timerBox = Ui.panel({ Size = UDim2.new(0.26, 0, 0.8, 0), Position = UDim2.fromScale(0.72, 0.1),
		BackgroundColor3 = T.Paper, Parent = bar })
	hud.timer = Ui.label("--", { MaxTextSize = 34, Parent = timerBox })

	local points = Ui.panel({ Name = "Points", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(150, 44), BackgroundColor3 = T.Green, Parent = gui })
	hud.points = Ui.label("✏️ 0", { MaxTextSize = 24, Parent = points })
	hud.packsButton = Ui.button("📚 Packs", T.Pink, function()
		packsModal.Visible = not packsModal.Visible
		if packsModal.Visible then
			Ui.pop(packsModal)
		end
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 58), Size = UDim2.fromOffset(150, 40), Parent = gui })
end

local function updateHud()
	local s = ClientState.snapshot
	if not s then
		return
	end
	hud.phase.Text = s.phaseName or s.phase
	local count = #s.roster
	local diff = GameConfig.Difficulties[s.difficulty]
	local sub = string.format("%d/%d students • %s", count, s.maxPlayers, diff and diff.DisplayName or s.difficulty)
	if s.totalSteps and s.totalSteps > 0 and Phases.Seated[s.phase] then
		sub = string.format("Page %d of %d • %s", s.step + 1, s.totalSteps, sub)
	end
	if s.devMode then
		sub ..= " • DEV"
	end
	hud.sub.Text = sub
	local inLobby = s.phase == Phases.WaitingForPlayers or s.phase == Phases.Countdown
	hud.packsButton.Visible = inLobby or s.phase == Phases.Results
	if not hud.packsButton.Visible then
		packsModal.Visible = false
	end
end

-- Lobby ---------------------------------------------------------------------------------
local function buildLobby()
	local panel = Ui.panel({ Name = "Lobby", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.fromOffset(260, 210), BackgroundColor3 = T.Paper, Parent = gui })
	Ui.padding(10).Parent = panel
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = panel
	lobby.panel = panel
	lobby.status = Ui.label("Waiting for classmates...", { Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 1,
		MaxTextSize = 20, Parent = panel })
	lobby.ready = Ui.button("✅ Ready", T.Green, function()
		local me = ClientState.me()
		local ready = if me then not me.ready else true
		ClientState.remote("SetReady"):FireServer(ready)
	end, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = panel })
	lobby.difficulty = Ui.button("Mixed Madness", T.Blue, function()
		if not ClientState.isHost() then
			return
		end
		local order = GameConfig.DifficultyOrder
		local current = table.find(order, ClientState.snapshot.difficulty) or 1
		ClientState.remote("SetDifficulty"):FireServer(order[current % #order + 1])
	end, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3, Parent = panel })
	lobby.start = Ui.button("🚀 Start class", T.Orange, function()
		ClientState.remote("HostStart"):FireServer()
	end, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 4, Parent = panel })
	lobby.hint = Ui.label("Walk around! Try the button... if you dare.", { Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 5, Font = T.BodyFont, MaxTextSize = 13, TextColor3 = Color3.fromRGB(90, 90, 100), Parent = panel })
end

local function updateLobby()
	local s = ClientState.snapshot
	if not s then
		return
	end
	local inLobby = s.phase == Phases.WaitingForPlayers or s.phase == Phases.Countdown
	lobby.panel.Visible = inLobby
	if not inLobby then
		return
	end
	local readyCount = 0
	for _, r in s.roster do
		if r.ready then
			readyCount += 1
		end
	end
	local me = ClientState.me()
	local isHost = ClientState.isHost()
	if s.phase == Phases.Countdown then
		lobby.status.Text = string.format("Class starts in %d!", math.ceil(ClientState.timeLeft()))
	elseif readyCount < s.minPlayers then
		lobby.status.Text = string.format("Need %d more ready student%s", s.minPlayers - readyCount,
			if s.minPlayers - readyCount == 1 then "" else "s")
	elseif s.isPrivate then
		lobby.status.Text = if isHost then "Everyone's here. Start when ready!" else "Waiting for the host..."
	else
		lobby.status.Text = "Get ready..."
	end
	lobby.ready.Text = if me and me.ready then "✅ Ready" else "💤 Sitting out"
	lobby.ready.BackgroundColor3 = if me and me.ready then T.Green else T.Grey
	local diff = GameConfig.Difficulties[s.difficulty]
	lobby.difficulty.Text = (if isHost then "🎚 " else "") .. (diff and diff.DisplayName or s.difficulty)
	lobby.difficulty.AutoButtonColor = isHost
	lobby.start.Visible = isHost and (s.isPrivate or s.devMode)
	lobby.hint.Text = if isHost then "You're the class captain: tap difficulty to change it." else "Walk around! Try the button... if you dare."
end

-- Packs ---------------------------------------------------------------------------------
local function buildPacks()
	packsModal = Ui.panel({ Name = "Packs", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.62), Visible = false, ZIndex = 20, Parent = gui })
	Ui.new("UISizeConstraint", { MinSize = Vector2.new(300, 300), MaxSize = Vector2.new(560, 520), Parent = packsModal })
	Ui.padding(12).Parent = packsModal
	Ui.label("📚 Word Packs", { Size = UDim2.new(1, -50, 0, 36), MaxTextSize = 30, ZIndex = 21, Parent = packsModal })
	Ui.button("✖", T.Red, function()
		packsModal.Visible = false
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(40, 36), ZIndex = 21,
		Parent = packsModal })
	local list = Ui.new("ScrollingFrame", { Name = "List", Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 1, -46),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ZIndex = 21, Parent = packsModal })
	Ui.list(Enum.FillDirection.Vertical, 8).Parent = list
end

local function updatePacks()
	local profile = ClientState.profile
	hud.points.Text = "✏️ " .. (if profile then tostring(profile.points) else "...")
	local list = packsModal:FindFirstChild("List") :: ScrollingFrame
	Ui.clear(list, { "UIListLayout" })
	if not profile then
		return
	end
	for i, pack in profile.packs do
		local color = Color3.fromRGB(pack.color[1], pack.color[2], pack.color[3])
		local row = Ui.panel({ Size = UDim2.new(1, -10, 0, 86), BackgroundColor3 = color, LayoutOrder = i, ZIndex = 22,
			Parent = list })
		Ui.label(pack.name, { Size = UDim2.new(0.62, 0, 0.42, 0), Position = UDim2.fromScale(0.03, 0.06),
			TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 22, ZIndex = 23, Parent = row })
		Ui.label(pack.description, { Size = UDim2.new(0.62, 0, 0.46, 0), Position = UDim2.fromScale(0.03, 0.5),
			TextXAlignment = Enum.TextXAlignment.Left, Font = T.BodyFont, MaxTextSize = 13, ZIndex = 23, Parent = row })
		local buttonText, buttonColor, action
		if pack.free then
			buttonText, buttonColor = "Always on", T.Grey
		elseif pack.unlocked then
			buttonText = if pack.enabled then "✅ Enabled" else "⬜ Disabled"
			buttonColor = if pack.enabled then T.Green else T.Grey
			action = function()
				ClientState.remote("TogglePack"):FireServer(pack.id, not pack.enabled)
			end
		else
			buttonText = string.format("🔓 %d pts", pack.cost or 0)
			buttonColor = if profile.points >= (pack.cost or math.huge) then T.Yellow else T.Grey
			action = function()
				ClientState.remote("UnlockPack"):FireServer(pack.id)
			end
		end
		Ui.button(buttonText, buttonColor, action or function() end, { AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0.97, 0, 0.5, 0), Size = UDim2.new(0.3, 0, 0, 40), ZIndex = 23, Parent = row })
		if not pack.unlocked and pack.milestone then
			Ui.label(string.format("or free after %d matches", pack.milestone), { AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(0.97, 0, 1, -2), Size = UDim2.new(0.3, 0, 0, 16), Font = T.BodyFont, MaxTextSize = 11,
				ZIndex = 23, Parent = row })
		end
	end
	local stats = Ui.label(string.format("Matches: %d • Awards: %d%s", profile.matchesCompleted, profile.awardsEarned,
		if profile.saveDisabled then " • ⚠️ saving disabled" else ""), {
		Size = UDim2.new(1, 0, 0, 24), Font = T.BodyFont, MaxTextSize = 14, LayoutOrder = 99, ZIndex = 22, Parent = list })
	stats.Name = "Stats"
end

-- Toasts --------------------------------------------------------------------------------
local TOAST_COLORS = { info = T.Blue, success = T.Green, warning = T.Orange }

function UIController.toast(text: string, kind: string?)
	local t = Ui.panel({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = TOAST_COLORS[kind or "info"] or T.Blue, Parent = toastStack })
	Ui.padding(8).Parent = t
	local l = Ui.label(text, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextScaled = false,
		TextSize = 17, Font = T.BodyFont, Parent = t })
	l.TextXAlignment = Enum.TextXAlignment.Left
	Ui.pop(t)
	task.delay(4.5, function()
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.wait(0.3)
		t:Destroy()
	end)
	local items = toastStack:GetChildren()
	local count = 0
	for _, c in items do
		if c:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, c in items do
			if c:IsA("Frame") then
				c:Destroy()
				break
			end
		end
	end
end

local function buildToasts()
	toastStack = Ui.new("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 106),
		Size = UDim2.fromOffset(300, 400), BackgroundTransparency = 1, Parent = gui })
	local layout = Ui.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = toastStack
end

-- Waiting / spectator ---------------------------------------------------------------------
local function buildWaiting()
	waitingPanel = Ui.panel({ Name = "Waiting", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 170), BackgroundColor3 = T.Paper, Visible = false, Parent = gui })
	Ui.padding(14).Parent = waitingPanel
	Ui.label("✏️ Pencils down!", { Size = UDim2.new(1, 0, 0.5, 0), MaxTextSize = 34, Parent = waitingPanel })
	waitingText = Ui.label("Waiting for classmates...", { Size = UDim2.new(1, 0, 0.45, 0), Position = UDim2.fromScale(0, 0.55),
		Font = T.BodyFont, MaxTextSize = 20, Parent = waitingPanel })

	spectatorBanner = Ui.panel({ Name = "Spectator", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -80),
		Size = UDim2.fromOffset(440, 54), BackgroundColor3 = T.Purple, Visible = false, Parent = gui })
	Ui.padding(8).Parent = spectatorBanner
	Ui.label("👀 Class in session! You'll join the next match.", { TextColor3 = Color3.new(1, 1, 1), MaxTextSize = 22,
		Parent = spectatorBanner })
end

function UIController.setWaiting(active: boolean)
	waitingActive = active
	UIController.refreshWaiting()
end

function UIController.refreshWaiting()
	local s = ClientState.snapshot
	local phase = ClientState.phase()
	local show = waitingActive and ClientState.isParticipant() and (phase == Phases.Drawing or phase == Phases.Guessing)
	local collecting = phase == Phases.CollectingSubmissions and ClientState.isParticipant()
	waitingPanel.Visible = show or collecting or phase == Phases.StartingMatch and ClientState.isParticipant()
	if not s then
		return
	end
	if phase == Phases.StartingMatch then
		waitingText.Text = "Grab a pencil. Sketchbooks incoming!"
	elseif collecting then
		waitingText.Text = "Passing sketchbooks to the next desk..."
	else
		local remaining = 0
		for _, r in s.roster do
			if r.inMatch and not r.submitted then
				remaining += 1
			end
		end
		waitingText.Text = string.format("Waiting for %d classmate%s...", remaining, if remaining == 1 then "" else "s")
	end
	spectatorBanner.Visible = Phases.Seated[phase] == true and not ClientState.isParticipant()
end

-- Reactions -----------------------------------------------------------------------------
local function showReactionOverHead(userId: number, emoji: string)
	local p = Players:GetPlayerByUserId(userId)
	local head = p and p.Character and p.Character:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = Ui.new("BillboardGui", { Size = UDim2.fromOffset(60, 60), StudsOffset = Vector3.new(0, 3, 0),
		AlwaysOnTop = true, MaxDistance = 500, Parent = head })
	local l = Ui.label(emoji, { MaxTextSize = 60, Parent = bb })
	TweenService:Create(bb, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 7, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	Debris:AddItem(bb, 2)
end

local reactionListeners: { (number, string) -> () } = {}
function UIController.onReaction(fn: (number, string) -> ())
	table.insert(reactionListeners, fn)
end

local function buildReactions()
	reactionBar = Ui.panel({ Name = "Reactions", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(#GameConfig.Reactions * 54 + 16, 62), BackgroundColor3 = T.Paper, Parent = gui })
	Ui.padding(6).Parent = reactionBar
	Ui.list(Enum.FillDirection.Horizontal, 6).Parent = reactionBar
	for i, emoji in GameConfig.Reactions do
		Ui.button(emoji, T.Yellow, function()
			ClientState.remote("SendReaction"):FireServer(i)
		end, { Size = UDim2.fromOffset(46, 46), LayoutOrder = i, MaxTextSize = 30, Parent = reactionBar })
	end
	ClientState.remote("ReactionShown").OnClientEvent:Connect(function(userId, index)
		local emoji = GameConfig.Reactions[index]
		if not emoji then
			return
		end
		showReactionOverHead(userId, emoji)
		for _, fn in reactionListeners do
			task.spawn(fn, userId, emoji)
		end
	end)
end

-- Results -------------------------------------------------------------------------------
local function buildResults()
	resultsPanel = Ui.panel({ Name = "Results", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.72), BackgroundColor3 = T.Paper, Visible = false, ZIndex = 10, Parent = gui })
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(980, 640), Parent = resultsPanel })
	Ui.padding(12).Parent = resultsPanel
	Ui.label("🏆 Award Ceremony 🏆", { Size = UDim2.new(1, 0, 0, 44), MaxTextSize = 36, ZIndex = 11, Parent = resultsPanel })
	resultsList = Ui.new("ScrollingFrame", { Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 1, -52),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X, CanvasSize = UDim2.new(), ZIndex = 11, Parent = resultsPanel })
	Ui.list(Enum.FillDirection.Horizontal, 12).Parent = resultsList
end

function UIController.showResults(results: { any })
	Ui.clear(resultsList, { "UIListLayout" })
	if #results == 0 then
		Ui.label("Everyone's a winner today! (Not enough votes for awards.)", { Size = UDim2.new(1, 0, 1, 0),
			MaxTextSize = 28, ZIndex = 12, Parent = resultsList })
	end
	for i, r in results do
		local card = Ui.panel({ Size = UDim2.new(0, 260, 1, -12), BackgroundColor3 = ({ T.Yellow, T.Pink, T.Blue, T.Green })[(i - 1) % 4 + 1],
			LayoutOrder = i, ZIndex = 12, Parent = resultsList })
		Ui.padding(8).Parent = card
		Ui.label(r.displayName, { Size = UDim2.new(1, 0, 0, 30), MaxTextSize = 24, ZIndex = 13, Parent = card })
		local winner = r.winners[1]
		if not winner then
			Ui.label("No votes... the award is shy.", { Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 60),
				Font = T.BodyFont, MaxTextSize = 18, ZIndex = 13, Parent = card })
			continue
		end
		local holder = Ui.new("Frame", { Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(1, 0, 0.6, 0),
			BackgroundTransparency = 1, ZIndex = 13, Parent = card })
		if winner.kind == "Draw" then
			local canvas = DrawingRenderer.makeCanvas({ ZIndex = 13 })
			canvas.Parent = holder
			DrawingRenderer.render(canvas, winner.content)
		else
			local bubble = Ui.panel({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 13,
				Parent = holder })
			Ui.padding(8).Parent = bubble
			Ui.label("“" .. tostring(winner.content) .. "”", { MaxTextSize = 30, ZIndex = 14, Parent = bubble })
		end
		local names = {}
		for _, w in r.winners do
			table.insert(names, w.authorName)
		end
		Ui.label(table.concat(names, " & ") .. string.format("  (%d vote%s)", r.votes, if r.votes == 1 then "" else "s"), {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 40),
			MaxTextSize = 22, ZIndex = 13, Parent = card })
	end
	Ui.pop(resultsPanel)
end

-- Main ----------------------------------------------------------------------------------
local function onStateChanged()
	local phase = ClientState.phase()
	updateHud()
	updateLobby()
	UIController.refreshWaiting()
	resultsPanel.Visible = phase == Phases.Results
	-- Reactions are available whenever players aren't busy at their desks.
	reactionBar.Visible = not (Phases.Seated[phase] and ClientState.isParticipant())
end

function UIController.start()
	gui = Ui.screenGui("DoodleHud", 5)
	buildHud()
	buildPacks()
	buildLobby()
	buildToasts()
	buildWaiting()
	buildReactions()
	buildResults()

	ClientState.Changed:Connect(onStateChanged)
	ClientState.ProfileChanged:Connect(updatePacks)
	ClientState.remote("Notify").OnClientEvent:Connect(function(text, kind)
		if type(text) == "string" then
			UIController.toast(text, kind)
		end
	end)
	ClientState.remote("VotingClosed").OnClientEvent:Connect(function(results)
		UIController.showResults(results)
	end)

	RunService.Heartbeat:Connect(function()
		local s = ClientState.snapshot
		if not s then
			return
		end
		local left = ClientState.timeLeft()
		hud.timer.Text = if s.endsAt and s.endsAt > 0 then tostring(math.ceil(left)) else "--"
		hud.timer.TextColor3 = if s.endsAt > 0 and left <= 10 then T.Red else T.Ink
		if s.phase == Phases.Countdown then
			lobby.status.Text = string.format("Class starts in %d!", math.ceil(left))
		end
	end)
	updatePacks()
end

return UIController
