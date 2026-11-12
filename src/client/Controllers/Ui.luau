--!strict
-- Ui: tiny helpers for building the procedural interface plus the shared visual theme.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Ui = {}

Ui.Theme = {
	Font = Enum.Font.FredokaOne,
	BodyFont = Enum.Font.GothamBold,
	Ink = Color3.fromRGB(25, 25, 35),
	Paper = Color3.fromRGB(255, 252, 240),
	Yellow = Color3.fromRGB(255, 215, 40),
	Pink = Color3.fromRGB(255, 120, 190),
	Blue = Color3.fromRGB(60, 170, 255),
	Green = Color3.fromRGB(80, 200, 110),
	Red = Color3.fromRGB(255, 90, 95),
	Purple = Color3.fromRGB(150, 100, 255),
	Orange = Color3.fromRGB(255, 150, 50),
	Grey = Color3.fromRGB(200, 200, 210),
}

-- Ui.new("Frame", { Size = ..., Parent = ... }, { children })
function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Ui.stroke(thickness: number?, color: Color3?): UIStroke
	return Ui.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Ui.Theme.Ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return Ui.new("UIPadding", { PaddingLeft = u, PaddingRight = u, PaddingTop = u, PaddingBottom = u })
end

function Ui.list(direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Ui.label(text: string, props: { [string]: any }?): TextLabel
	local base = {
		BackgroundTransparency = 1,
		Font = Ui.Theme.Font,
		Text = text,
		TextColor3 = Ui.Theme.Ink,
		TextScaled = true,
		TextWrapped = true,
		Size = UDim2.fromScale(1, 1),
	}
	for k, v in props or {} do
		if k ~= "MaxTextSize" then
			base[k] = v
		end
	end
	local l = Ui.new("TextLabel", base)
	Ui.new("UITextSizeConstraint", { MaxTextSize = (props and props.MaxTextSize) or 40, Parent = l })
	return l
end

-- Chunky cartoon button. onClick is connected to Activated (mouse, touch and gamepad).
function Ui.button(text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local base = {
		BackgroundColor3 = color,
		Font = Ui.Theme.Font,
		Text = text,
		TextColor3 = Ui.Theme.Ink,
		TextScaled = true,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(140, 44),
	}
	for k, v in props or {} do
		if k ~= "MaxTextSize" then
			base[k] = v
		end
	end
	local b = Ui.new("TextButton", base, { Ui.corner(12), Ui.stroke(3) })
	Ui.new("UITextSizeConstraint", { MaxTextSize = (props and props.MaxTextSize) or 26, Parent = b })
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = b })
	local scale = Ui.new("UIScale", { Parent = b })
	b.Activated:Connect(function()
		scale.Scale = 1
		TweenService:Create(scale, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
			{ Scale = 0.92 }):Play()
		onClick()
	end)
	return b
end

function Ui.panel(props: { [string]: any }?, children: { Instance }?): Frame
	local base = {
		BackgroundColor3 = Ui.Theme.Paper,
		BorderSizePixel = 0,
	}
	for k, v in props or {} do
		base[k] = v
	end
	local f = Ui.new("Frame", base, children)
	Ui.corner(18).Parent = f
	Ui.stroke(4).Parent = f
	return f
end

function Ui.screenGui(name: string, displayOrder: number?): ScreenGui
	return Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 1,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

-- Bouncy entrance animation.
function Ui.pop(obj: GuiObject)
	local scale = obj:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = obj })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Ui.clear(container: Instance, keepClass: { string }?)
	for _, c in container:GetChildren() do
		local keep = false
		for _, cls in keepClass or {} do
			if c:IsA(cls) then
				keep = true
			end
		end
		if not keep then
			c:Destroy()
		end
	end
end

function Ui.formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Ui
