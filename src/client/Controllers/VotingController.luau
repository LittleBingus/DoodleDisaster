--!strict
-- VotingController: anonymous award ballot. Candidates are shown with generic labels only;
-- the player's own entries are marked "Yours" and can't be picked (the server enforces it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DrawingRenderer = require(Shared.DrawingRenderer)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local T = Ui.Theme
local VotingController = {}

local gui: ScreenGui
local tabs: Frame
local grid: ScrollingFrame
local timerLabel: TextLabel
local infoLabel: TextLabel
local ballot: any = nil
local mine: { [string]: boolean } = {}
local myVotes: { [string]: string } = {}
local currentCategory: string? = nil
local cards: { [string]: TextButton } = {}

local TAB_COLORS = { T.Yellow, T.Pink, T.Blue, T.Green }

local function refreshCards()
	for cid, card in cards do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		local chosen = currentCategory ~= nil and myVotes[currentCategory :: string] == cid
		if stroke then
			stroke.Thickness = if chosen then 7 else 3
			stroke.Color = if chosen then T.Green else T.Ink
		end
	end
end

local function showCategory(categoryId: string)
	currentCategory = categoryId
	Ui.clear(grid, { "UIGridLayout" })
	cards = {}
	local category
	for _, c in ballot.categories do
		if c.id == categoryId then
			category = c
		end
	end
	if not category then
		return
	end
	for i, tab in tabs:GetChildren() do
		if tab:IsA("TextButton") then
			tab.TextTransparency = if tab.Name == categoryId then 0 else 0.35
		end
	end
	infoLabel.Text = if myVotes[categoryId] then "✅ Voted! You can check the other awards."
		elseif ballot.canVote then "Tap your favourite for " .. category.displayName
		else "Spectating the vote"
	for i, cid in category.candidateIds do
		local c = ballot.candidates[cid]
		local isMine = mine[cid] == true
		local card = Ui.new("TextButton", { Name = cid, Text = "", BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = i,
			AutoButtonColor = not isMine, Parent = grid }, { Ui.corner(12), Ui.stroke(3) })
		cards[cid] = card
		local holder = Ui.new("Frame", { Position = UDim2.fromScale(0.04, 0.04), Size = UDim2.fromScale(0.92, 0.72),
			BackgroundTransparency = 1, Parent = card })
		if c.kind == "Draw" then
			local canvas = DrawingRenderer.makeCanvas({ Parent = holder })
			DrawingRenderer.render(canvas, c.content)
		else
			Ui.label("“" .. tostring(c.content) .. "”", { MaxTextSize = 26, Parent = holder })
		end
		Ui.label(if isMine then c.label .. " (yours)" else c.label, { Position = UDim2.fromScale(0, 0.78),
			Size = UDim2.fromScale(1, 0.2), MaxTextSize = 20, TextColor3 = if isMine then T.Grey else T.Ink, Parent = card })
		card.Activated:Connect(function()
			if isMine or not ballot.canVote or myVotes[categoryId] then
				return
			end
			ClientState.remote("CastVote"):FireServer(categoryId, cid)
		end)
	end
	refreshCards()
end

local function open(newBallot: any)
	ballot = newBallot
	mine = {}
	for _, cid in newBallot.mine or {} do
		mine[cid] = true
	end
	myVotes = {}
	Ui.clear(tabs, { "UIListLayout" })
	for i, cat in newBallot.categories do
		local b = Ui.button(cat.displayName, TAB_COLORS[(i - 1) % 4 + 1], function()
			showCategory(cat.id)
		end, { Name = cat.id, Size = UDim2.new(1 / #newBallot.categories, -8, 1, 0), LayoutOrder = i, MaxTextSize = 20,
			Parent = tabs })
		b.Name = cat.id
	end
	gui.Enabled = true
	if newBallot.categories[1] then
		showCategory(newBallot.categories[1].id)
	end
end

local function nextUnvoted(): string?
	for _, cat in ballot.categories do
		if not myVotes[cat.id] then
			return cat.id
		end
	end
	return nil
end

function VotingController.start()
	gui = Ui.screenGui("VotingGui", 9)
	gui.Enabled = false
	local panel = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.86, 0.76), BackgroundColor3 = T.Paper, Parent = gui })
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(1100, 760), Parent = panel })
	Ui.padding(12).Parent = panel
	Ui.label("🗳 Anonymous Award Voting", { Size = UDim2.new(0.8, 0, 0, 40), MaxTextSize = 32, Parent = panel })
	timerLabel = Ui.label("30", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.18, 0, 0, 40), MaxTextSize = 32, Parent = panel })
	tabs = Ui.new("Frame", { Position = UDim2.new(0, 0, 0, 46), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1,
		Parent = panel })
	Ui.list(Enum.FillDirection.Horizontal, 8).Parent = tabs
	infoLabel = Ui.label("", { Position = UDim2.new(0, 0, 0, 94), Size = UDim2.new(1, 0, 0, 24), Font = T.BodyFont,
		MaxTextSize = 16, Parent = panel })
	grid = Ui.new("ScrollingFrame", { Position = UDim2.new(0, 0, 0, 122), Size = UDim2.new(1, 0, 1, -122),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), Parent = panel })
	Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(200, 180), CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })

	ClientState.remote("VotingOpened").OnClientEvent:Connect(open)
	ClientState.remote("VoteResult").OnClientEvent:Connect(function(categoryId, candidateId, ok, reason)
		if ok then
			myVotes[categoryId] = candidateId
			refreshCards()
			local nxt = nextUnvoted()
			task.delay(0.6, function()
				if gui.Enabled and nxt and currentCategory == categoryId then
					showCategory(nxt)
				elseif gui.Enabled and currentCategory == categoryId then
					infoLabel.Text = "✅ All votes in! Waiting for the class..."
				end
			end)
		elseif reason then
			infoLabel.Text = "⚠️ " .. tostring(reason)
		end
	end)
	ClientState.Changed:Connect(function(snapshot)
		if snapshot.phase ~= "AwardVoting" then
			gui.Enabled = false
		end
	end)
	RunService.Heartbeat:Connect(function()
		if gui.Enabled then
			timerLabel.Text = tostring(math.ceil(ClientState.timeLeft()))
		end
	end)
end

return VotingController
