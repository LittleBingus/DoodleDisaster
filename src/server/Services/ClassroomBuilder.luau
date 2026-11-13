--!strict
-- ClassroomBuilder: procedurally builds the 2.5D classroom at server start using only
-- Roblox Parts, materials and GUIs (no paid or external assets).
--
-- Layout (top view, camera looks north from the south side):
--
--   z=-35  [ chalkboard ][====== PROJECTOR SCREEN ======][ clock ]   golden pencil
--             desk1  desk2  desk3  desk4        (row A, z = -6)
--                      [ craft table ]
--             desk5  desk6  desk7  desk8        (row B, z = 10)
--   trash can                                             suspicious button
--   z=+35  low front wall (keeps the camera's view clear)

local Workspace = game:GetService("Workspace")

local ClassroomBuilder = {}

ClassroomBuilder.RoomSize = Vector3.new(100, 30, 70)
ClassroomBuilder.FloorY = 0

local folder: Folder

local function part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or folder
	return p
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function label(parent: Instance, face: Enum.NormalId, text: string, opts: { [string]: any }?): TextLabel
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.PixelsPerStud or 30
	gui.LightInfluence = 0
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = o.Font or Enum.Font.FredokaOne
	t.TextColor3 = o.Color or Color3.new(1, 1, 1)
	t.TextWrapped = true
	t.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = t
	return t
end

local STATION_COLORS = {
	rgb(255, 90, 95), rgb(255, 170, 40), rgb(255, 220, 60), rgb(80, 200, 110),
	rgb(60, 170, 255), rgb(150, 100, 255), rgb(255, 120, 200), rgb(60, 210, 200),
}

local function buildShell()
	local size = ClassroomBuilder.RoomSize
	local hx, hz = size.X / 2, size.Z / 2

	-- Floor with a checkerboard of big tiles for a cartoony look.
	part({ Name = "Floor", Size = Vector3.new(size.X, 1, size.Z), Position = Vector3.new(0, -0.5, 0),
		Color = rgb(235, 205, 160), Material = Enum.Material.WoodPlanks })
	local tile = 10
	for ix = 0, size.X / tile - 1 do
		for iz = 0, size.Z / tile - 1 do
			if (ix + iz) % 2 == 0 then
				part({ Name = "Tile", Size = Vector3.new(tile, 0.05, tile),
					Position = Vector3.new(-hx + tile / 2 + ix * tile, 0.02, -hz + tile / 2 + iz * tile),
					Color = rgb(225, 190, 140), Material = Enum.Material.WoodPlanks, CanCollide = false })
			end
		end
	end

	-- Walls: tall back and sides, low front so the fixed camera always sees the room.
	part({ Name = "BackWall", Size = Vector3.new(size.X, size.Y, 1), Position = Vector3.new(0, size.Y / 2, -hz - 0.5),
		Color = rgb(120, 200, 230) })
	part({ Name = "LeftWall", Size = Vector3.new(1, size.Y, size.Z), Position = Vector3.new(-hx - 0.5, size.Y / 2, 0),
		Color = rgb(255, 180, 200) })
	part({ Name = "RightWall", Size = Vector3.new(1, size.Y, size.Z), Position = Vector3.new(hx + 0.5, size.Y / 2, 0),
		Color = rgb(255, 180, 200) })
	part({ Name = "FrontWall", Size = Vector3.new(size.X, 3, 1), Position = Vector3.new(0, 1.5, hz + 0.5),
		Color = rgb(255, 150, 80) })
	-- Baseboard trim
	part({ Name = "Trim", Size = Vector3.new(size.X, 1.2, 0.4), Position = Vector3.new(0, 0.6, -hz + 0.2),
		Color = rgb(255, 255, 255), CanCollide = false })

	-- Invisible barriers keep players inside the camera frame.
	local barrierHeight = 80
	for _, spec in {
		{ Vector3.new(size.X + 4, barrierHeight, 2), Vector3.new(0, barrierHeight / 2, hz + 1) },
		{ Vector3.new(size.X + 4, barrierHeight, 2), Vector3.new(0, barrierHeight / 2, -hz - 1) },
		{ Vector3.new(2, barrierHeight, size.Z + 4), Vector3.new(hx + 1, barrierHeight / 2, 0) },
		{ Vector3.new(2, barrierHeight, size.Z + 4), Vector3.new(-hx - 1, barrierHeight / 2, 0) },
		{ Vector3.new(size.X + 4, 2, size.Z + 4), Vector3.new(0, 38, 0) }, -- ceiling: no jumping out
	} do
		part({ Name = "Barrier", Size = spec[1], Position = spec[2], Transparency = 1, CanCollide = true,
			CastShadow = false })
	end

	-- Windows on the right wall
	for i = 0, 2 do
		local z = -22 + i * 18
		part({ Name = "Window", Size = Vector3.new(0.4, 10, 12), Position = Vector3.new(hx - 0.1, 14, z),
			Color = rgb(190, 240, 255), Material = Enum.Material.Neon, Transparency = 0.25, CanCollide = false })
		part({ Name = "WindowFrame", Size = Vector3.new(0.6, 0.6, 12.6), Position = Vector3.new(hx - 0.2, 14, z),
			Color = rgb(255, 255, 255), CanCollide = false })
	end

	-- Posters
	local posters = {
		{ "THINK OUTSIDE THE CRAYON", rgb(255, 220, 60), Vector3.new(-hx + 0.1, 14, -18) },
		{ "ART IS 90% CONFIDENCE", rgb(150, 100, 255), Vector3.new(-hx + 0.1, 14, 0) },
		{ "NO STICK FIGURES\n(JK. ALL STICK FIGURES)", rgb(80, 200, 110), Vector3.new(-hx + 0.1, 14, 18) },
	}
	for _, info in posters do
		local p = part({ Name = "Poster", Size = Vector3.new(0.2, 9, 12), Position = info[3], Color = info[2],
			CanCollide = false })
		label(p, Enum.NormalId.Right, info[1], { Color = rgb(30, 30, 40) })
	end

	-- Clock
	local clock = part({ ClassName = "Part", Name = "Clock", Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 6, 6), CFrame = CFrame.new(38, 22, -hz + 0.3) * CFrame.Angles(0, math.rad(90), 0),
		Color = rgb(255, 255, 255), CanCollide = false })
	label(clock, Enum.NormalId.Left, "⏰", { Color = rgb(30, 30, 40) })

	-- Paint splats on the floor
	local splatColors = { rgb(255, 90, 95), rgb(60, 170, 255), rgb(255, 220, 60), rgb(150, 100, 255) }
	local splatSpots = { Vector3.new(-30, 0.06, 25), Vector3.new(22, 0.06, 26), Vector3.new(-40, 0.06, -20),
		Vector3.new(36, 0.06, 2), Vector3.new(4, 0.06, 28) }
	for i, pos in splatSpots do
		part({ Name = "PaintSplat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 5 + i, 5 + i),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = splatColors[(i - 1) % 4 + 1],
			CanCollide = false })
	end

	-- Giant crayons leaning on the left wall
	for i, color in { rgb(255, 90, 95), rgb(60, 170, 255), rgb(80, 200, 110), rgb(255, 220, 60) } do
		local base = CFrame.new(-hx + 3, 5, 26 - i * 3.2) * CFrame.Angles(0, 0, math.rad(-12))
		part({ Name = "GiantCrayon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 2.4, 2.4),
			CFrame = base * CFrame.Angles(0, 0, math.rad(90)), Color = color })
		part({ Name = "CrayonTip", Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = base * CFrame.new(0, 5.2, 0), Color = color })
	end

	-- Bookshelf
	part({ Name = "Bookshelf", Size = Vector3.new(4, 12, 14), Position = Vector3.new(hx - 2.5, 6, 24),
		Color = rgb(150, 95, 60), Material = Enum.Material.Wood })
	for shelf = 0, 2 do
		for b = 0, 5 do
			part({ Name = "Book", Size = Vector3.new(2.6, 2.6, 1.4),
				Position = Vector3.new(hx - 4.4, 2.2 + shelf * 3.8, 18.5 + b * 2.1),
				Color = STATION_COLORS[(shelf * 6 + b) % 8 + 1], CanCollide = false })
		end
	end

	-- Teacher's desk and plant (front left)
	part({ Name = "TeacherDesk", Size = Vector3.new(14, 3.5, 5), Position = Vector3.new(-30, 1.75, -26),
		Color = rgb(160, 100, 60), Material = Enum.Material.Wood })
	part({ Name = "Apple", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4),
		Position = Vector3.new(-26, 4.2, -26), Color = rgb(230, 40, 40) })
	part({ Name = "PlantPot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(-45, 1.5, -30) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(200, 100, 60) })
	part({ Name = "Plant", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 5, 5), Position = Vector3.new(-45, 5, -30),
		Color = rgb(70, 180, 80), Material = Enum.Material.Grass })

	-- Central craft table between the desk rows
	part({ Name = "CraftTable", Size = Vector3.new(18, 3, 6), Position = Vector3.new(0, 1.5, 2),
		Color = rgb(255, 255, 255) })
	for i, color in { rgb(255, 90, 95), rgb(60, 170, 255), rgb(255, 220, 60), rgb(80, 200, 110) } do
		part({ Name = "PaintPot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 1.6, 1.6),
			CFrame = CFrame.new(-6 + i * 2.5, 3.6, 2) * CFrame.Angles(0, 0, math.rad(90)), Color = color })
	end

	-- Rug
	part({ Name = "Rug", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 30, 30),
		CFrame = CFrame.new(0, 0.08, 24) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(255, 140, 180),
		Material = Enum.Material.Fabric, CanCollide = false })

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ClassroomSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.2, 6)
	spawn.Position = Vector3.new(0, 0.12, 25)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
