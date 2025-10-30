-- Fioletus_MAIN.txt
-- UI + HttpGet loader (generated)

-- UI CREATION
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- remove old ui if exists
for _, c in ipairs(playerGui:GetChildren()) do
	if c.Name == "StrafeRingUI_v4_"..tostring(PlayerId) then safeDestroy(c) end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StrafeRingUI_v4_"..tostring(PlayerId)
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = FRAME_SIZE
frame.Position = UI_POS
frame.BackgroundColor3 = Color3.fromRGB(16,29,31)
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0,10)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Thickness = 2
frameStroke.Parent = frame

-- animate stroke color between two violets
local strokeColors = {Color3.fromRGB(212,61,146), Color3.fromRGB(160,0,213)}
spawn(function()
	local idx = 1
	while frameStroke and frameStroke.Parent do
		local nextColor = strokeColors[idx]
		idx = idx % #strokeColors + 1
		local ok, tw = pcall(function()
			return TweenService:Create(frameStroke, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Color = nextColor})
		end)
		if ok and tw then tw:Play(); tw.Completed:Wait() end
		wait(0.06)
	end
end)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 42)
title.Position = UDim2.new(0, 6, 0, 6)
title.BackgroundTransparency = 1
title.Text = "FioletusHub"
title.Font = Enum.Font.Arcade
title.TextSize = 32
title.TextColor3 = strokeColors[1]
title.TextStrokeTransparency = 0.7
title.Parent = frame

spawn(function()
	local i = 1
	while title and title.Parent do
		local col = strokeColors[i]
		i = i % #strokeColors + 1
		pcall(function()
			local tw = TweenService:Create(title, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {TextColor3 = col})
			tw:Play()
			tw.Completed:Wait()
		end)
		wait(0.05)
	end
end)

local function styleButton(btn)
	btn.Font = Enum.Font.Arcade
	btn.TextScaled = true
	btn.BackgroundColor3 = Color3.fromRGB(51,38,53)
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,6)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.6
	stroke.Color = Color3.fromRGB(212,61,146)
	stroke.Parent = btn
	return btn
end

local function styleTextBox(tb)
	tb.Font = Enum.Font.Arcade
	tb.TextScaled = true
	tb.BackgroundColor3 = Color3.fromRGB(51,38,53)
	tb.ClearTextOnFocus = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0,6)
	corner.Parent = tb
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.2
	stroke.Color = Color3.fromRGB(170,0,220)
	stroke.Parent = tb
	return tb
end

-- Controls
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0.20, -6, 0, 44)
toggleBtn.Position = UDim2.new(0, 6, 0, 66)
toggleBtn.Text = "OFF"
toggleBtn.Parent = frame
styleButton(toggleBtn)

local changeTargetBtn = Instance.new("TextButton")
changeTargetBtn.Size = UDim2.new(0.28, -6, 0, 44)
changeTargetBtn.Position = UDim2.new(0.22, 6, 0, 66)
changeTargetBtn.Text = "Change Target"
changeTargetBtn.Parent = frame
styleButton(changeTargetBtn)

local hotkeyBox = Instance.new("TextBox")
hotkeyBox.Size = UDim2.new(0.24, -6, 0, 44)
hotkeyBox.Position = UDim2.new(0.52, 6, 0, 66)
hotkeyBox.Text = "Hotkey: F"
hotkeyBox.Parent = frame
styleTextBox(hotkeyBox)

local chargeHotkeyBox = Instance.new("TextBox")
chargeHotkeyBox.Size = UDim2.new(0.24, -6, 0, 44)
chargeHotkeyBox.Position = UDim2.new(0.76, 6, 0, 66)
chargeHotkeyBox.Text = "Charge: G"
chargeHotkeyBox.Parent = frame
styleTextBox(chargeHotkeyBox)

local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(1, -12, 0, 24)
infoLabel.Position = UDim2.new(0, 6, 0, 116)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Nearest: — | Dist: — | Dir: CW | R: "..tostring(ORBIT_RADIUS_DEFAULT)
infoLabel.Font = Enum.Font.Arcade
infoLabel.TextSize = 14
infoLabel.TextColor3 = Color3.fromRGB(220,220,220)
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Parent = frame

