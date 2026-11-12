--!strict
-- DrawingRenderer: draws stroke data into any GuiObject (ScreenGui frames, the projector
-- SurfaceGui, voting thumbnails) using rotated, rounded Frames. Resolution independent:
-- everything is positioned in scale units, so the same drawing looks right at any size
-- as long as the container keeps the canvas aspect ratio (DrawingTypes.ASPECT).
--
-- Client-only in practice (it creates GUI objects), but it has no client-only API calls.

local DrawingTypes = require(script.Parent.DrawingTypes)

local DrawingRenderer = {}

local SCALE = DrawingTypes.SCALE
local ASPECT = DrawingTypes.ASPECT

local colorCache: { Color3 } = {}
for i, rgb in DrawingTypes.Palette do
	colorCache[i] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function DrawingRenderer.color(index: number): Color3
	return colorCache[index] or colorCache[2]
end

function DrawingRenderer.thickness(sizeIndex: number): number
	return DrawingTypes.BrushSizes[sizeIndex] or DrawingTypes.BrushSizes[2]
end

-- Adds one capsule-shaped segment between two stored points (0..SCALE integers).
function DrawingRenderer.segment(parent: Instance, x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number, zIndex: number?): Frame
	local nx1, ny1, nx2, ny2 = x1 / SCALE, y1 / SCALE, x2 / SCALE, y2 / SCALE
	local dx = nx2 - nx1
	local dyW = (ny2 - ny1) / ASPECT -- vertical distance in canvas-width units
	local len = math.sqrt(dx * dx + dyW * dyW)
	local f = Instance.new("Frame")
	f.Name = "Seg"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale((nx1 + nx2) / 2, (ny1 + ny2) / 2)
	f.Size = UDim2.fromScale(len + thickness, thickness * ASPECT)
	f.Rotation = if len > 0 then math.deg(math.atan2(dyW, dx)) else 0
	f.ZIndex = zIndex or 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	f.Parent = parent
	return f
end

-- Renders a whole stroke into `parent` (usually a Folder per stroke so undo is cheap).
function DrawingRenderer.stroke(parent: Instance, stroke: { c: number, w: number, p: { number } }, zIndex: number?)
	local color = DrawingRenderer.color(stroke.c)
	local t = DrawingRenderer.thickness(stroke.w)
	local p = stroke.p
	local count = #p // 2
	if count == 1 then
		DrawingRenderer.segment(parent, p[1], p[2], p[1], p[2], color, t, zIndex)
		return
	end
	for i = 1, count - 1 do
		local j = (i - 1) * 2
		DrawingRenderer.segment(parent, p[j + 1], p[j + 2], p[j + 3], p[j + 4], color, t, zIndex)
	end
end

-- Clears `canvas` of previous ink and renders the drawing. The canvas should be a Frame
-- with a UIAspectRatioConstraint of DrawingTypes.ASPECT (see DrawingRenderer.makeCanvas).
function DrawingRenderer.render(canvas: GuiObject, drawing: any)
	local ink = canvas:FindFirstChild("Ink")
	if ink then
		ink:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Ink"
	if type(drawing) == "table" and type(drawing.strokes) == "table" then
		for _, s in drawing.strokes do
			DrawingRenderer.stroke(folder, s, canvas.ZIndex + 1)
		end
	end
	folder.Parent = canvas
end

-- Creates a white paper canvas with the correct aspect ratio and clipping.
function DrawingRenderer.makeCanvas(props: { [string]: any }?): Frame
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundColor3 = Color3.new(1, 1, 1)
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1, 1)
	for k, v in props or {} do
		(canvas :: any)[k] = v
	end
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = ASPECT
	aspect.Parent = canvas
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = canvas
	return canvas
end

return DrawingRenderer
