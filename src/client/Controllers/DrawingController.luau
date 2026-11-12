--!strict
-- DrawingController: the 2D sketching interface.
-- Mouse and touch input are converted to normalized integer coordinates (0..1000) and
-- rendered locally with DrawingRenderer. The finished drawing is sent once on submit or
-- automatically when the timer hits zero; the server re-validates everything.
--
-- Chaos Events hook (future): add functions to DrawingController.inputTransforms. Each
-- receives (x, y) in 0..1 and returns a transformed (x, y), e.g. mirroring or shaking.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DrawingTypes = require(Shared.DrawingTypes)
local DrawingRenderer = require(Shared.DrawingRenderer)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local T = Ui.Theme
local DrawingController = {}

DrawingController.inputTransforms = {} :: { (number, number) -> (number, number) }

local MIN_STEP = 5 -- minimum distance between stored points (in 0..1000 units)

local gui: ScreenGui
local canvas: Frame
local promptLabel: TextLabel
local timerLabel: TextLabel
local pointsLabel: TextLabel
local swatches: { [number]: TextButton } = {}
local sizeButtons: { [number]: TextButton } = {}
local eraserButton: TextButton

local currentTask: any = nil
local strokes: { any } = {} -- { data = Stroke, folder = Folder }
local active: any = nil -- stroke being drawn
local activeInput: InputObject? = nil
local colorIndex = 2
local sizeIndex = 2
local erasing = false
local submitted = false
local totalPoints = 0

local function refreshTools()
	for i, b in swatches do
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if (not erasing and i == colorIndex) then 6 else 2
		end
	end
	for i, b in sizeButtons do
		b.BackgroundColor3 = if i == sizeIndex then T.Yellow else T.Paper
	end
	eraserButton.BackgroundColor3 = if erasing then T.Yellow else T.Paper
	pointsLabel.Text = string.format("Ink: %d%%", math.floor(100 * (1 - totalPoints / DrawingTypes.Limits.MaxTotalPoints)))
end

-- Converts a screen position into normalized canvas coordinates, or nil if outside.
local function toCanvas(pos: Vector2): (number?, number?)
	local origin = canvas.AbsolutePosition
	local size = canvas.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil, nil
	end
	local x = (pos.X - origin.X) / size.X
	local y = (pos.Y - origin.Y) / size.Y
	for _, transform in DrawingController.inputTransforms do
		x, y = transform(x, y)
	end
	return x, y
end