local espBtn = Instance.new("TextButton")
espBtn.Size = UDim2.new(0.24, -6, 0, 36)
espBtn.Position = UDim2.new(0.76, 6, 0, 148)
espBtn.Text = "PlayerESP"
espBtn.Parent = frame
styleButton(espBtn)

local espGearBtn = Instance.new("TextButton")
espGearBtn.Size = UDim2.new(0.12, -6, 0, 36)
espGearBtn.Position = UDim2.new(0.88, 6, 0, 148)
espGearBtn.Text = ""
espGearBtn.Parent = frame
styleButton(espGearBtn)

-- Mode buttons
local modeContainer = Instance.new("Frame", frame)
modeContainer.Size = UDim2.new(1, -12, 0, 40)
modeContainer.Position = UDim2.new(0, 6, 0, 186)
modeContainer.BackgroundTransparency = 1

local function makeModeButton(name, x)
	local b = Instance.new("TextButton", modeContainer)
	b.Size = UDim2.new(0.24, -8, 1, 0)
	b.Position = UDim2.new(x, 6, 0, 0)
	b.Text = name
	styleButton(b)
	return b
end

local btnSmooth = makeModeButton("Smooth", 0)
local btnVelocity = makeModeButton("Velocity", 0.26)
local btnTwisted = makeModeButton("Twisted", 0.52)
local btnForce = makeModeButton("Force", 0.78)

-- SLIDER helper (dragging disables frame movement)
local sliderDraggingCount = 0

local function setFrameDraggableState(allowed)
	-- toggle draggable/active state for main frame and config pickers to prevent sliders from moving frames while dragging
	pcall(function() frame.Draggable = allowed; frame.Active = allowed end)
	pcall(function() if espPickerFrame then espPickerFrame.Draggable = allowed; espPickerFrame.Active = allowed end end)
	pcall(function() if lookAimPicker then lookAimPicker.Draggable = allowed; lookAimPicker.Active = allowed end end)
	pcall(function() if noFallPicker then noFallPicker.Draggable = allowed; noFallPicker.Active = allowed end end)
	pcall(function() if aimViewPicker then aimViewPicker.Draggable = allowed; aimViewPicker.Active = allowed end end)
	pcall(function() if pathPicker then pathPicker.Draggable = allowed; pathPicker.Active = allowed end end)
end

