--!strict
-- GuessController: shows the received drawing (and nothing else from the sketchbook) and
-- collects a short guess. Auto-submits whatever is typed when the timer runs out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local DrawingRenderer = require(Shared.DrawingRenderer)
local DrawingTypes = require(Shared.DrawingTypes)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local T = Ui.Theme
local GuessController = {}

local gui: ScreenGui
local canvas: Frame
local blankNote: TextLabel
local box: TextBox
local timerLabel: TextLabel
local counter: TextLabel
local currentTask: any = nil
local submitted = false

local function submit()
	if submitted or not currentTask then
		return
	end
	local text = box.Text
	if text:match("^%s*$") then
		return -- nothing typed: on timeout the server inserts a placeholder instead
	end
	submitted = true
	ClientState.remote("SubmitGuess"):FireServer(currentTask.step, text)
end

local function build()
	gui = Ui.screenGui("GuessGui", 10)
	gui.Enabled = false
	local root = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(210, 235, 255),
		BackgroundTransparency = 0.15, Parent = gui })
	local header = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.9, 0, 0, 64), BackgroundColor3 = T.Blue, Parent = root })
	Ui.label("🤔 What on earth is this?", { Size = UDim2.new(0.8, 0, 1, 0), Position = UDim2.fromScale(0.02, 0),
		TextXAlignment = Enum.TextXAlignment.Left, MaxTextSize = 34, Parent = header })
	timerLabel = Ui.label("30", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.98, 0),
		Size = UDim2.new(0.16, 0, 1, 0), MaxTextSize = 40, Parent = header })

	local area = Ui.new("Frame", { Position = UDim2.new(0.05, 0, 0, 82), Size = UDim2.new(0.9, 0, 1, -200),
		BackgroundTransparency = 1, Parent = root })
	canvas = DrawingRenderer.makeCanvas({ Parent = area })
	Ui.stroke(4).Parent = canvas
	blankNote = Ui.label("(a blank page... interpret the void)", { Size = UDim2.fromScale(1, 0.2),
		Position = UDim2.fromScale(0, 0.4), TextColor3 = Color3.fromRGB(150, 150, 160), MaxTextSize = 28, Visible = false,
		ZIndex = 5, Parent = canvas })

	local row = Ui.panel({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0.9, 0, 0, 92), Parent = root })
	Ui.padding(10).Parent = row
	box = Ui.new("TextBox", {
		Size = UDim2.new(0.72, 0, 0.62, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Font = T.Font,
		PlaceholderText = "Type your guess...",
		Text = "",
		TextScaled = true,
		ClearTextOnFocus = false,
		TextColor3 = T.Ink,
		Parent = row,
	}, { Ui.corner(10), Ui.stroke(3), Ui.new("UITextSizeConstraint", { MaxTextSize = 30 }), Ui.padding(6) })
	counter = Ui.label("0/" .. GameConfig.Guess.MaxLength, { Position = UDim2.fromScale(0, 0.66), Size = UDim2.new(0.72, 0, 0.34, 0),
		Font = T.BodyFont, MaxTextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
	Ui.button("📨 Submit", T.Green, submit, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.25, 0, 1, 0), Parent = row })

	box:GetPropertyChangedSignal("Text"):Connect(function()
		local len = utf8.len(box.Text) or #box.Text
		if len > GameConfig.Guess.MaxLength then
			box.Text = string.sub(box.Text, 1, utf8.offset(box.Text, GameConfig.Guess.MaxLength + 1) - 1)
			return
		end
		counter.Text = string.format("%d/%d", len, GameConfig.Guess.MaxLength)
	end)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)
end

function GuessController.open(t: any)
	local isNew = not currentTask or currentTask.step ~= t.step or currentTask.matchId ~= t.matchId
	currentTask = t
	if isNew then
		submitted = false
		box.Text = ""
		DrawingRenderer.render(canvas, t.drawing)
		blankNote.Visible = type(t.drawing) ~= "table" or DrawingTypes.isBlank(t.drawing)
	end
	gui.Enabled = true
	Ui.pop(canvas.Parent :: GuiObject)
	task.defer(function()
		box:CaptureFocus()
	end)
end

function GuessController.close()
	gui.Enabled = false
	box:ReleaseFocus()
end

function GuessController.start()
	build()
	RunService.Heartbeat:Connect(function()
		if not gui.Enabled or not currentTask then
			return
		end
		local left = math.max(0, (currentTask.endsAt or 0) - workspace:GetServerTimeNow())
		timerLabel.Text = tostring(math.ceil(left))
		timerLabel.TextColor3 = if left <= 8 then T.Red else T.Ink
		if left <= 0.4 and not submitted then
			submit()
		end
	end)
end

return GuessController