local function inputPosition(input: InputObject): Vector2
	-- Both the canvas (IgnoreGuiInset = false) and InputObject.Position exclude the top bar inset.
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function isInside(x: number?, y: number?): boolean
	return x ~= nil and y ~= nil and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function beginStroke(x: number, y: number)
	if totalPoints >= DrawingTypes.Limits.MaxTotalPoints or #strokes >= DrawingTypes.Limits.MaxStrokes then
		return
	end
	local qx, qy = DrawingTypes.quantize(x), DrawingTypes.quantize(y)
	local data = {
		c = if erasing then DrawingTypes.PAPER_INDEX else colorIndex,
		w = if erasing then math.min(sizeIndex + 1, #DrawingTypes.BrushSizes) else sizeIndex,
		p = { qx, qy },
	}
	local folder = Instance.new("Folder")
	folder.Name = "Stroke"
	folder.Parent = canvas:FindFirstChild("Live") or canvas
	-- dot so single taps leave a mark
	DrawingRenderer.segment(folder, qx, qy, qx, qy, DrawingRenderer.color(data.c), DrawingRenderer.thickness(data.w), 3)
	active = { data = data, folder = folder }
	totalPoints += 1
end

local function extendStroke(x: number, y: number)
	if not active then
		return
	end
	local p = active.data.p
	local qx, qy = DrawingTypes.quantize(math.clamp(x, 0, 1)), DrawingTypes.quantize(math.clamp(y, 0, 1))
	local lx, ly = p[#p - 1], p[#p]
	if math.abs(qx - lx) + math.abs(qy - ly) < MIN_STEP then
		return
	end
	if totalPoints >= DrawingTypes.Limits.MaxTotalPoints then
		return
	end
	if #p // 2 >= DrawingTypes.Limits.MaxPointsPerStroke then
		-- continue seamlessly in a new stroke
		table.insert(strokes, active)
		local data = active.data
		active = nil
		beginStroke(lx / DrawingTypes.SCALE, ly / DrawingTypes.SCALE)
		if not active then
			return
		end
		active.data.c, active.data.w = data.c, data.w
		p = active.data.p
	end
	table.insert(p, qx)
	table.insert(p, qy)
	totalPoints += 1
	DrawingRenderer.segment(active.folder, lx, ly, qx, qy, DrawingRenderer.color(active.data.c),
		DrawingRenderer.thickness(active.data.w), 3)
end

local function endStroke()
	if active then
		table.insert(strokes, active)
		active = nil
		refreshTools()
	end
	activeInput = nil
end

local function undo()
	endStroke()
	local last = table.remove(strokes)
	if last then
		totalPoints -= #last.data.p // 2
		last.folder:Destroy()
	end
	refreshTools()
end

local function clearAll()
	endStroke()
	for _, s in strokes do
		s.folder:Destroy()
	end
	strokes = {}
	totalPoints = 0
	refreshTools()
end

local function buildDrawing()
	local list = {}
	for _, s in strokes do
		table.insert(list, s.data)
	end
	return { v = DrawingTypes.VERSION, strokes = list }
end

local function submit()
	if submitted or not currentTask then
		return
	end
	endStroke()
	submitted = true
	ClientState.remote("SubmitDrawing"):FireServer(currentTask.step, buildDrawing())
end

local function build()
	gui = Ui.screenGui("DrawingGui", 10)
	gui.Enabled = false
	local root = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 240, 200),
		BackgroundTransparency = 0.15, Parent = gui })

	local header = Ui.panel({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0.9, 0, 0, 70), BackgroundColor3 = T.Yellow, Parent = root })
	promptLabel = Ui.label("Draw!", { Size = UDim2.new(0.8, 0, 1, 0), Position = UDim2.fromScale(0.02, 0),
		MaxTextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
	timerLabel = Ui.label("60", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.98, 0),
		Size = UDim2.new(0.16, 0, 1, 0), MaxTextSize = 40, Parent = header })

	-- Canvas area (left/center) and toolbar (right on wide screens, bottom on narrow).
	local area = Ui.new("Frame", { Name = "CanvasArea", Position = UDim2.new(0.03, 0, 0, 88),
		Size = UDim2.new(0.74, 0, 1, -100), BackgroundTransparency = 1, Parent = root })
	canvas = DrawingRenderer.makeCanvas({ Parent = area })
	Ui.stroke(4).Parent = canvas
	local live = Instance.new("Folder")
	live.Name = "Live"
	live.Parent = canvas

	local toolbar = Ui.panel({ Name = "Toolbar", Position = UDim2.new(0.79, 0, 0, 88), Size = UDim2.new(0.19, 0, 1, -100),
		Parent = root })
	Ui.padding(8).Parent = toolbar
	local grid = Ui.new("Frame", { Size = UDim2.new(1, 0, 0.42, 0), BackgroundTransparency = 1, Parent = toolbar })
	Ui.new("UIGridLayout", { CellSize = UDim2.new(0.3, 0, 0.2, 0), CellPadding = UDim2.new(0.04, 0, 0.04, 0),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	for i = 2, #DrawingTypes.Palette do
		local b = Ui.new("TextButton", { Text = "", BackgroundColor3 = DrawingRenderer.color(i), LayoutOrder = i,
			AutoButtonColor = true, Parent = grid }, { Ui.corner(10), Ui.stroke(2) })
		b.Activated:Connect(function()
			colorIndex = i
			erasing = false
			refreshTools()
		end)
		swatches[i] = b
	end
	-- the paper colour is also a usable "white" paint
	local white = Ui.new("TextButton", { Text = "", BackgroundColor3 = DrawingRenderer.color(1), LayoutOrder = 99,
		Parent = grid }, { Ui.corner(10), Ui.stroke(2) })
	white.Activated:Connect(function()
		colorIndex = 1
		erasing = false
		refreshTools()
	end)
	swatches[1] = white

	local sizes = Ui.new("Frame", { Position = UDim2.fromScale(0, 0.44), Size = UDim2.new(1, 0, 0.1, 0),
		BackgroundTransparency = 1, Parent = toolbar })
	Ui.list(Enum.FillDirection.Horizontal, 4).Parent = sizes
	for i = 1, #DrawingTypes.BrushSizes do
		local b = Ui.new("TextButton", { Text = "", Size = UDim2.new(0.18, 0, 1, 0), BackgroundColor3 = T.Paper,
			LayoutOrder = i, Parent = sizes }, { Ui.corner(8), Ui.stroke(2) })
		local dot = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.2 + i * 0.13, 0.2 + i * 0.13), BackgroundColor3 = T.Ink, Parent = b },
			{ Ui.corner(100), Ui.new("UIAspectRatioConstraint", { AspectRatio = 1 }) })
		dot.Active = false
		b.Activated:Connect(function()
			sizeIndex = i
			refreshTools()
		end)
		sizeButtons[i] = b
	end

	local tools = Ui.new("Frame", { Position = UDim2.fromScale(0, 0.56), Size = UDim2.new(1, 0, 0.44, 0),
		BackgroundTransparency = 1, Parent = toolbar })
	Ui.list(Enum.FillDirection.Vertical, 6).Parent = tools
	local h = UDim2.new(1, 0, 0.18, 0)
	eraserButton = Ui.button("🧽 Eraser", T.Paper, function()
		erasing = not erasing
		refreshTools()
	end, { Size = h, LayoutOrder = 1, Parent = tools })
	Ui.button("↩️ Undo", T.Blue, undo, { Size = h, LayoutOrder = 2, Parent = tools })
	Ui.button("🗑 Clear", T.Red, clearAll, { Size = h, LayoutOrder = 3, Parent = tools })
	Ui.button("✅ Done!", T.Green, submit, { Size = UDim2.new(1, 0, 0.24, 0), LayoutOrder = 4, Parent = tools })
	pointsLabel = Ui.label("Ink: 100%", { Size = UDim2.new(1, 0, 0.1, 0), LayoutOrder = 5, Font = T.BodyFont,
		MaxTextSize = 14, Parent = tools })

	-- Narrow screens: canvas on top, toolbar below.
	local function layout()
		local vs = workspace.CurrentCamera.ViewportSize
		if vs.X / math.max(vs.Y, 1) < 1.15 then
			area.Position = UDim2.new(0.03, 0, 0, 88)
			area.Size = UDim2.new(0.94, 0, 0.55, -88)
			toolbar.Position = UDim2.new(0.03, 0, 0.57, 0)
			toolbar.Size = UDim2.new(0.94, 0, 0.42, -8)
		else
			area.Position = UDim2.new(0.03, 0, 0, 88)
			area.Size = UDim2.new(0.74, 0, 1, -100)
			toolbar.Position = UDim2.new(0.79, 0, 0, 88)
			toolbar.Size = UDim2.new(0.19, 0, 1, -100)
		end
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	layout()
	refreshTools()