local function createSlider(parent, yOffset, labelText, minVal, maxVal, initialVal, formatFn)
	local container = Instance.new("Frame", parent)
	container.Size = UDim2.new(1, -12, 0, 36)
	container.Position = UDim2.new(0, 6, 0, yOffset)
	container.BackgroundTransparency = 1

	local lbl = Instance.new("TextLabel", container)
	lbl.Size = UDim2.new(0.5, 0, 1, 0)
	lbl.Position = UDim2.new(0, 6, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = labelText
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Font = Enum.Font.Arcade
	lbl.TextScaled = true

	local valLabel = Instance.new("TextLabel", container)
	valLabel.Size = UDim2.new(0.5, -8, 1, 0)
	valLabel.Position = UDim2.new(0.5, 0, 0, 0)
	valLabel.BackgroundTransparency = 1
	valLabel.Text = tostring(formatFn and formatFn(initialVal) or string.format("%.2f", initialVal))
	valLabel.Font = Enum.Font.Arcade
	valLabel.TextScaled = true
	valLabel.TextXAlignment = Enum.TextXAlignment.Right

	local sliderBg = Instance.new("Frame", container)
	sliderBg.Size = UDim2.new(1, -12, 0, 8)
	sliderBg.Position = UDim2.new(0, 6, 0, 20)
	sliderBg.BackgroundColor3 = Color3.fromRGB(40,40,40)
	sliderBg.BorderSizePixel = 0
	sliderBg.ClipsDescendants = true
	local bgCorner = Instance.new("UICorner", sliderBg); bgCorner.CornerRadius = UDim.new(0,4)
	local bgStroke = Instance.new("UIStroke", sliderBg); bgStroke.Color = Color3.fromRGB(170,0,220)

	local fill = Instance.new("Frame", sliderBg)
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Position = UDim2.new(0,0,0,0)
	fill.BackgroundColor3 = Color3.fromRGB(245,136,212)
	fill.BorderSizePixel = 0
	local fillCorner = Instance.new("UICorner", fill); fillCorner.CornerRadius = UDim.new(0,4)

	local thumb = Instance.new("Frame", sliderBg)
	thumb.Size = UDim2.new(0, 16, 0, 16)
	thumb.Position = UDim2.new(0, -8, 0.5, -8)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.BackgroundColor3 = Color3.fromRGB(245,136,212)
	thumb.BorderSizePixel = 0
	local thumbCorner = Instance.new("UICorner", thumb); thumbCorner.CornerRadius = UDim.new(0,2)
	local thumbStroke = Instance.new("UIStroke", thumb); thumbStroke.Color = Color3.fromRGB(245,136,212)

	local dragging = false
	local sliderWidth = 0
	local function recalc()
		sliderWidth = sliderBg.AbsoluteSize.X
	end
	sliderBg:GetPropertyChangedSignal("AbsoluteSize"):Connect(recalc)
	recalc()

	local minV, maxV = minVal, maxVal

	local function setFromX(x)
		if sliderWidth <= 0 then return end
		local rel = clamp(x/sliderWidth, 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		thumb.Position = UDim2.new(rel, 0, 0.5, -8)
		local v = minV + (maxV - minV) * rel
		valLabel.Text = tostring(formatFn and formatFn(v) or string.format("%.2f", v))
		return v
	end

	local function startDrag(input)
		dragging = true
		sliderDraggingCount = sliderDraggingCount + 1
		setFrameDraggableState(false)
		local localX = input.Position.X - sliderBg.AbsolutePosition.X
		setFromX(localX)
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				sliderDraggingCount = math.max(0, sliderDraggingCount - 1)
				if sliderDraggingCount == 0 then setFrameDraggableState(true) end
			end
		end)
	end

	sliderBg.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startDrag(input)
		end
	end)

	thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startDrag(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.Position then
			local localX = input.Position.X - sliderBg.AbsolutePosition.X
			setFromX(localX)
		end
	end)

	UserInputService.TouchMoved:Connect(function(touch, g)
		if dragging then
			local localX = touch.Position.X - sliderBg.AbsolutePosition.X
			setFromX(localX)
		end
	end)

	local function getValue()
		local rel = 0
		if sliderWidth > 0 then rel = fill.AbsoluteSize.X / sliderWidth end
		return minV + (maxV - minV) * rel
	end

	local function setRange(minVv, maxVv, initV)
		minV, maxV = minVv, maxVv
		if initV then
			local rel = 0
			if maxV ~= minV then rel = (initV - minV) / (maxV - minV) end
			fill.Size = UDim2.new(clamp(rel,0,1),0,1,0)
			thumb.Position = UDim2.new(clamp(rel,0,1),0,0.5,-8)
			valLabel.Text = tostring(formatFn and formatFn(initV) or string.format("%.2f", initV))
		end
	end

	local function setLabel(txt) lbl.Text = txt end

	return {
		Container = container,
		GetValue = getValue,
		SetValue = function(v)
			if maxV == minV then return end
			local rel = (v - minV) / (maxV - minV)
			fill.Size = UDim2.new(clamp(rel,0,1),0,1,0)
			thumb.Position = UDim2.new(clamp(rel,0,1),0,0.5,-8)
			valLabel.Text = tostring(formatFn and formatFn(v) or string.format("%.2f", v))
		end,
		SetRange = setRange,
		SetLabel = setLabel,
		ValueLabel = valLabel,
		IsDragging = function() return dragging end,
	}
end

-- create sliders
local sliderSpeed = createSlider(frame, 236, "Orbit Speed", 0.2, 6.0, ORBIT_SPEED_BASE, function(v) return string.format("%.2f", v) end)
local sliderRadius = createSlider(frame, 284, "Orbit Radius", 0.5, 8.0, ORBIT_RADIUS_DEFAULT, function(v) return string.format("%.2f", v) end)
local sliderForce = createSlider(frame, 332, "Force Power", SLIDER_LIMITS.FORCE_POWER_MIN, SLIDER_LIMITS.FORCE_POWER_MAX, SLIDER_LIMITS.FORCE_POWER_DEFAULT, function(v) return string.format("%.0f", v) end)
sliderForce.Container.Visible = false
local sliderSearch = createSlider(frame, 380, "Search Radius", 5, 150, SEARCH_RADIUS_DEFAULT, function(v) return string.format("%.1f", v) end)