end

local function buildStations()
	local stations = {}
	local xs = { -27, -9, 9, 27 }
	local zs = { -6, 10 }
	local index = 0
	for _, z in zs do
		for _, x in xs do
			index += 1
			local color = STATION_COLORS[index]
			local model = Instance.new("Model")
			model.Name = "Station" .. index
			model.Parent = folder
			local desk = part({ Name = "Desk", Size = Vector3.new(7, 3, 4), Position = Vector3.new(x, 1.5, z),
				Color = color, Parent = model })
			part({ Name = "DeskTop", Size = Vector3.new(7.4, 0.4, 4.4), Position = Vector3.new(x, 3.2, z),
				Color = rgb(255, 255, 255), Parent = model })
			-- Sketchbook prop on the desk
			part({ Name = "Sketchbook", Size = Vector3.new(3, 0.3, 2.2), CFrame = CFrame.new(x, 3.55, z + 0.4)
				* CFrame.Angles(0, math.rad(8 * (index % 2 == 0 and 1 or -1)), 0), Color = rgb(250, 250, 240),
				CanCollide = false, Parent = model })
			local seat = Instance.new("Seat")
			seat.Name = "Seat"
			seat.Anchored = true
			seat.Size = Vector3.new(3, 1, 3)
			seat.CFrame = CFrame.new(x, 1.2, z + 4) -- default look vector is -Z: faces the projector
			seat.Color = rgb(70, 70, 90)
			seat.TopSurface = Enum.SurfaceType.Smooth
			seat.Disabled = true -- only the server seats players (StationManager)
			seat.Parent = model
			part({ Name = "SeatBack", Size = Vector3.new(3, 3, 0.5), Position = Vector3.new(x, 2.5, z + 5.6),
				Color = rgb(70, 70, 90), Parent = model })

			local anchor = part({ Name = "LabelAnchor", Size = Vector3.new(1, 1, 1), Position = Vector3.new(x, 8, z),
				Transparency = 1, CanCollide = false, CanQuery = false, Parent = model })
			local bb = Instance.new("BillboardGui")
			bb.Name = "StationLabel"
			bb.Size = UDim2.fromOffset(160, 44)
			bb.AlwaysOnTop = false
			bb.MaxDistance = 400
			bb.Parent = anchor
			local t = Instance.new("TextLabel")
			t.Name = "Text"
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundColor3 = color
			t.TextColor3 = rgb(25, 25, 35)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.Text = "Desk " .. index
			t.Parent = bb
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.3, 0)
			corner.Parent = t
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Color = rgb(25, 25, 35)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = t

			stations[index] = {
				index = index,
				model = model,
				desk = desk,
				seat = seat,
				label = t,
				color = color,
				standCFrame = CFrame.new(x, 3, z + 7.5),
			}
		end
	end
	return stations