end

local function isPointerInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function connectInput()
	UserInputService.InputBegan:Connect(function(input)
		if not gui.Enabled or submitted or activeInput or not isPointerInput(input) then
			return
		end
		local x, y = toCanvas(inputPosition(input))
		if isInside(x, y) then
			activeInput = input
			beginStroke(x :: number, y :: number)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not active or submitted then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and activeInput
			and activeInput.UserInputType == Enum.UserInputType.MouseButton1 then
			local x, y = toCanvas(inputPosition(input))
			if x and y then
				extendStroke(x, y)
			end
		elseif input.UserInputType == Enum.UserInputType.Touch and input == activeInput then
			local x, y = toCanvas(inputPosition(input))
			if x and y then
				extendStroke(x, y)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if activeInput and (input == activeInput or (input.UserInputType == Enum.UserInputType.MouseButton1
			and activeInput.UserInputType == Enum.UserInputType.MouseButton1)) then
			endStroke()
		end
	end)
end

function DrawingController.open(task: any)
	local isNewTask = not currentTask or currentTask.step ~= task.step
	currentTask = task
	if isNewTask then
		submitted = false
		clearAll()
		erasing = false
	end
	if task.inputType == "Prompt" then
		promptLabel.Text = "✏️ Draw: " .. tostring(task.text)
	else
		promptLabel.Text = "✏️ Draw this guess: “" .. tostring(task.text) .. "”"
	end
	gui.Enabled = true
	Ui.pop(canvas.Parent :: GuiObject)
end

function DrawingController.close()
	endStroke()
	gui.Enabled = false
end

function DrawingController.isOpen(): boolean
	return gui.Enabled
end

function DrawingController.start()
	build()
	connectInput()
	RunService.Heartbeat:Connect(function()
		if not gui.Enabled or not currentTask then
			return
		end
		local left = math.max(0, (currentTask.endsAt or 0) - workspace:GetServerTimeNow())
		timerLabel.Text = tostring(math.ceil(left))
		timerLabel.TextColor3 = if left <= 10 then T.Red else T.Ink
		if left <= 0.4 and not submitted then
			submit() -- auto-submit on timeout; the server also fills in a blank page if this never arrives
		end
	end)
end

return DrawingController
