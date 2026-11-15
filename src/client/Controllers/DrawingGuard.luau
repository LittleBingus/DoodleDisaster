--!strict
-- DrawingGuard: shows another player's drawing with Hide and Report controls.
--
-- Hide is local: the drawing is replaced by a placeholder everywhere this player would see
-- it again (reveal, projector, voting, results). Report asks the server to record it; the
-- server then also stops sending that artist's drawings to this player. Drawings the server
-- withheld arrive with no strokes and `serverHidden = true`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DrawingRenderer = require(Shared.DrawingRenderer)
local DrawingTypes = require(Shared.DrawingTypes)
local ClientState = require(script.Parent.ClientState)
local Ui = require(script.Parent.Ui)

local T = Ui.Theme
local DrawingGuard = {}

-- Drawing ids are random per match, so one session-long set is enough.
local hidden: { [string]: boolean } = {}
local reported: { [string]: boolean } = {}
local changed = Instance.new("BindableEvent")

export type Options = {
	drawId: string?,
	serverHidden: boolean?,
	controls: boolean?, -- show the Hide / Report buttons (off for the projector and own drawings)
	compact: boolean?, -- small buttons for thumbnails
	blankText: string?, -- note shown over an empty page
	stroke: number?,
	zIndex: number?,
}

function DrawingGuard.isHidden(drawId: string?): boolean
	return drawId ~= nil and (hidden[drawId] == true or reported[drawId] == true)
end

-- Creates a canvas in `holder` showing `drawing` (or a placeholder) and returns it.
function DrawingGuard.mount(holder: Instance, drawing: any, opts: Options?): Frame
	local o: Options = opts or {}
	local drawId = o.drawId
	local z = o.zIndex or 1
	local canvas = DrawingRenderer.makeCanvas({ ZIndex = z, Parent = holder })
	if o.stroke then
		Ui.stroke(o.stroke).Parent = canvas
	end
	local blank = type(drawing) ~= "table" or DrawingTypes.isBlank(drawing)
	local canControl = o.controls == true and drawId ~= nil and not blank and not o.serverHidden
	local size = if o.compact then 34 else 44

	local note = Ui.label("", { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.35),
		TextColor3 = Color3.fromRGB(120, 120, 135), MaxTextSize = if o.compact then 18 else 36, ZIndex = z + 4, Parent = canvas })
	local hideButton: TextButton? = nil
	local reportButton: TextButton? = nil
	local confirming = false

	local function refresh()
		local isHidden = o.serverHidden == true or DrawingGuard.isHidden(drawId)
		if isHidden then
			DrawingRenderer.render(canvas, nil)
			canvas.BackgroundColor3 = Color3.fromRGB(232, 232, 238)
			note.Text = if o.serverHidden or (drawId and reported[drawId]) then "🚩 Reported drawing (hidden)" else "🙈 Hidden drawing"
		else
			canvas.BackgroundColor3 = Color3.new(1, 1, 1)
			DrawingRenderer.render(canvas, drawing)
			note.Text = if blank then (o.blankText or "") else ""
		end
		note.Visible = note.Text ~= ""
		local wasReported = drawId ~= nil and reported[drawId] == true
		if hideButton then
			hideButton.Visible = not wasReported
			hideButton.Text = if isHidden then "👁" else "🙈"
		end
		if reportButton then
			reportButton.Visible = not wasReported
		end
	end

	if canControl and drawId then
		local id = drawId :: string
		hideButton = Ui.button("🙈", T.Paper, function()
			hidden[id] = if hidden[id] then nil else true
			changed:Fire(id)
		end, { Name = "HideDrawing", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(size, size), ZIndex = z + 6, MaxTextSize = 24, Parent = canvas })
		local report: TextButton
		report = Ui.button("🚩", T.Paper, function()
			if not confirming then
				-- Two taps to report, so a stray tap can't send one.
				confirming = true
				report.Text = "Report?"
				report.BackgroundColor3 = T.Red
				report.Size = UDim2.fromOffset(size * 2.2, size)
				task.delay(3, function()
					if confirming and report.Parent then
						confirming = false
						report.Text = "🚩"
						report.BackgroundColor3 = T.Paper
						report.Size = UDim2.fromOffset(size, size)
					end
				end)
				return
			end
			confirming = false
			reported[id] = true
			ClientState.remote("ReportDrawing"):FireServer(id)
			changed:Fire(id)
		end, { Name = "ReportDrawing", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8 - size, 0, 4),
			Size = UDim2.fromOffset(size, size), ZIndex = z + 6, MaxTextSize = 20, Parent = canvas })
		reportButton = report
	end

	if drawId then
		local connection = changed.Event:Connect(function(id)
			if id == drawId and canvas.Parent then
				refresh()
			end
		end)
		canvas.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
	refresh()
	return canvas
end

return DrawingGuard