end

local function buildProjector()
	local hz = ClassroomBuilder.RoomSize.Z / 2
	local screen = part({ Name = "ProjectorScreen", Size = Vector3.new(44, 22, 0.4), Position = Vector3.new(0, 15, -hz + 0.4),
		Color = rgb(250, 250, 250), CanCollide = false })
	part({ Name = "ScreenFrame", Size = Vector3.new(46, 23.5, 0.3), Position = Vector3.new(0, 15, -hz + 0.15),
		Color = rgb(40, 40, 55), CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Parent = screen
	-- Projector on a cart at the back of the room with a soft beam
	part({ Name = "ProjectorCart", Size = Vector3.new(4, 5, 3), Position = Vector3.new(0, 2.5, 30),
		Color = rgb(60, 60, 75) })
	part({ Name = "Projector", Size = Vector3.new(3, 1.6, 2.4), Position = Vector3.new(0, 5.8, 30),
		Color = rgb(230, 230, 240) })
	local beamStart = Vector3.new(0, 6, 28.5)
	local beamEnd = Vector3.new(0, 15, -hz + 1)
	local dist = (beamEnd - beamStart).Magnitude
	part({ Name = "ProjectorBeam", Size = Vector3.new(6, 3, dist),
		CFrame = CFrame.lookAt((beamStart + beamEnd) / 2, beamEnd), Color = rgb(255, 255, 220),
		Material = Enum.Material.Neon, Transparency = 0.93, CanCollide = false, CanQuery = false, CastShadow = false })
	return screen
end

local function buildInteractives()
	local hx, hz = ClassroomBuilder.RoomSize.X / 2, ClassroomBuilder.RoomSize.Z / 2
	local out = {}

	local chalkboard = part({ Name = "Chalkboard", Size = Vector3.new(20, 11, 0.4), Position = Vector3.new(-35, 13, -hz + 0.4),
		Color = rgb(45, 90, 70), Material = Enum.Material.Slate, CanCollide = false })
	part({ Name = "ChalkboardFrame", Size = Vector3.new(21, 12, 0.3), Position = Vector3.new(-35, 13, -hz + 0.15),
		Color = rgb(150, 95, 60), Material = Enum.Material.Wood, CanCollide = false })
	out.chalkboardText = label(chalkboard, Enum.NormalId.Back, "Welcome to Doodle Disaster!", { Font = Enum.Font.PermanentMarker })
	-- Prompt lives on a small ledge players can actually reach.
	out.chalkboardLedge = part({ Name = "ChalkLedge", Size = Vector3.new(20, 1, 2), Position = Vector3.new(-35, 3, -hz + 1.5),
		Color = rgb(150, 95, 60), Material = Enum.Material.Wood })
	out.chalkboard = chalkboard

	-- Golden pencil trophy
	local pedestal = part({ Name = "PencilPedestal", Size = Vector3.new(5, 4, 5), Position = Vector3.new(38, 2, -26),
		Color = rgb(255, 255, 255), Material = Enum.Material.Marble })
	local pencilCF = CFrame.new(38, 9, -26) * CFrame.Angles(0, 0, math.rad(90))
	local pencil = part({ Name = "GoldenPencil", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 1.6, 1.6),
		CFrame = pencilCF, Color = rgb(255, 200, 40), Material = Enum.Material.Foil })
	part({ Name = "GoldenPencilTip", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5),
		CFrame = pencilCF * CFrame.new(-4.2, 0, 0), Color = rgb(255, 230, 150), Material = Enum.Material.Foil })
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = rgb(255, 230, 120)
	sparkle.Parent = pencil
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(14, 4) -- studs, so the label scales with the room instead of the screen
	bb.StudsOffset = Vector3.new(-3, 6, 0)
	bb.MaxDistance = 400
	bb.Parent = pencil
	local winner = Instance.new("TextLabel")
	winner.Size = UDim2.fromScale(1, 1)
	winner.BackgroundTransparency = 1
	winner.Font = Enum.Font.FredokaOne
	winner.TextScaled = true
	winner.TextWrapped = true
	winner.TextColor3 = rgb(255, 215, 60)
	winner.TextStrokeTransparency = 0
	winner.Text = "Golden Pencil"
	winner.Parent = bb
	out.pencil = pedestal
	out.pencilText = winner

	-- Trash can
	local can = part({ Name = "TrashCan", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 3.6, 3.6),
		CFrame = CFrame.new(-42, 2, 24) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(70, 150, 90),
		Material = Enum.Material.Metal })
	part({ Name = "TrashHole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 3, 3),
		CFrame = CFrame.new(-42, 4.02, 24) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(20, 20, 20),
		CanCollide = false })
	out.trashCan = can

	-- Suspicious button
	part({ Name = "ButtonPedestal", Size = Vector3.new(3, 3.5, 3), Position = Vector3.new(42, 1.75, 24),
		Color = rgb(60, 60, 75), Material = Enum.Material.DiamondPlate })
	local button = part({ Name = "SuspiciousButton", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 2.4, 2.4),
		CFrame = CFrame.new(42, 3.9, 24) * CFrame.Angles(0, 0, math.rad(90)), Color = rgb(255, 40, 40),
		Material = Enum.Material.Neon })
	local warn = Instance.new("BillboardGui")
	warn.Size = UDim2.fromOffset(160, 40)
	warn.StudsOffset = Vector3.new(0, 3, 0)
	warn.MaxDistance = 400
	warn.Parent = button
	local warnText = Instance.new("TextLabel")
	warnText.Size = UDim2.fromScale(1, 1)
	warnText.BackgroundTransparency = 1
	warnText.Font = Enum.Font.FredokaOne
	warnText.TextScaled = true
	warnText.TextColor3 = rgb(255, 60, 60)
	warnText.TextStrokeTransparency = 0
	warnText.Text = "DO NOT PRESS"
	warnText.Parent = warn
	out.button = button

	return out
end

function ClassroomBuilder.build()
	local old = Workspace:FindFirstChild("Classroom")
	if old then
		old:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Classroom"
	buildShell()
	local stations = buildStations()
	local screen = buildProjector()
	local interactives = buildInteractives()
	folder.Parent = Workspace
	return {
		folder = folder,
		stations = stations,
		screen = screen,
		interactives = interactives,
	}
end

return ClassroomBuilder
