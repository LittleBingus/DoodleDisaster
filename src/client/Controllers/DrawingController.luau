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

-- Layout ----------------------------------------------------------------------------------
-- Three arrangements, chosen from the space actually available, all in pixels so every
-- button keeps a touch-friendly size (TOUCH px or more):
--   side       wide and tall enough: tools in one column on the right
--   wideShort  landscape phone: actions on the left, colours on the right, canvas between
--   stacked    portrait / narrow: canvas on top, colours then actions underneath
local TOUCH = 44
local GAP = 6
local PAD = 8

function DrawingController.pickLayout(width: number, height: number): string
	local headerH = if height < 300 then 40 elseif height < 480 then 48 else 70
	local availH = height - headerH - PAD * 3
	if width / math.max(height, 1) < 1.15 then
		return "stacked"
	elseif availH < 430 then
		return "wideShort"
	end
	return "side"
end

local function build()
	gui = Ui.screenGui("DrawingGui", 10)
	gui.Enabled = false
	local root = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 240, 200),
		BackgroundTransparency = 0.15, Parent = gui })

	local header = Ui.panel({ Name = "Header", Position = UDim2.fromOffset(PAD, PAD), Size = UDim2.new(1, -PAD * 2, 0, 70),
		BackgroundColor3 = T.Yellow, Parent = root })
	promptLabel = Ui.label("Draw!", { Size = UDim2.new(0.8, 0, 1, 0), Position = UDim2.fromScale(0.02, 0),
		MaxTextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, Parent = header })
	timerLabel = Ui.label("60", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.98, 0),
		Size = UDim2.new(0.16, 0, 1, 0), MaxTextSize = 40, Parent = header })

	local area = Ui.new("Frame", { Name = "CanvasArea", BackgroundTransparency = 1, Parent = root })
	canvas = DrawingRenderer.makeCanvas({ Parent = area })
	Ui.stroke(4).Parent = canvas
	local live = Instance.new("Folder")
	live.Name = "Live"
	live.Parent = canvas

	-- Colours + brush sizes
	local colorsBox = Ui.panel({ Name = "Colours", Parent = root })
	Ui.padding(GAP).Parent = colorsBox
	local grid = Ui.new("Frame", { Name = "Swatches", BackgroundTransparency = 1, Parent = colorsBox })
	local gridLayout = Ui.new("UIGridLayout", { CellPadding = UDim2.fromOffset(GAP, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	local function swatch(index: number, order: number)
		local b = Ui.new("TextButton", { Text = "", BackgroundColor3 = DrawingRenderer.color(index), LayoutOrder = order,
			AutoButtonColor = true, Parent = grid }, { Ui.corner(10), Ui.stroke(2) })
		b.Activated:Connect(function()
			colorIndex = index
			erasing = false
			refreshTools()
		end)
		swatches[index] = b
	end
	for i = 2, #DrawingTypes.Palette do
		swatch(i, i)
	end
	swatch(1, 99) -- the paper colour is also a usable "white" paint

	local sizes = Ui.new("Frame", { Name = "Sizes", BackgroundTransparency = 1, Parent = colorsBox })
	Ui.list(Enum.FillDirection.Horizontal, GAP).Parent = sizes
	local sizeCount = #DrawingTypes.BrushSizes
	for i = 1, sizeCount do
		local b = Ui.new("TextButton", { Text = "", Size = UDim2.new(1 / sizeCount, -GAP, 1, 0), BackgroundColor3 = T.Paper,
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
	pointsLabel = Ui.label("Ink: 100%", { Font = T.BodyFont, MaxTextSize = 13, Parent = colorsBox })

	-- Actions
	local actionsBox = Ui.new("Frame", { Name = "Actions", BackgroundTransparency = 1, Parent = root })
	local actionsLayout = Ui.list(Enum.FillDirection.Vertical, GAP)
	actionsLayout.Parent = actionsBox
	eraserButton = Ui.button("🧽 Eraser", T.Paper, function()
		erasing = not erasing
		refreshTools()
	end, { LayoutOrder = 1, Parent = actionsBox })
	local undoButton = Ui.button("↩️ Undo", T.Blue, undo, { LayoutOrder = 2, Parent = actionsBox })
	local clearButton = Ui.button("🗑 Clear", T.Red, clearAll, { LayoutOrder = 3, Parent = actionsBox })
	local doneButton = Ui.button("✅ Done!", T.Green, submit, { LayoutOrder = 4, Parent = actionsBox })
	local actionButtons = { { eraserButton, 1 }, { undoButton, 1 }, { clearButton, 1 }, { doneButton, 1.2 } }
	local totalWeight = 4.2

	local function place(obj: GuiObject, x: number, y: number, w: number, h: number)
		obj.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		obj.Size = UDim2.fromOffset(math.floor(math.max(w, 0)), math.floor(math.max(h, 0)))
	end

	-- Sizes the colour box contents for `cols` swatch columns; returns the height it needs.
	local function arrangeColours(width: number, cols: number): number
		local count = #DrawingTypes.Palette
		local rows = math.ceil(count / cols)
		local inner = width - GAP * 2
		gridLayout.CellSize = UDim2.fromOffset(math.floor((inner - GAP * (cols - 1)) / cols), TOUCH)
		local gridH = rows * TOUCH + (rows - 1) * GAP
		place(grid, 0, 0, inner, gridH)
		place(sizes, 0, gridH + GAP, inner, TOUCH)
		place(pointsLabel, 0, gridH + GAP + TOUCH + 2, inner, 16)
		return gridH + GAP + TOUCH + 2 + 16 + GAP * 2
	end

	local function arrangeActions(horizontal: boolean)
		actionsLayout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		for _, entry in actionButtons do
			local share = entry[2] / totalWeight
			entry[1].Size = if horizontal then UDim2.new(share, -GAP, 1, 0) else UDim2.new(1, 0, share, -GAP)
		end
	end

	local function layout()
		local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
		if W <= 0 or H <= 0 then
			return
		end
		local mode = DrawingController.pickLayout(W, H)
		local headerH = if H < 300 then 40 elseif H < 480 then 48 else 70
		header.Size = UDim2.new(1, -PAD * 2, 0, headerH)
		local top = headerH + PAD * 2
		local availH = H - top - PAD
		root:SetAttribute("Layout", mode)
		if mode == "side" then
			local colW = math.clamp(W * 0.2, 256, 290)
			local colX = W - colW - PAD
			local coloursH = arrangeColours(colW, 4)
			place(colorsBox, colX, top, colW, coloursH)
			place(actionsBox, colX, top + coloursH + PAD, colW, availH - coloursH - PAD)
			arrangeActions(false)
			place(area, PAD, top, W - colW - PAD * 3, availH)
		elseif mode == "wideShort" then
			local leftW, rightW = 120, 280
			place(actionsBox, PAD, top, leftW, availH)
			arrangeActions(false)
			local coloursH = arrangeColours(rightW, 4)
			place(colorsBox, W - rightW - PAD, top, rightW, math.min(coloursH, availH))
			place(area, leftW + PAD * 2, top, W - leftW - rightW - PAD * 4, availH)
		else
			local fullW = W - PAD * 2
			local actionsH = 56
			local coloursH = arrangeColours(fullW, 6)
			place(actionsBox, PAD, H - PAD - actionsH, fullW, actionsH)
			arrangeActions(true)
			place(colorsBox, PAD, H - PAD - actionsH - PAD - coloursH, fullW, coloursH)
			place(area, PAD, top, fullW, availH - actionsH - coloursH - PAD * 2)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
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
	local isNewTask = not currentTask or currentTask.step ~= task.step or currentTask.matchId ~= task.matchId
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
