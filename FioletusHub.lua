local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0
local Camera = workspace.CurrentCamera

-- CONFIG
local SEARCH_RADIUS_DEFAULT = 15

-- Named config table for quick edits (colors / common sliders)
local tab = {
	ESP_R = 212,
	ESP_G = 61,
	ESP_B = 146,
	ORBIT_RADIUS_DEFAULT = 3.2,
	ORBIT_SPEED_BASE = 2.2,
	SEARCH_RADIUS_DEFAULT = 15,
	PATH_SAMPLE_DIST_STEP = 1.2,
	PATH_MAX_SAMPLES = 18,
}

local SEGMENTS = 64
local RING_RADIUS = 2.6
local SEGMENT_HEIGHT = 0.14
local SEGMENT_THICK = 0.45
local RING_HEIGHT_BASE = -1.5
local RING_COLOR = Color3.fromRGB(255, 0, 170)
local RING_TRANSP = 0.22

local SLIDER_LIMITS = {
	BV_POWER_MIN = 50,
	BV_POWER_MAX = 1000,
	BV_POWER_DEFAULT = 200,

	TWIST_MIN = 10,
	TWIST_MAX = 1000,
	TWIST_DEFAULT = 120,

	FORCE_SPEED_MIN = 10,
	FORCE_SPEED_MAX = 10000,
	FORCE_SPEED_DEFAULT = 120,

	FORCE_POWER_MIN = 50,
	FORCE_POWER_MAX = 8000,
	FORCE_POWER_DEFAULT = 1200,
}

local ORBIT_RADIUS_DEFAULT = 3.2
local ORBIT_SPEED_BASE = 2.2
local ALIGN_MAX_FORCE = 5e4
local ALIGN_MIN_FORCE = 500
local ALIGN_RESPONSIVENESS = 18

local HELPER_SPRING = 90
local HELPER_DAMP = 14
local HELPER_MAX_SPEED = 60
local HELPER_MAX_ACCEL = 4000
local HELPER_SMOOTH_INTERP = 12

local ORBIT_NOISE_FREQ = 0.45
local ORBIT_NOISE_AMP = 0.9
local ORBIT_BURST_CHANCE_PER_SEC = 0.6
local ORBIT_BURST_MIN = 1.2
local ORBIT_BURST_MAX = 3.2
local DRIFT_FREQ = 0.12
local DRIFT_AMP = 0.45

-- PATHING (heuristic)
local PATH_SAMPLE_ANGLE_STEPS = 24
local PATH_SAMPLE_DIST_STEP = 1.2
local PATH_MAX_SAMPLES = 18

local UI_POS = UDim2.new(0.5, -310, 0.82, -210)
local FRAME_SIZE = UDim2.new(0, 620, 0, 460) -- немного выше для дополнительных кнопок

-- UTIL
local function getHRP(player)
	local ch = player and player.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function safeDestroy(obj)
	if obj and obj.Parent then
		pcall(function() obj:Destroy() end)
	end
end

local function charToKeyCode(str)
	if not str or #str == 0 then return nil end
	local s = tostring(str):upper()
	if s == "-" then return "-" end
	local ok, val = pcall(function() return Enum.KeyCode[s] end)
	if ok and val then return val end
	return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a,b,t) return a + (b-a) * t end

-- robust raycast down helper
local function raycastDown(origin, maxDist, ignoreInst)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	if ignoreInst then rp.FilterDescendantsInstances = {ignoreInst} end
	local res = Workspace:Raycast(origin, Vector3.new(0, -maxDist, 0), rp)
	return res
end

-- PERSISTENCE: store values under Player to survive respawn; also use Attributes if present
local persistFolder = nil
local function ensurePersistFolder()
	if persistFolder and persistFolder.Parent then return end
	persistFolder = LocalPlayer:FindFirstChild("StrafePersist")
	if not persistFolder then
		persistFolder = Instance.new("Folder")
		persistFolder.Name = "StrafePersist"
		persistFolder.Parent = LocalPlayer
	end
end

local function writePersistValue(name, value)
	ensurePersistFolder()
	local existing = persistFolder:FindFirstChild(name)
	if existing then
		if existing:IsA("BoolValue") then existing.Value = (value and true or false) end
		if existing:IsA("NumberValue") then existing.Value = tonumber(value) or 0 end
		if existing:IsA("StringValue") then existing.Value = tostring(value) end
	else
		local typ = type(value)
		if typ == "boolean" then
			local v = Instance.new("BoolValue")
			v.Name = name
			v.Value = value
			v.Parent = persistFolder
		elseif typ == "number" then
			local v = Instance.new("NumberValue")
			v.Name = name
			v.Value = value
			v.Parent = persistFolder
		else
			local v = Instance.new("StringValue")
			v.Name = name
			v.Value = tostring(value)
			v.Parent = persistFolder
		end
	end
	pcall(function() if LocalPlayer.SetAttribute then LocalPlayer:SetAttribute(name, value) end end)
end

local function readPersistValue(name, default)
	ensurePersistFolder()
	local existing = persistFolder:FindFirstChild(name)
	if existing then
		if existing:IsA("BoolValue") then return existing.Value end
		if existing:IsA("NumberValue") then return existing.Value end
		if existing:IsA("StringValue") then return existing.Value end
	end
	if LocalPlayer.GetAttribute then
		local ok, val = pcall(function() return LocalPlayer:GetAttribute(name) end)
		if ok and val ~= nil then return val end
	end
	return default
end

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
espBtn.Visible = false -- hidden in MainFrame; VisualFrame will expose the button
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

-- RUNTIME STATE
local enabled = false
currentTargetCharConn = nil
currentTargetRemovingConn = nil
local currentTarget = nil
local ringParts = {}
local folder = nil

local mode = "smooth"

local attach0, helperPart, helperAttach, alignObj = nil, nil, nil, nil
local bvObj, bgObj, lvObj = nil, nil, nil
local vfObj, vfAttach, fallbackForceBV = nil, nil, nil

local charHumanoid = nil
local helperVel = Vector3.new(0,0,0)

local orbitAngle = math.random() * math.pi * 2
local orbitDirection = 1
local lastNoFallCheck = 0
local orbitRadius = ORBIT_RADIUS_DEFAULT
local ORBIT_SPEED = ORBIT_SPEED_BASE
local steeringInput = 0
local shiftHeld = false

local hotkeyKeyCode = Enum.KeyCode.F
local hotkeyStr = "F"
local hotkeyRequireCtrl, hotkeyRequireShift, hotkeyRequireAlt = false, false, false
local ctrlHeld, altHeld = false, false

local chargeKeyCode = Enum.KeyCode.G
local chargeHotkeyStr = "G"
local chargeRequireCtrl, chargeRequireShift, chargeRequireAlt = false, false, false

local cycleKeyCode = Enum.KeyCode.H
local cycleHotkeyStr = "H"

local burstTimer = 0
local burstStrength = 0
local driftPhase = math.random() * 1000

local chargeTimer = 0
local CHARGE_DURATION = 0.45
local CHARGE_STRENGTH = 4.0

local espEnabled = false
local playerHighlights = {}

local espColor = {R=212, G=61, B=146}

local autoJumpEnabled = false

local lookAimEnabled = false
local lookAimTargetPart = "Head"
local noFallEnabled = false
local noFallThreshold = 4 -- studs
local checkWallEnabled = false

-- restore saved camera FOV (from persisted value)
local savedFOV_val = tonumber(readPersistValue('Strafe_sliderFOV', nil))
if savedFOV_val and workspace and workspace.CurrentCamera then pcall(function() workspace.CurrentCamera.FieldOfView = savedFOV_val end) end

-- PERSISTENCE helpers (use both attribute+values)
local function saveState()
	-- simple mapping of important vars
	writePersistValue("Strafe_enabled", enabled and 1 or 0)
	writePersistValue("Strafe_mode", mode)
	writePersistValue("Strafe_hotkey", hotkeyStr)
	writePersistValue("Strafe_orbitRadius", orbitRadius)
	writePersistValue("Strafe_orbitSpeed", ORBIT_SPEED)
	writePersistValue("Strafe_forcePower", tonumber(sliderForce.GetValue()) or SLIDER_LIMITS.FORCE_POWER_DEFAULT)
	writePersistValue("Strafe_chargeHotkey", chargeHotkeyStr)
	writePersistValue("Strafe_searchRadius", tonumber(sliderSearch.GetValue()) or SEARCH_RADIUS_DEFAULT)
	writePersistValue("Strafe_esp", espEnabled and 1 or 0)
	writePersistValue("Strafe_espR", espColor.R)
	writePersistValue("Strafe_espG", espColor.G)
	writePersistValue("Strafe_espB", espColor.B)
	writePersistValue("Strafe_autojump", autoJumpEnabled and 1 or 0)
	writePersistValue("Strafe_lookAim", lookAimEnabled and 1 or 0)
	writePersistValue("Strafe_lookAimPart", lookAimTargetPart)
	writePersistValue("Strafe_noFall", noFallEnabled and 1 or 0)
	writePersistValue("Strafe_noFallThreshold", noFallThreshold)
	writePersistValue("Strafe_checkWall", checkWallEnabled and 1 or 0)
	writePersistValue("Strafe_lookAimStrength", tostring(getLookAimStrength and getLookAimStrength() or 0.12))
	writePersistValue("Strafe_aimView", aimViewEnabled and 1 or 0)
	writePersistValue("Strafe_aimViewMode", aimViewRotateMode)
	writePersistValue("Strafe_aimViewRange", tostring(avSlider and avSlider.GetValue and avSlider.GetValue() or orbitRadius))
	-- persist slider values explicitly
	if sliderSpeed and sliderSpeed.GetValue then writePersistValue('Strafe_sliderSpeed', tostring(sliderSpeed.GetValue())) end
	if sliderRadius and sliderRadius.GetValue then writePersistValue('Strafe_sliderRadius', tostring(sliderRadius.GetValue())) end
	if sliderForce and sliderForce.GetValue then writePersistValue('Strafe_sliderForce', tostring(sliderForce.GetValue())) end
	if sliderSearch and sliderSearch.GetValue then writePersistValue('Strafe_sliderSearch', tostring(sliderSearch.GetValue())) end
	if workspace and workspace.CurrentCamera then pcall(function() writePersistValue('Strafe_sliderFOV', tostring(workspace.CurrentCamera.FieldOfView)) end) end
	if lookAimStrengthSlider and lookAimStrengthSlider.GetValue then writePersistValue('Strafe_lookAimStrength', tostring(lookAimStrengthSlider.GetValue())) end
	if avSlider and avSlider.GetValue then writePersistValue('Strafe_aimViewRange', tostring(avSlider.GetValue())) end

end


local function loadState()
	local e = readPersistValue("Strafe_enabled", 0)
	enabled = (tonumber(e) or 0) ~= 0
	local m = readPersistValue("Strafe_mode", mode)
	if type(m) == "string" then mode = m end
	local hk = readPersistValue("Strafe_hotkey", hotkeyStr)
	if hk then hotkeyStr = tostring(hk) end
	local orad = tonumber(readPersistValue("Strafe_orbitRadius", orbitRadius)) or orbitRadius
	orbitRadius = orad; sliderRadius.SetValue(orbitRadius)
	local ospeed = tonumber(readPersistValue("Strafe_orbitSpeed", ORBIT_SPEED)) or ORBIT_SPEED
	ORBIT_SPEED = ospeed; sliderSpeed.SetValue(ORBIT_SPEED)
	local fpow = tonumber(readPersistValue("Strafe_forcePower", SLIDER_LIMITS.FORCE_POWER_DEFAULT)) or SLIDER_LIMITS.FORCE_POWER_DEFAULT
	sliderForce.SetValue(fpow)
	local ch = readPersistValue("Strafe_chargeHotkey", chargeHotkeyStr)
	if ch then chargeHotkeyStr = tostring(ch) end
	local sr = tonumber(readPersistValue("Strafe_searchRadius", SEARCH_RADIUS_DEFAULT)) or SEARCH_RADIUS_DEFAULT
	sliderSearch.SetValue(sr)
	espEnabled = (tonumber(readPersistValue("Strafe_esp", espEnabled and 1 or 0)) or 0) ~= 0
	local rcol = tonumber(readPersistValue("Strafe_espR", espColor.R)) or espColor.R
	local gcol = tonumber(readPersistValue("Strafe_espG", espColor.G)) or espColor.G
	local bcol = tonumber(readPersistValue("Strafe_espB", espColor.B)) or espColor.B
	espColor.R, espColor.G, espColor.B = rcol, gcol, bcol
	autoJumpEnabled = (tonumber(readPersistValue("Strafe_autojump", autoJumpEnabled and 1 or 0)) or 0) ~= 0
	lookAimEnabled = (tonumber(readPersistValue("Strafe_lookAim", lookAimEnabled and 1 or 0)) or 0) ~= 0
	lookAimTargetPart = tostring(readPersistValue("Strafe_lookAimPart", lookAimTargetPart))
	noFallEnabled = (tonumber(readPersistValue("Strafe_noFall", noFallEnabled and 1 or 0)) or 0) ~= 0
	noFallThreshold = tonumber(readPersistValue("Strafe_noFallThreshold", noFallThreshold)) or noFallThreshold
	checkWallEnabled = (tonumber(readPersistValue("Strafe_checkWall", checkWallEnabled and 1 or 0)) or 0) ~= 0

	-- load aimView range and lookAim strength if present
	local avr = tonumber(readPersistValue("Strafe_aimViewRange", orbitRadius)) or orbitRadius
	if avSlider and avSlider.SetValue then pcall(function() avSlider.SetValue(avr) end) end
	local las = tonumber(readPersistValue("Strafe_lookAimStrength", 0.12)) or 0.12
	if lookAimStrengthSlider and lookAimStrengthSlider.SetValue then pcall(function() lookAimStrengthSlider.SetValue(las) end) end
	-- load new settings
	local las = tonumber(readPersistValue("Strafe_lookAimStrength", 0.12)) or 0.12
	if lookAimStrengthSlider and lookAimStrengthSlider.SetValue then pcall(function() lookAimStrengthSlider.SetValue(las) end) end
	aimViewEnabled = (tonumber(readPersistValue("Strafe_aimView", aimViewEnabled and 1 or 0)) or 0) ~= 0
	aimViewRotateMode = tostring(readPersistValue("Strafe_aimViewMode", aimViewRotateMode))
	-- restore explicit slider values
	local ss = tonumber(readPersistValue('Strafe_sliderSpeed', nil)) if ss and sliderSpeed and sliderSpeed.SetValue then pcall(function() sliderSpeed.SetValue(ss) end) end
	local sr = tonumber(readPersistValue('Strafe_sliderRadius', nil)) if sr and sliderRadius and sliderRadius.SetValue then pcall(function() sliderRadius.SetValue(sr) end) end
	local sf = tonumber(readPersistValue('Strafe_sliderForce', nil)) if sf and sliderForce and sliderForce.SetValue then pcall(function() sliderForce.SetValue(sf) end) end
	local ssearch = tonumber(readPersistValue('Strafe_sliderSearch', nil)) if ssearch and sliderSearch and sliderSearch.SetValue then pcall(function() sliderSearch.SetValue(ssearch) end) end
	local lk = tonumber(readPersistValue('Strafe_lookAimStrength', nil)) if lk and lookAimStrengthSlider and lookAimStrengthSlider.SetValue then pcall(function() lookAimStrengthSlider.SetValue(lk) end) end
	local avr = tonumber(readPersistValue('Strafe_aimViewRange', nil)) if avr and avSlider and avSlider.SetValue then pcall(function() avSlider.SetValue(avr) end) end

end

-- ring helpers
local function ensureFolder()
	if folder and folder.Parent then return end
	folder = Instance.new("Folder")
	folder.Name = "StrafeRing_v4_"..tostring(PlayerId)
	folder.Parent = workspace
end

local function clearRing()

	if folder then
		for _, v in ipairs(folder:GetChildren()) do safeDestroy(v) end
		-- destroy the folder itself to avoid invisible leftovers
		pcall(function() if folder and folder.Parent then folder:Destroy() end end)
	end
	folder = nil
	ringParts = {}
ringParts = {}
end

local function createRingSegments(count)
	clearRing()
	ensureFolder()
	local circumference = 2 * math.pi * RING_RADIUS
	local segLen = (circumference / count) * 1.14
	for i = 1, count do
		local part = Instance.new("Part")
		part.Size = Vector3.new(segLen, SEGMENT_HEIGHT, SEGMENT_THICK)
		part.Anchored = true
		part.CanCollide = false
		part.Locked = true
		part.Material = Enum.Material.Neon
		part.Color = RING_COLOR
		part.Transparency = RING_TRANSP
		part.CastShadow = false
		part.Name = "RingSeg"
		part.Parent = folder
		table.insert(ringParts, part)
	end
end

-- MODE object creators (smooth/velocity/twisted/force)
local function createSmoothObjectsFor(hrp)
	if alignObj or helperPart then return end
	attach0 = hrp:FindFirstChild("StrafeAttach0_"..tostring(PlayerId))
	if not attach0 then
		attach0 = Instance.new("Attachment")
		attach0.Name = "StrafeAttach0_"..tostring(PlayerId)
		attach0.Parent = hrp
	end

	helperPart = workspace:FindFirstChild("StrafeHelperPart_"..tostring(PlayerId))
	if not helperPart then
		helperPart = Instance.new("Part")
		helperPart.Name = "StrafeHelperPart_"..tostring(PlayerId)
		helperPart.Size = Vector3.new(0.2,0.2,0.2)
		helperPart.Transparency = 1
		helperPart.Anchored = true
		helperPart.CanCollide = false
		helperPart.CFrame = hrp.CFrame
		helperPart.Parent = workspace
	end

	helperAttach = helperPart:FindFirstChild("StrafeAttach1_"..tostring(PlayerId))
	if not helperAttach then
		helperAttach = Instance.new("Attachment")
		helperAttach.Name = "StrafeAttach1_"..tostring(PlayerId)
		helperAttach.Parent = helperPart
	end

	alignObj = hrp:FindFirstChild("StrafeAlignPos_"..tostring(PlayerId))
	if not alignObj then
		alignObj = Instance.new("AlignPosition")
		alignObj.Name = "StrafeAlignPos_"..tostring(PlayerId)
		alignObj.Attachment0 = attach0
		alignObj.Attachment1 = helperAttach
		alignObj.MaxForce = ALIGN_MIN_FORCE
		alignObj.Responsiveness = ALIGN_RESPONSIVENESS
		alignObj.RigidityEnabled = false
		pcall(function() alignObj.MaxVelocity = HELPER_MAX_SPEED end)
		alignObj.Parent = hrp
	end

	helperVel = Vector3.new(0,0,0)
end

local function destroySmoothObjects()
	safeDestroy(alignObj); alignObj = nil
	safeDestroy(attach0); attach0 = nil
	safeDestroy(helperAttach); helperAttach = nil
	safeDestroy(helperPart); helperPart = nil
	helperVel = Vector3.new(0,0,0)
end

local function createVelocityObjectsFor(hrp)
	if bvObj or bgObj then return end
	bvObj = hrp:FindFirstChild("Strafe_BV_"..tostring(PlayerId))
	bgObj = hrp:FindFirstChild("Strafe_BG_"..tostring(PlayerId))
	if not (bvObj and bgObj) then
		local bv = Instance.new("BodyVelocity")
		bv.Name = "Strafe_BV_"..tostring(PlayerId)
		bv.MaxForce = Vector3.new(ALIGN_MIN_FORCE, ALIGN_MIN_FORCE, ALIGN_MIN_FORCE)
		bv.P = 2500
		bv.Velocity = Vector3.new(0,0,0)
		bv.Parent = hrp

		local bg = Instance.new("BodyGyro")
		bg.Name = "Strafe_BG_"..tostring(PlayerId)
		bg.MaxTorque = Vector3.new(ALIGN_MIN_FORCE, ALIGN_MIN_FORCE, ALIGN_MIN_FORCE)
		bg.P = 2000
		bg.CFrame = hrp.CFrame
		bg.Parent = hrp

		bvObj, bgObj = bv, bg
	end
end

local function destroyVelocityObjects()
	safeDestroy(bvObj); bvObj = nil
	safeDestroy(bgObj); bgObj = nil
end

local function createLinearObjectsFor(hrp)
	if lvObj then return end
	local att = hrp:FindFirstChild("StrafeLVAttach")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "StrafeLVAttach"
		att.Parent = hrp
	end
	local lv = hrp:FindFirstChild("Strafe_LV_"..tostring(PlayerId))
	if not lv then
		lv = Instance.new("LinearVelocity")
		lv.Name = "Strafe_LV_"..tostring(PlayerId)
		lv.Attachment0 = att
		lv.MaxForce = 0
		lv.VectorVelocity = Vector3.new(0,0,0)
		lv.Parent = hrp
	end
	lvObj = lv
end

local function destroyLinearObjects()
	safeDestroy(lvObj); lvObj = nil
	local hrp = getHRP(LocalPlayer)
	if hrp then
		local att = hrp:FindFirstChild("StrafeLVAttach")
		if att then safeDestroy(att) end
	end
end

local function createForceObjectsFor(hrp)
	if vfObj or fallbackForceBV then return end
	local att = hrp:FindFirstChild("StrafeVFAttach")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "StrafeVFAttach"
		att.Parent = hrp
	end
	vfAttach = att

	local vf = hrp:FindFirstChild("Strafe_VectorForce_"..tostring(PlayerId))
	if not vf then
		local ok, v = pcall(function()
			local vv = Instance.new("VectorForce")
			vv.Name = "Strafe_VectorForce_"..tostring(PlayerId)
			vv.Attachment0 = att
			pcall(function() vv.RelativeTo = Enum.ActuatorRelativeTo.World end)
			vv.Force = Vector3.new(0,0,0)
			vv.Parent = hrp
			return vv
		end)
		if ok and v then vfObj = v end
	else vfObj = vf end

	if not vfObj then
		local bv = hrp:FindFirstChild("Strafe_ForceBV_"..tostring(PlayerId))
		if not bv then
			local ok2, b = pcall(function()
				local bb = Instance.new("BodyVelocity")
				bb.Name = "Strafe_ForceBV_"..tostring(PlayerId)
				bb.MaxForce = Vector3.new(0,0,0)
				bb.P = 3000
				bb.Velocity = Vector3.new(0,0,0)
				bb.Parent = hrp
				return bb
			end)
			if ok2 and b then fallbackForceBV = b end
		else fallbackForceBV = bv end
	end
end

local function destroyForceObjects()
	if vfObj then safeDestroy(vfObj); vfObj = nil end
	if fallbackForceBV then safeDestroy(fallbackForceBV); fallbackForceBV = nil end
	local hrp = getHRP(LocalPlayer)
	if hrp then
		local att = hrp:FindFirstChild("StrafeVFAttach")
		if att then safeDestroy(att) end
	end
end

local function destroyModeObjects()
	destroySmoothObjects()
	destroyVelocityObjects()
	destroyLinearObjects()
	destroyForceObjects()
end

-- TARGET management
local function setTarget(player, forceClear)
	if player == nil then
		currentTarget = nil
		clearRing()
		destroyModeObjects()
		return
	end
	if currentTarget == player and not forceClear then return end
	currentTarget = player
	clearRing()
	destroyModeObjects()
	if player then
		-- only create ring segments if RING mode is selected to avoid invisible leftovers
		if selectedTargetMode == "RING" then
			createRingSegments(SEGMENTS)
		end
		orbitAngle = math.random() * math.pi * 2
		local myHRP = getHRP(LocalPlayer)
		if myHRP then
			if mode == "smooth" then createSmoothObjectsFor(myHRP)
			elseif mode == "velocity" then createVelocityObjectsFor(myHRP)
			elseif mode == "twisted" then createLinearObjectsFor(myHRP)
			elseif mode == "force" then createForceObjectsFor(myHRP) end
		end
	end
	saveState()
	-- manage currentTarget live connections
	if currentTargetCharConn then pcall(function() currentTargetCharConn:Disconnect() end) end
	if currentTargetRemovingConn then pcall(function() currentTargetRemovingConn:Disconnect() end) end
	if currentTarget and currentTarget.Character then
		local ok, ch = pcall(function() return currentTarget.Character end)
		if ok and ch then
			currentTargetCharConn = ch:FindFirstChild("Humanoid") and ch:FindFirstChildOfClass("Humanoid").Died:Connect(function()
				setTarget(nil, true)
			end) or nil
		end
		-- also watch for character added (in case of respawn)
		currentTargetRemovingConn = currentTarget.CharacterRemoving and currentTarget.CharacterRemoving:Connect(function()
			setTarget(nil, true)
		end) or nil
	end

end

local function cycleTarget()
	local list = {}
	local myHRP = getHRP(LocalPlayer)
	if not myHRP then return end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then
			local hrp = getHRP(p)
			if hrp then
				local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass('Humanoid')
				local alive = hum and hum.Health and hum.Health > 0
				if alive then
					local d = (hrp.Position - myHRP.Position).Magnitude
					if d <= tonumber(sliderSearch.GetValue() or SEARCH_RADIUS_DEFAULT) then table.insert(list, {player=p, dist=d}) end
				end
			end
		end
	end
	table.sort(list, function(a,b) return a.dist < b.dist end)
	if #list == 0 then setTarget(nil); return end
	if not currentTarget then setTarget(list[1].player); return end
	local idx = nil
	for i,v in ipairs(list) do if v.player == currentTarget then idx = i; break end end
	if not idx then setTarget(list[1].player); return end
	setTarget(list[idx % #list + 1].player)
end

-- UI Mode handling + AutoJump visibility
local autoJumpBtn = nil
local function updateAutoJumpUIVisibility()
	if autoJumpBtn then
		autoJumpBtn.Visible = (mode == "force")
	end
end

local function applyModeUI()
	local function setActive(btn, active)
		if active then
			btn.BackgroundTransparency = 0.2
			btn.BackgroundColor3 = Color3.fromRGB(100,40,120)
		else
			btn.BackgroundTransparency = 0
			btn.BackgroundColor3 = Color3.fromRGB(51,38,53)
		end
	end
	setActive(btnSmooth, mode=="smooth")
	setActive(btnVelocity, mode=="velocity")
	setActive(btnTwisted, mode=="twisted")
	setActive(btnForce, mode=="force")

	if mode == "smooth" then
		sliderSpeed.SetLabel("Orbit Speed")
		sliderSpeed.SetRange(0.2, 6.0, ORBIT_SPEED)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = false
	elseif mode == "velocity" then
		sliderSpeed.SetLabel("BV Power")
		sliderSpeed.SetRange(SLIDER_LIMITS.BV_POWER_MIN, SLIDER_LIMITS.BV_POWER_MAX, SLIDER_LIMITS.BV_POWER_DEFAULT)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = false
	elseif mode == "twisted" then
		sliderSpeed.SetLabel("Twist Power")
		sliderSpeed.SetRange(SLIDER_LIMITS.TWIST_MIN, SLIDER_LIMITS.TWIST_MAX, SLIDER_LIMITS.TWIST_DEFAULT)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = false
	elseif mode == "force" then
		sliderSpeed.SetLabel("Force Speed")
		sliderSpeed.SetRange(SLIDER_LIMITS.FORCE_SPEED_MIN, SLIDER_LIMITS.FORCE_SPEED_MAX, SLIDER_LIMITS.FORCE_SPEED_DEFAULT)
		sliderRadius.SetLabel("Orbit Radius")
		sliderRadius.SetRange(0.5, 8.0, orbitRadius)
		sliderForce.Container.Visible = true
		sliderForce.SetRange(SLIDER_LIMITS.FORCE_POWER_MIN, SLIDER_LIMITS.FORCE_POWER_MAX, SLIDER_LIMITS.FORCE_POWER_DEFAULT)
	end

	updateAutoJumpUIVisibility()
end

btnSmooth.MouseButton1Click:Connect(function()
	if mode ~= "smooth" then
		mode = "smooth"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createSmoothObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)
btnVelocity.MouseButton1Click:Connect(function()
	if mode ~= "velocity" then
		mode = "velocity"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createVelocityObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)
btnTwisted.MouseButton1Click:Connect(function()
	if mode ~= "twisted" then
		mode = "twisted"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createLinearObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)
btnForce.MouseButton1Click:Connect(function()
	if mode ~= "force" then
		mode = "force"
		if currentTarget then
			destroyModeObjects()
			local myHRP = getHRP(LocalPlayer)
			if myHRP then createForceObjectsFor(myHRP) end
		end
		applyModeUI(); saveState()
	end
end)

-- Hotkey parsing (supports "-" unassigned)
local function parseHotkeyString(txt)
	if not txt then return nil end
	local s = tostring(txt):gsub("^%s*(.-)%s*$","%1")
	s = s:gsub("^Hotkey:%s*", "")
	s = s:gsub("^Charge:%s*", "")
	s = s:gsub("^Cycle:%s*", "")
	s = s:upper()
	s = s:gsub("%s+", "")
	if s == "-" then return "-", false, false, false end
	local parts = {}
	for token in s:gmatch("[^%+]+") do
		token = token:gsub("^%s*(.-)%s*$","%1")
		table.insert(parts, token)
	end
	local reqCtrl, reqShift, reqAlt = false, false, false
	local primary = nil
	for _, tok in ipairs(parts) do
		if tok == "CTRL" or tok == "CONTROL" then reqCtrl = true
		elseif tok == "SHIFT" then reqShift = true
		elseif tok == "ALT" then reqAlt = true
		else
			local kc = charToKeyCode(tok)
			if kc then primary = kc end
		end
	end
	if not primary then return nil end
	return primary, reqCtrl, reqShift, reqAlt
end

hotkeyBox.FocusLost:Connect(function()
	local txt = tostring(hotkeyBox.Text or ""):gsub("^%s*(.-)%s*$","%1")
	if #txt == 0 then hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F"); return end
	local primary, rCtrl, rShift, rAlt = parseHotkeyString(txt)
	if primary then
		if primary == "-" then
			hotkeyKeyCode = nil; hotkeyStr = "-"
			hotkeyBox.Text = "Hotkey: -"
			infoLabel.Text = "Hotkey cleared"
			saveState(); return
		end
		hotkeyKeyCode = primary
		hotkeyRequireCtrl = rCtrl
		hotkeyRequireShift = rShift
		hotkeyRequireAlt = rAlt
		local parts = {}
		if hotkeyRequireCtrl then table.insert(parts, "Ctrl") end
		if hotkeyRequireShift then table.insert(parts, "Shift") end
		if hotkeyRequireAlt then table.insert(parts, "Alt") end
		table.insert(parts, tostring(hotkeyKeyCode.Name))
		hotkeyStr = table.concat(parts, "+")
		hotkeyBox.Text = "Hotkey: "..hotkeyStr
		infoLabel.Text = "Hotkey set: "..hotkeyStr
		saveState()
	else
		hotkeyBox.Text = "Hotkey: "..(hotkeyStr or "F")
		infoLabel.Text = "Invalid hotkey."
	end
end)

chargeHotkeyBox.FocusLost:Connect(function()
	local txt = tostring(chargeHotkeyBox.Text or ""):gsub("^%s*(.-)%s*$","%1")
	if #txt == 0 then chargeHotkeyBox.Text = "Charge: "..(chargeHotkeyStr or "G"); return end
	local primary, rCtrl, rShift, rAlt = parseHotkeyString(txt)
	if primary then
		if primary == "-" then
			chargeKeyCode = nil; chargeHotkeyStr = "-"
			chargeHotkeyBox.Text = "Charge: -"
			infoLabel.Text = "Charge hotkey cleared"
			saveState(); return
		end
		chargeKeyCode = primary
		chargeRequireCtrl = rCtrl
		chargeRequireShift = rShift
		chargeRequireAlt = rAlt
		local parts = {}
		if chargeRequireCtrl then table.insert(parts, "Ctrl") end
		if chargeRequireShift then table.insert(parts, "Shift") end
		if chargeRequireAlt then table.insert(parts, "Alt") end
		table.insert(parts, tostring(chargeKeyCode.Name))
		chargeHotkeyStr = table.concat(parts, "+")
		chargeHotkeyBox.Text = "Charge: "..chargeHotkeyStr
		infoLabel.Text = "Charge hotkey set: "..chargeHotkeyStr
		saveState()
	else
		chargeHotkeyBox.Text = "Charge: "..(chargeHotkeyStr or "G")
		infoLabel.Text = "Invalid charge hotkey."
	end
end)

-- Toggle handler
local function updateToggleUI()
	toggleBtn.Text = enabled and "ON" or "OFF"
	toggleBtn.BackgroundColor3 = enabled and Color3.fromRGB(120,220,120) or Color3.fromRGB(220,120,120)
end

toggleBtn.MouseButton1Click:Connect(function()
	enabled = not enabled
	updateToggleUI()
	if not enabled then
		setTarget(nil, true)
		destroyModeObjects()
		infoLabel.Text = "Disabled"
	else
		infoLabel.Text = "Enabled: searching..."
		if currentTarget then
			local myHRP = getHRP(LocalPlayer)
			if myHRP then
				if mode == "smooth" then createSmoothObjectsFor(myHRP)
				elseif mode == "velocity" then createVelocityObjectsFor(myHRP)
				elseif mode == "twisted" then createLinearObjectsFor(myHRP)
				elseif mode == "force" then createForceObjectsFor(myHRP) end
			end
		end
	end
	saveState()
end)

changeTargetBtn.MouseButton1Click:Connect(cycleTarget)

-- ESP panel
local espPickerFrame = Instance.new("Frame")
espPickerFrame.Size = UDim2.new(0, 260, 0, 140)
espPickerFrame.Position = UDim2.new(0.5, -130, 0.5, -70)
espPickerFrame.BackgroundColor3 = Color3.fromRGB(16,29,31)
espPickerFrame.Visible = false
espPickerFrame.Parent = screenGui
espPickerFrame.Active = true
espPickerFrame.Draggable = true
local espPickerCorner = Instance.new("UICorner", espPickerFrame); espPickerCorner.CornerRadius = UDim.new(0,8)
local espPickerStroke = Instance.new("UIStroke", espPickerFrame); espPickerStroke.Thickness = 1.6; espPickerStroke.Color = Color3.fromRGB(160,0,213)
-- Ensure ESP stays applied reliably (fixes missed updates): periodic lightweight sync
spawn(function()
	while screenGui and screenGui.Parent do
		pcall(function()
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= LocalPlayer then
					if espEnabled then
						if p.Character then enableESPForPlayer(p) end
					else
						disableESPForPlayer(p)
					end
				end
			end
		end)
		wait(0.9)
	end
end)

local rSlider = createSlider(espPickerFrame, 8, "R", 1, 255, espColor.R, function(v) return tostring(math.floor(v)) end)
rSlider.Container.Position = UDim2.new(0, 8, 0, 8)
rSlider.Container.Size = UDim2.new(1, -16, 0, 28)
local gSlider = createSlider(espPickerFrame, 56, "G", 1, 255, espColor.G, function(v) return tostring(math.floor(v)) end)
gSlider.Container.Position = UDim2.new(0, 8, 0, 44)
gSlider.Container.Size = UDim2.new(1, -16, 0, 28)
local bSlider = createSlider(espPickerFrame, 104, "B", 1, 255, espColor.B, function(v) return tostring(math.floor(v)) end)
bSlider.Container.Position = UDim2.new(0, 8, 0, 80)
bSlider.Container.Size = UDim2.new(1, -16, 0, 28)

local colorPreview = Instance.new("TextLabel", espPickerFrame)
colorPreview.Size = UDim2.new(0, 48, 0, 48)
colorPreview.Position = UDim2.new(1, -56, 0, 8)
colorPreview.BackgroundColor3 = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
colorPreview.Text = ""
local cpCorner = Instance.new("UICorner", colorPreview); cpCorner.CornerRadius = UDim.new(0,6)

local function enableESPForPlayer(p)
	if not p or p == LocalPlayer then return end
	local ch = p.Character
	if not ch then return end
	-- destroy old highlight to avoid duplicates
	local existing = ch:FindFirstChild("StrafeESP_Highlight")
	if existing then safeDestroy(existing) end
	local hl = Instance.new("Highlight")
	hl.Name = "StrafeESP_Highlight"
	hl.Adornee = ch
	hl.FillTransparency = 0.4
	hl.OutlineTransparency = 0
	hl.FillColor = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
	hl.Parent = ch
	playerHighlights[p] = hl
end

local function disableESPForPlayer(p)
	local hl = playerHighlights[p]
	if hl then
		safeDestroy(hl)
		playerHighlights[p] = nil
	end
end

local function updateESP(enabledFlag)
	espEnabled = enabledFlag
	if espEnabled then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and p.Character then enableESPForPlayer(p) end
		end
		espBtn.TextColor3 = Color3.fromRGB(134,34,177)
	else
		for p,_ in pairs(playerHighlights) do disableESPForPlayer(p) end
		espBtn.TextColor3 = Color3.fromRGB(206,30,144)
	end
	saveState()
end

espBtn.MouseButton1Click:Connect(function() updateESP(not espEnabled) end)
espGearBtn.MouseButton1Click:Connect(function()
	espPickerFrame.Visible = not espPickerFrame.Visible
	if espPickerFrame.Visible then
		rSlider.SetValue(espColor.R)
		gSlider.SetValue(espColor.G)
		bSlider.SetValue(espColor.B)
	end
end)

RunService.RenderStepped:Connect(function()
	if espPickerFrame.Visible then
		local r = math.floor(rSlider.GetValue())
		local g = math.floor(gSlider.GetValue())
		local b = math.floor(bSlider.GetValue())
		espColor.R, espColor.G, espColor.B = r, g, b
		colorPreview.BackgroundColor3 = Color3.fromRGB(r,g,b)
		for p, hl in pairs(playerHighlights) do
			if hl and hl.Parent then hl.FillColor = Color3.fromRGB(r,g,b) end
		end
	end
end)

-- keep ESP updated for joins/resets
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(ch)
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end)
for _,p in ipairs(Players:GetPlayers()) do
	p.CharacterAdded:Connect(function(ch)
		if espEnabled and p ~= LocalPlayer then enableESPForPlayer(p) end
	end)
end
Players.PlayerRemoving:Connect(function(p)
	disableESPForPlayer(p)
	if p == currentTarget then setTarget(nil, true) end
end)

-- AutoJump helpers (robust)
local function isOnGround(humanoid, hrp)
	if not humanoid or not hrp then return false end
	-- Prefer Humanoid.FloorMaterial where possible
	local ok, state = pcall(function() return humanoid:GetState() end)
	if ok and state then
		if state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.PlatformStanding then return true end
	end
	-- raycast down check
	local r = raycastDown(hrp.Position + Vector3.new(0,0.5,0), 3, LocalPlayer.Character)
	if r and r.Instance then return true end
	-- fallback use Humanoid.FloorMaterial property if available
	local fmat = humanoid.FloorMaterial
	if fmat and fmat ~= Enum.Material.Air then return true end
	return false
end

local function tryAutoJump()
	if not autoJumpEnabled then return end
	if mode ~= "force" then return end
	if not enabled then return end
	local hrp = getHRP(LocalPlayer)
	if not hrp then return end
	local humanoid = charHumanoid
	if not humanoid then return end
	if isOnGround(humanoid, hrp) then
		humanoid.Jump = true
	end
end

-- PATHING: heuristic sampling around target (no PathfindingService)
local function samplePointAround(targetPos)
	for r = 1, PATH_MAX_SAMPLES do
		local dist = PATH_SAMPLE_DIST_STEP * r
		for i = 1, PATH_SAMPLE_ANGLE_STEPS do
			local ang = (i / PATH_SAMPLE_ANGLE_STEPS) * math.pi * 2
			local p = targetPos + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
			p = p + Vector3.new(0, 1.2, 0)
			local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Blacklist; rp.FilterDescendantsInstances = {LocalPlayer.Character}; local res = Workspace:Raycast(p, Vector3.new(0, -3, 0), rp)
			if res and res.Instance and not res.Instance:IsDescendantOf(LocalPlayer.Character) then
				-- ensure line from player position to sample is clear (or at least less blocked)
				return p
			end
		end
	end
	return nil
end



local function findAlternateWaypoint(playerHRP, targetHRP)
	if not playerHRP or not targetHRP then return nil end
	local startPos = playerHRP.Position
	local goalPos = targetHRP.Position + Vector3.new(0,1.2,0)

	-- prepare raycast params (ignore local character and the target's character)
	local rpParams = RaycastParams.new()
	rpParams.FilterType = Enum.RaycastFilterType.Blacklist
	rpParams.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}

	-- if direct path is clear, no waypoint needed
	local direct = Workspace:Raycast(startPos, goalPos - startPos, rpParams)
	if not direct then return nil end

	-- lightweight cache to avoid frequent heavy sampling
	if not _G._strafePathCache then _G._strafePathCache = {} end
	local cacheKey = tostring(math.floor(goalPos.X*10))..':'..tostring(math.floor(goalPos.Y*10))..':'..tostring(math.floor(goalPos.Z*10))
	local cached = _G._strafePathCache[cacheKey]
	if cached and (tick() - cached.time) < 1.5 then
		return cached.pos
	end

	-- adapt sampling based on distance
	local dist = (goalPos - startPos).Magnitude
	local baseSamples = 16
	local angleSamples = math.clamp(math.floor(baseSamples * (math.min(dist/10, 3) )), 8, 64)
	local radii = {0.8, 1.8, 3.2, math.max(4, math.min(8, dist*0.35))}

	-- Try ring samples around goal; for each candidate make sure:
	-- 1) there is ground beneath the sample (raycast down)
	-- 2) start->sample and sample->goal are both unobstructed (raycasts)
	for _, r in ipairs(radii) do
		for i = 0, angleSamples - 1 do
			local a = (i / angleSamples) * (2 * math.pi)
			local cand = goalPos + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)

			-- raycast down to snap to floor (avoid mid-air or inside walls)
			local down = Workspace:Raycast(cand + Vector3.new(0, 8, 0), Vector3.new(0, -16, 0), rpParams)
			if down then
				local candPos = Vector3.new(cand.X, down.Position.Y + 1.2, cand.Z)

				-- ensure candidate not inside the target's model
				if (candPos - targetHRP.Position).Magnitude > 1.0 then
					-- check start -> candidate
					local r1 = Workspace:Raycast(startPos, candPos - startPos, rpParams)
					-- check candidate -> goal
					local r2 = Workspace:Raycast(candPos, goalPos - candPos, rpParams)

					if not r1 and not r2 then
						_G._strafePathCache[cacheKey] = {pos = candPos, time = tick()}
						return candPos
					end
				end
			end
		end
	end

	-- fallback: try stepping along the straight line and find a visible intermediate point
	local steps = math.clamp(math.floor(dist / 3) + 2, 3, 12)
	for i = 1, steps - 1 do
		local p = startPos + (goalPos - startPos) * (i / steps)
		local down = Workspace:Raycast(p + Vector3.new(0,8,0), Vector3.new(0,-16,0), rpParams)
		if down then
			local pPos = Vector3.new(p.X, down.Position.Y + 1.2, p.Z)
			local r1 = Workspace:Raycast(startPos, pPos - startPos, rpParams)
			local r2 = Workspace:Raycast(pPos, goalPos - pPos, rpParams)
			if not r1 and not r2 then
				_G._strafePathCache[cacheKey] = {pos = pPos, time = tick()}
				return pPos
			end
		end
	end

	return nil
end



-- Optimized CheckWall (throttled + cached) to reduce expensive raycasts
local _strafe_checkwall_cache = { lastTime = 0, interval = 0.12, target = nil, result = false }
local function fastCheckWall(myHRP, targetHRP)
	if not (myHRP and targetHRP) then return false end
	local now = tick()
	if _strafe_checkwall_cache.target == targetHRP and (now - _strafe_checkwall_cache.lastTime) < _strafe_checkwall_cache.interval then
		return _strafe_checkwall_cache.result
	end
	_strafe_checkwall_cache.target = targetHRP
	_strafe_checkwall_cache.lastTime = now
	local startPos = myHRP.Position + Vector3.new(0,1,0)
	local dir = targetHRP.Position - startPos
	local dist = dir.Magnitude
	if dist < 1.5 then _strafe_checkwall_cache.result = false; return false end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	rp.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}
	local ok, res = pcall(function() return Workspace:Raycast(startPos, dir, rp) end)
	_strafe_checkwall_cache.result = (ok and res ~= nil)
	return _strafe_checkwall_cache.result
end

-- LookAim UI
local lookAimBtn = Instance.new("TextButton", frame)
lookAimBtn.Size = UDim2.new(0, 120, 0, 34)
lookAimBtn.Position = UDim2.new(0, 6, 0, 232)
lookAimBtn.Text = "LookAim: OFF"
styleButton(lookAimBtn)
local lookAimConfigBtn = Instance.new("TextButton", frame)
lookAimConfigBtn.Size = UDim2.new(0, 36, 0, 34)
lookAimConfigBtn.Position = UDim2.new(0, 130, 0, 232)
lookAimConfigBtn.Text = "T"
styleButton(lookAimConfigBtn)

local lookAimPicker = Instance.new("Frame", screenGui)
lookAimPicker.Size = UDim2.new(0, 180, 0, 80)
lookAimPicker.Position = UDim2.new(0.5, -90, 0.5, -40)
lookAimPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
lookAimPicker.Visible = false
lookAimPicker.Active = true
lookAimPicker.Draggable = true
local lpCorner = Instance.new("UICorner", lookAimPicker); lpCorner.CornerRadius = UDim.new(0,8)
local headBtn = Instance.new("TextButton", lookAimPicker)
headBtn.Size = UDim2.new(1, -12, 0, 36)
headBtn.Position = UDim2.new(0, 6, 0, 8)
headBtn.Text = "Target: Head"
styleButton(headBtn)
local torsoBtn = Instance.new("TextButton", lookAimPicker)
torsoBtn.Size = UDim2.new(1, -12, 0, 36)
torsoBtn.Position = UDim2.new(0, 6, 0, 44)
torsoBtn.Text = "Target: Torso"
styleButton(torsoBtn)

-- LookAim strength slider
local lookAimStrength = 0.12
local lookAimStrengthSlider = createSlider(lookAimPicker, 44, "AimLookStrength", 0.01, 1.0, lookAimStrength, function(v) return string.format("%.2f", v) end)
lookAimStrengthSlider.Container.Position = UDim2.new(0,6,0,44)
lookAimStrengthSlider.Container.Size = UDim2.new(1,-12,0,36)
function getLookAimStrength() return tonumber(lookAimStrengthSlider and lookAimStrengthSlider.GetValue and lookAimStrengthSlider.GetValue() or lookAimStrength) end

lookAimBtn.MouseButton1Click:Connect(function()
	lookAimEnabled = not lookAimEnabled
	lookAimBtn.Text = "LookAim: " .. (lookAimEnabled and "ON" or "OFF")
	saveState()
end)
lookAimConfigBtn.MouseButton1Click:Connect(function()
	lookAimPicker.Visible = not lookAimPicker.Visible
end)
headBtn.MouseButton1Click:Connect(function()
	lookAimTargetPart = "Head"
	headBtn.BackgroundColor3 = Color3.fromRGB(100,40,120)
	torsoBtn.BackgroundColor3 = Color3.fromRGB(51,38,53)
	saveState()
end)
torsoBtn.MouseButton1Click:Connect(function()
	lookAimTargetPart = "Torso"
	torsoBtn.BackgroundColor3 = Color3.fromRGB(100,40,120)
	headBtn.BackgroundColor3 = Color3.fromRGB(51,38,53)
	saveState()
end)

-- NoFall UI
local noFallBtn = Instance.new("TextButton", frame)
noFallBtn.Size = UDim2.new(0, 120, 0, 34)
noFallBtn.Position = UDim2.new(0, 156, 0, 232)
noFallBtn.Text = "NoFall: OFF"
styleButton(noFallBtn)
local noFallConfigBtn = Instance.new("TextButton", frame)
noFallConfigBtn.Size = UDim2.new(0, 36, 0, 34)
noFallConfigBtn.Position = UDim2.new(0, 280, 0, 232)
noFallConfigBtn.Text = "S"
styleButton(noFallConfigBtn)

local noFallPicker = Instance.new("Frame", screenGui)
noFallPicker.Size = UDim2.new(0, 260, 0, 110)
noFallPicker.Position = UDim2.new(0.5, -130, 0.5, -55)
noFallPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
noFallPicker.Visible = false
noFallPicker.Active = true
noFallPicker.Draggable = true
local nfCorner = Instance.new("UICorner", noFallPicker); nfCorner.CornerRadius = UDim.new(0,8)
local nfLabel = Instance.new("TextLabel", noFallPicker)
nfLabel.Size = UDim2.new(1, -12, 0, 28)
nfLabel.Position = UDim2.new(0, 6, 0, 8)
nfLabel.Text = "NoFall Threshold (studs):"
nfLabel.BackgroundTransparency = 1
nfLabel.Font = Enum.Font.Arcade
nfLabel.TextScaled = true
local nfSlider = createSlider(noFallPicker, 40, "Threshold", 0, 30, noFallThreshold, function(v) return tostring(math.floor(v)) end)
nfSlider.Container.Position = UDim2.new(0, 6, 0, 40)
nfSlider.Container.Size = UDim2.new(1, -12, 0, 36)


-- == AimView ==
local aimViewEnabled = false
local aimViewRotateMode = "All" -- "Head" or "All"
local aimViewAxes = {X=true, Y=false, Z=false}
local aimViewRange = orbitRadius or 6

local aimViewBtn = Instance.new("TextButton", frame)
aimViewBtn.Size = UDim2.new(0, 120, 0, 34)
aimViewBtn.Position = UDim2.new(0, 456, 0, 232)
aimViewBtn.Text = "AimView: OFF"
styleButton(aimViewBtn)

local aimViewConfigBtn = Instance.new("TextButton", frame)
aimViewConfigBtn.Size = UDim2.new(0, 36, 0, 34)
aimViewConfigBtn.Position = UDim2.new(0, 580, 0, 232)
aimViewConfigBtn.Text = "A"
styleButton(aimViewConfigBtn)

local aimViewPicker = Instance.new("Frame", screenGui)
aimViewPicker.Size = UDim2.new(0, 220, 0, 140)
aimViewPicker.Position = UDim2.new(0.5, -110, 0.5, -70)
aimViewPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
aimViewPicker.Visible = false
aimViewPicker.Active = true
aimViewPicker.Draggable = true
local avCorner = Instance.new("UICorner", aimViewPicker); avCorner.CornerRadius = UDim.new(0,8)

local axisX = Instance.new("TextButton", aimViewPicker)
axisX.Size = UDim2.new(0.3, -8, 0, 28)
axisX.Position = UDim2.new(0, 6, 0, 8)
axisX.Text = "X"
styleButton(axisX)
local axisY = Instance.new("TextButton", aimViewPicker)
axisY.Size = UDim2.new(0.3, -8, 0, 28)
axisY.Position = UDim2.new(0.35, 6, 0, 8)
axisY.Text = "Y"
styleButton(axisY)
local axisZ = Instance.new("TextButton", aimViewPicker)
axisZ.Size = UDim2.new(0.3, -8, 0, 28)
axisZ.Position = UDim2.new(0.7, 6, 0, 8)
axisZ.Text = "Z"
styleButton(axisZ)

local avSlider = createSlider(aimViewPicker, 72, "AimView Range", 0.5, 12.0, aimViewRange, function(v) return string.format("%.2f", v) end)
avSlider.Container.Position = UDim2.new(0, 6, 0, 44)
avSlider.Container.Size = UDim2.new(1, -12, 0, 36)

local rotateBtn = Instance.new("TextButton", aimViewPicker)
rotateBtn.Size = UDim2.new(0.5, -8, 0, 26)
rotateBtn.Position = UDim2.new(0,6,0,112)
rotateBtn.Text = "Rotate: All"
styleButton(rotateBtn)

axisX.MouseButton1Click:Connect(function() aimViewAxes.X = not aimViewAxes.X axisX.BackgroundColor3 = aimViewAxes.X and Color3.fromRGB(100,40,120) or Color3.fromRGB(51,38,53) end)
axisY.MouseButton1Click:Connect(function() aimViewAxes.Y = not aimViewAxes.Y axisY.BackgroundColor3 = aimViewAxes.Y and Color3.fromRGB(100,40,120) or Color3.fromRGB(51,38,53) end)
axisZ.MouseButton1Click:Connect(function() aimViewAxes.Z = not aimViewAxes.Z axisZ.BackgroundColor3 = aimViewAxes.Z and Color3.fromRGB(100,40,120) or Color3.fromRGB(51,38,53) end)
rotateBtn.MouseButton1Click:Connect(function() if aimViewRotateMode == "All" then aimViewRotateMode = "Head" rotateBtn.Text = "Rotate: Head" else aimViewRotateMode = "All" rotateBtn.Text = "Rotate: All" end end)

aimViewBtn.MouseButton1Click:Connect(function() aimViewEnabled = not aimViewEnabled aimViewBtn.Text = "AimView: " .. (aimViewEnabled and "ON" or "OFF") saveState() end)
aimViewConfigBtn.MouseButton1Click:Connect(function() aimViewPicker.Visible = not aimViewPicker.Visible if aimViewPicker.Visible then avSlider.SetValue(aimViewRange) end end)

local aimGyro = nil
local function ensureAimGyro(hrp)
	if aimGyro and aimGyro.Parent then return end
	if aimGyro then pcall(function() aimGyro:Destroy() end) end
	aimGyro = Instance.new("BodyGyro")
	aimGyro.Name = "Strafe_AimGyro_"..tostring(PlayerId)
	aimGyro.MaxTorque = Vector3.new(1e8,1e8,1e8)
	aimGyro.P = 1e5
	aimGyro.D = 100
	aimGyro.Parent = hrp
end

local function applyAimView(hrp, targetHRP)
	if not aimViewEnabled or not hrp or not targetHRP then return end
	local desiredPos = targetHRP.Position
	local dir = (desiredPos - hrp.Position)
	local range = avSlider and avSlider.GetValue and avSlider.GetValue() or aimViewRange
	if dir.Magnitude > range then return end
	local lookCFrame = CFrame.new(hrp.Position, Vector3.new(desiredPos.X, hrp.Position.Y, desiredPos.Z))
	ensureAimGyro(hrp)
	if aimViewRotateMode == "Head" then
		local head = hrp.Parent and hrp.Parent:FindFirstChild("Head")
		if head then pcall(function() head.CFrame = CFrame.new(head.Position, desiredPos) end) end
	else
		pcall(function()
			aimGyro.CFrame = lookCFrame
			aimGyro.MaxTorque = Vector3.new(1e8, aimViewAxes.Y and 1e8 or 0, 1e8)
			aimGyro.Parent = hrp
		end)
	end
end

-- end AimView
noFallBtn.MouseButton1Click:Connect(function()
	noFallEnabled = not noFallEnabled
	noFallBtn.Text = "NoFall: " .. (noFallEnabled and "ON" or "OFF")
	saveState()
end)
noFallConfigBtn.MouseButton1Click:Connect(function()
	noFallPicker.Visible = not noFallPicker.Visible
	if noFallPicker.Visible then nfSlider.SetValue(noFallThreshold) end
end)
nfSlider.Container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() end)
nfSlider.Container:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() end)

-- PathFinding toggle UI
local pathBtn = Instance.new("TextButton", frame)
pathBtn.Size = UDim2.new(0, 120, 0, 34)
pathBtn.Position = UDim2.new(0, 306, 0, 232)
pathBtn.Text = "CheckWall: OFF"
styleButton(pathBtn)

pathBtn.MouseButton1Click:Connect(function()
	checkWallEnabled = not checkWallEnabled
	pathBtn.Text = "CheckWall: " .. (checkWallEnabled and "ON" or "OFF")
	saveState()
end)

-- AutoJump UI (visible only in Force mode)
autoJumpBtn = Instance.new("TextButton", frame)
autoJumpBtn.Size = UDim2.new(0, 120, 0, 34)
autoJumpBtn.Position = UDim2.new(0.02, 6, 0, 280)
autoJumpBtn.Text = "AutoJump: OFF"
styleButton(autoJumpBtn)
autoJumpBtn.Visible = false

local function updateAutoJumpUI()
	autoJumpBtn.Text = "AutoJump: " .. (autoJumpEnabled and "ON" or "OFF")
	autoJumpBtn.TextColor3 = autoJumpEnabled and Color3.fromRGB(134,34,177) or Color3.fromRGB(206,30,144)
end

autoJumpBtn.MouseButton1Click:Connect(function()
	autoJumpEnabled = not autoJumpEnabled
	updateAutoJumpUI()
	saveState()
end)

-- INPUT handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local kc = input.KeyCode
		if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then ctrlHeld = true end
		if kc == Enum.KeyCode.LeftAlt or kc == Enum.KeyCode.RightAlt then altHeld = true end
		if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then shiftHeld = true end

		if kc == Enum.KeyCode.A then steeringInput = -1
		elseif kc == Enum.KeyCode.D then steeringInput = 1
		elseif kc == Enum.KeyCode.Z then orbitRadius = math.max(0.5, orbitRadius - 0.2); sliderRadius.SetValue(orbitRadius)
		elseif kc == Enum.KeyCode.X then orbitRadius = math.min(8, orbitRadius + 0.2); sliderRadius.SetValue(orbitRadius)
		end

		-- main hotkey toggle (supports nil/unassigned)
		if hotkeyKeyCode and kc == hotkeyKeyCode then
			local okCtrl = (not hotkeyRequireCtrl) or ctrlHeld
			local okShift = (not hotkeyRequireShift) or shiftHeld
			local okAlt = (not hotkeyRequireAlt) or altHeld
			if okCtrl and okShift and okAlt then
				enabled = not enabled
				updateToggleUI()
				if enabled then
					infoLabel.Text = "Enabled: searching..."
					if currentTarget then
						local myHRP = getHRP(LocalPlayer)
						if myHRP then
							if mode == "smooth" then createSmoothObjectsFor(myHRP)
							elseif mode == "velocity" then createVelocityObjectsFor(myHRP)
							elseif mode == "twisted" then createLinearObjectsFor(myHRP)
							elseif mode == "force" then createForceObjectsFor(myHRP) end
						end
					end
				else
					setTarget(nil, true)
					destroyModeObjects()
					infoLabel.Text = "Disabled"
				end
				saveState()
			end
		end

		-- charge hotkey
		if chargeKeyCode and kc == chargeKeyCode then
			local okCtrl = (not chargeRequireCtrl) or ctrlHeld
			local okShift = (not chargeRequireShift) or shiftHeld
			local okAlt = (not chargeRequireAlt) or altHeld
			if okCtrl and okShift and okAlt then
				if currentTarget then
					chargeTimer = CHARGE_DURATION
					infoLabel.Text = ("Charging %s..."):format(tostring(currentTarget.Name))
				end
			end
		end

		-- cycle target
		if kc == cycleKeyCode then cycleTarget() end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local kc = input.KeyCode
		if kc == Enum.KeyCode.A or kc == Enum.KeyCode.D then steeringInput = 0 end
		if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then shiftHeld = false end
		if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then ctrlHeld = false end
		if kc == Enum.KeyCode.LeftAlt or kc == Enum.KeyCode.RightAlt then altHeld = false end
	end
end)

-- Character handlers
LocalPlayer.CharacterAdded:Connect(function(char)
	local hrp = char:WaitForChild("HumanoidRootPart", 6)
	if hrp then
		charHumanoid = char:FindFirstChildOfClass("Humanoid")
		if enabled and currentTarget then
			destroyModeObjects()
			if mode == "smooth" then createSmoothObjectsFor(hrp)
			elseif mode == "velocity" then createVelocityObjectsFor(hrp)
			elseif mode == "twisted" then createLinearObjectsFor(hrp)
			elseif mode == "force" then createForceObjectsFor(hrp) end
		end
		if espEnabled then
			for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character then enableESPForPlayer(p) end end
		end
	end
end)
LocalPlayer.CharacterRemoving:Connect(function() charHumanoid = nil; destroyModeObjects(); clearRing() end)

-- MAIN LOOP
local startTick = tick()
RunService.RenderStepped:Connect(function(dt)
	if dt > 0.12 then dt = 0.12 end
	local now = tick()
	local t = now - startTick

	-- read sliders live
	local sVal = tonumber(sliderSpeed.GetValue() or ORBIT_SPEED) or ORBIT_SPEED
	local rVal = tonumber(sliderRadius.GetValue() or orbitRadius) or orbitRadius
	if mode == "smooth" then ORBIT_SPEED = sVal; orbitRadius = rVal else orbitRadius = rVal end
	local newSearch = tonumber(sliderSearch.GetValue() or SEARCH_RADIUS_DEFAULT) or SEARCH_RADIUS_DEFAULT
	local forcePower = tonumber(sliderForce.GetValue() or SLIDER_LIMITS.FORCE_POWER_DEFAULT) or SLIDER_LIMITS.FORCE_POWER_DEFAULT

	if chargeTimer > 0 then
		chargeTimer = math.max(0, chargeTimer - dt)
		if chargeTimer == 0 then cycleTarget() end
	end

	if not enabled then return end

	local myHRP = getHRP(LocalPlayer)
	if not myHRP then setTarget(nil, true); return end

	-- auto-find target when none
	if not currentTarget then
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer then
				local hrp = getHRP(p)
				if hrp then
					local d = (hrp.Position - myHRP.Position).Magnitude
					if d <= newSearch then table.insert(list, {player=p, dist=d}) end
				end
			end
		end
		table.sort(list, function(a,b) return a.dist < b.dist end)
		if #list > 0 then setTarget(list[1].player) end
	end

	local targetHRP = currentTarget and getHRP(currentTarget) or nil
	if not targetHRP then
		if attach0 or alignObj or bvObj or bgObj or lvObj or vfObj or vfAttach or fallbackForceBV then destroyModeObjects() end
		infoLabel.Text = "Nearest: — | Dist: — | Dir: " .. (orbitDirection==1 and "CW" or "CCW") .. " | R: " .. string.format("%.2f", orbitRadius)
		clearRing()
		return
	else
		local distToMe = (targetHRP.Position - myHRP.Position).Magnitude
		if distToMe > newSearch then setTarget(nil, true); return end
		infoLabel.Text = ("Nearest: %s | Dist: %.1f | Dir: %s | R: %.2f"):format(tostring(currentTarget.Name), distToMe, (orbitDirection==1 and "CW" or "CCW"), orbitRadius)
	end

	-- NoFall check (throttled): if enabled and no ground beneath target within threshold -> drop target
	if noFallEnabled and targetHRP then
		if now - lastNoFallCheck > 0.12 then
			lastNoFallCheck = now
			local ok, under = pcall(function()
				if currentTarget and currentTarget.Character then
					return raycastDown(targetHRP.Position + Vector3.new(0,1,0), noFallThreshold, currentTarget.Character)
				end
				return true
			end)
			if ok and (under == nil or under == false) then
				setTarget(nil, true)
				return
			end
		end
	end

	-- draw ring
	if currentTarget and selectedTargetMode == "RING" and #ringParts == 0 then createRingSegments(SEGMENTS) end
	if currentTarget and targetHRP and #ringParts > 0 then
		local levOffset = math.sin(t * 1.0) * 0.22 + (math.noise(t * 0.7, PlayerId * 0.01) - 0.5) * 0.06
		local basePos = targetHRP.Position + Vector3.new(0, RING_HEIGHT_BASE + levOffset, 0)
		local angleStep = (2 * math.pi) / #ringParts
		for i, part in ipairs(ringParts) do
			if not part or not part.Parent then if selectedTargetMode == "RING" then createRingSegments(SEGMENTS); end; break end
			local angle = (i - 1) * angleStep
			local radialPulse = math.sin(t * 1.35 + angle * 1.1) * 0.05
			local r = RING_RADIUS + radialPulse + (math.noise(i * 0.03, t * 0.6) - 0.5) * 0.03
			local bob =
				math.sin(t * 2.0 + angle * 0.8) * 0.28 +
				math.sin(t * 0.6 + angle * 0.45) * (0.28 * 0.25) +
				math.cos(t * 0.9 + angle * 0.3) * (0.28 * 0.08)
			local x = math.cos(angle) * r
			local z = math.sin(angle) * r
			local pos = basePos + Vector3.new(x, bob, z)
			local dirToCenter = (basePos - pos)
			if dirToCenter.Magnitude < 0.001 then dirToCenter = Vector3.new(0,0,1) end
			local lookAt = dirToCenter.Unit
			local up = Vector3.new(0,1,0)
			local right = up:Cross(lookAt)
			if right.Magnitude < 0.001 then right = Vector3.new(1,0,0) else right = right.Unit end
			local forward = lookAt
			local cframe = CFrame.fromMatrix(pos, right, up, -forward)
			cframe = cframe * CFrame.new(0, SEGMENT_HEIGHT/2, 0)
			part.CFrame = cframe
		end
	end

	-- orbit math & dynamics
	if burstTimer > 0 then
		burstTimer = math.max(0, burstTimer - dt)
		if burstTimer == 0 then burstStrength = 0 end
	else
		if math.random() < ORBIT_BURST_CHANCE_PER_SEC * dt then
			burstStrength = (math.random() < 0.5 and -1 or 1) * (ORBIT_BURST_MIN + math.random() * (ORBIT_BURST_MAX - ORBIT_BURST_MIN))
			burstTimer = 0.18 + math.random() * 0.26
		end
	end

	local noise = (math.noise(t * ORBIT_NOISE_FREQ, PlayerId * 0.01) - 0.5) * ORBIT_NOISE_AMP
	local drift = math.sin(t * DRIFT_FREQ + driftPhase) * DRIFT_AMP
	local effectiveBaseSpeed = ORBIT_SPEED * (1 + noise)
	if shiftHeld then effectiveBaseSpeed = effectiveBaseSpeed * 1.6 end

	local myDist = nil
	local radialError = 0
	if currentTarget and targetHRP then
		myDist = (myHRP.Position - targetHRP.Position).Magnitude
		radialError = myDist - orbitRadius
	end
	local speedBias = clamp(radialError * 0.45, -2.2, 2.2)

	local chargeEffect = 0
	if chargeTimer > 0 then chargeEffect = CHARGE_STRENGTH end
	local burstEffect = burstStrength * (burstTimer > 0 and 1 or 0)

	orbitAngle = orbitAngle + (orbitDirection * (effectiveBaseSpeed * (1 + chargeEffect*0.05) + speedBias + burstEffect) + steeringInput * 1.8) * dt

	local desiredRadius = orbitRadius + drift * 0.6
	if myDist and myDist < desiredRadius - 0.6 then desiredRadius = desiredRadius + (desiredRadius - myDist) * 0.35 end

	local ox = math.cos(orbitAngle) * desiredRadius
	local oz = math.sin(orbitAngle) * desiredRadius

	-- Validate currentTarget: if player died/disconnected or character missing, clear target immediately
	if currentTarget then
		local okHRP = getHRP(currentTarget)
		local okAlive = false
		if okHRP and okHRP.Parent then
			local hum = okHRP.Parent:FindFirstChildOfClass('Humanoid')
			okAlive = hum and hum.Health and hum.Health > 0
		end
		if (not okHRP) or (not okAlive) then
			setTarget(nil, true)
		end
	end

	local targetPos = targetHRP.Position + Vector3.new(ox, 1.2, oz)

	-- CheckWall: if enabled and direct line blocked, drop target immediately (used for Strafe to avoid attacking behind walls)
	if checkWallEnabled and fastCheckWall(myHRP, targetHRP) then
		setTarget(nil, true)
		return
	end

	-- LookAim: rotate camera toward target part (smooth) rotate camera toward target part (smooth)
	if lookAimEnabled and currentTarget and currentTarget.Character and Camera then
		local tgtPart = nil
		if lookAimTargetPart == "Head" then tgtPart = currentTarget.Character:FindFirstChild("Head") end
		if not tgtPart then tgtPart = currentTarget.Character:FindFirstChild("HumanoidRootPart") end
		if tgtPart then
			local desiredCFrame = CFrame.new(Camera.CFrame.Position, tgtPart.Position)
			Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, clamp(getLookAimStrength() * dt * 60, 0, 1))
		end
	end

	if myHRP then pcall(function() applyAimView(myHRP, targetHRP) end) end

	-- Apply modes — ensure they obey orbit radius by always using 'targetPos' computed above
	if mode == "smooth" then
		if not (alignObj and helperPart and attach0) then createSmoothObjectsFor(myHRP) end
		if alignObj and helperPart then
			local curPos = helperPart.Position
			local toTarget = (targetPos - curPos)
			local accel = toTarget * HELPER_SPRING - helperVel * HELPER_DAMP
			local aMag = accel.Magnitude
			if aMag > HELPER_MAX_ACCEL then accel = accel.Unit * HELPER_MAX_ACCEL end
			local candidateVel = helperVel + accel * dt
			if candidateVel.Magnitude > HELPER_MAX_SPEED then candidateVel = candidateVel.Unit * HELPER_MAX_SPEED end
			local interp = clamp(HELPER_SMOOTH_INTERP * dt, 0, 1)
			helperVel = Vector3.new(lerp(helperVel.X, candidateVel.X, interp), lerp(helperVel.Y, candidateVel.Y, interp), lerp(helperVel.Z, candidateVel.Z, interp))
			local newPos = curPos + helperVel * dt
			local maxStep = math.max(3, HELPER_MAX_SPEED * 0.2) * dt
			local toNew = newPos - curPos
			if toNew.Magnitude > maxStep then newPos = curPos + toNew.Unit * maxStep end
			if chargeTimer > 0 then
				local chargeDir = (targetPos - curPos)
				if chargeDir.Magnitude > 0.01 then
					local n = chargeDir.Unit * (math.max(10, HELPER_MAX_SPEED) * 0.7) * (chargeTimer/CHARGE_DURATION)
					newPos = newPos + n * dt
				end
			end
			helperPart.CFrame = CFrame.new(newPos)
			local playerMoving = false
			if charHumanoid then local mv = charHumanoid.MoveDirection if mv and mv.Magnitude > 0.12 then playerMoving = true end end
			local distToHelper = (myHRP.Position - helperPart.Position).Magnitude
			local extraForce = clamp(distToHelper * 1200, 0, ALIGN_MAX_FORCE)
			local desiredForce = clamp(2000 + extraForce, ALIGN_MIN_FORCE, ALIGN_MAX_FORCE)
			if playerMoving then alignObj.MaxForce = math.max(ALIGN_MIN_FORCE, desiredForce * 0.45) else alignObj.MaxForce = desiredForce end
			alignObj.Responsiveness = ALIGN_RESPONSIVENESS
		end

	elseif mode == "velocity" then
		if not (bvObj and bgObj) then createVelocityObjectsFor(myHRP) end
		if bvObj and bgObj then
			local power = tonumber(sliderSpeed.GetValue() or SLIDER_LIMITS.BV_POWER_DEFAULT) or SLIDER_LIMITS.BV_POWER_DEFAULT
			local dir = (targetPos - myHRP.Position)
			dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
			local dist = dir.Magnitude
			local speedTarget = ORBIT_SPEED * (power/SLIDER_LIMITS.BV_POWER_DEFAULT) * 4 * (chargeTimer>0 and (1+CHARGE_STRENGTH*0.15) or 1)
			local velTarget = Vector3.new(0,0,0)
			if dist > 0.01 then velTarget = dir.Unit * speedTarget end
			if dist < 1.0 then velTarget = velTarget * dist end
			pcall(function() bvObj.Velocity = velTarget end)
			local mf = clamp(power*200, 1000, ALIGN_MAX_FORCE)
			pcall(function() bvObj.MaxForce = Vector3.new(mf,mf,mf) end)
			local flat = Vector3.new(velTarget.X, 0, velTarget.Z)
			if flat.Magnitude > 0.01 then local desiredYaw = CFrame.new(myHRP.Position, myHRP.Position + flat); bgObj.CFrame = desiredYaw end
		end

	elseif mode == "twisted" then
		if not lvObj then createLinearObjectsFor(myHRP) end
		if lvObj then
			local power = tonumber(sliderSpeed.GetValue() or SLIDER_LIMITS.TWIST_DEFAULT) or SLIDER_LIMITS.TWIST_DEFAULT
			local dir = (targetPos - myHRP.Position)
			dir = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
			local dist = dir.Magnitude
			local base = (power / SLIDER_LIMITS.TWIST_DEFAULT) * (ORBIT_SPEED * 3.5) * (chargeTimer>0 and (1+CHARGE_STRENGTH*0.12) or 1)
			local vel = Vector3.new(0,0,0)
			if dist > 0.01 then vel = dir.Unit * base end
			if dist < 1.0 then vel = vel * dist end
			pcall(function() lvObj.VectorVelocity = vel end)
			pcall(function() lvObj.MaxForce = math.max(1e3, math.abs(power) * 500) end)
		end

	elseif mode == "force" then
		if not (vfObj or fallbackForceBV) then createForceObjectsFor(myHRP) end
		local dir = (targetPos - myHRP.Position)
		local desired = Vector3.new(dir.X, dir.Y * 0.6, dir.Z)
		local dist = desired.Magnitude
		local unit = Vector3.new(0,0,0)
		if dist > 0.01 then unit = desired.Unit end
		local appliedPower = forcePower * (chargeTimer>0 and (1 + CHARGE_STRENGTH*0.4) or 1)
		local forceVec = unit * appliedPower
		if vfObj then pcall(function() vfObj.Force = forceVec end)
		elseif fallbackForceBV then
			local speedTarget = clamp(ORBIT_SPEED * (appliedPower/SLIDER_LIMITS.FORCE_POWER_DEFAULT) * 6, 0, 120)
			local velTarget = unit * speedTarget
			if dist < 1 then velTarget = velTarget * dist end
			pcall(function() fallbackForceBV.Velocity = velTarget local mf = clamp(appliedPower * 50, 1000, ALIGN_MAX_FORCE) fallbackForceBV.MaxForce = Vector3.new(mf,mf,mf) end)
		end
		tryAutoJump()
	end
end)

-- cleanup on gui removal
screenGui.AncestryChanged:Connect(function(_, parent)
	if not parent then
		pcall(function() saveState() end)
		destroyModeObjects(); clearRing()
	end
end)

Players.PlayerRemoving:Connect(function(p)
	if p == LocalPlayer then pcall(function() saveState() end) end
	if p == currentTarget then setTarget(nil, true) end
end)



-- live-sync sliders into runtime variables so sliders *always* affect behavior
RunService.RenderStepped:Connect(function()
	pcall(function()
		if sliderRadius and sliderRadius.GetValue then
			local v = tonumber(sliderRadius.GetValue()) or orbitRadius
			if v and type(v)=='number' then orbitRadius = v end
		end
		if sliderSpeed and sliderSpeed.GetValue then
			local sv = tonumber(sliderSpeed.GetValue()) or ORBIT_SPEED
			if sv and type(sv)=='number' then ORBIT_SPEED = sv end
		end
	end)
end)

-- initial setup: load state, update UI and apply saved settings
loadState()
hotkeyBox.Text = "Hotkey: "..hotkeyStr
chargeHotkeyBox.Text = "Charge: "..chargeHotkeyStr
updateToggleUI()
applyModeUI()
updateESP(espEnabled)
updateAutoJumpUI()
saveState()


-- ===== Added Visuals / TargetVisuals / FOV UI & runtime (v5) =====
-- This block adds:
-- 1) Visuals button + VisualFrame holding PlayerESP and Target Visuals controls.
-- 2) Small TargetFrame with mutually-exclusive RING / Fire / Sneak / Star modes.
-- 3) RGB sliders (only Parts used) and color preview / label.
-- 4) Fov button + small Fov picker to change Camera.FieldOfView ("CameraZoom").
-- 5) Lightweight animated Part-only visuals for Fire / Sneak / Star; RING uses existing ringParts.
-- 6) Ensures sliders don't move frames while dragging by polling slider IsDragging().
-- Note: uses existing helpers createSlider, styleButton, styleTextBox, setFrameDraggableState, and screenGui/frame variables.

local _ok,_err = pcall(function()
	-- guard to avoid double-create if script hot-reloads
	if screenGui:FindFirstChild("Visuals_v5") then return end

	local visualsContainer = Instance.new("Folder", screenGui)
	visualsContainer.Name = "Visuals_v5"

	-- Visuals toggle button on MainFrame
	local visualsBtn = Instance.new("TextButton", frame)
	visualsBtn.Size = UDim2.new(0, 120, 0, 34)
	visualsBtn.Position = UDim2.new(0, 6, 0, 320)
	visualsBtn.Text = "Visuals"
	styleButton(visualsBtn)

	-- Main VisualFrame (opens at same position as MainFrame)
	local visualFrame = Instance.new("Frame", screenGui)
	visualFrame.Name = "VisualFrame_v5"
	visualFrame.Size = UDim2.new(0, 360, 0, 220)
	visualFrame.Position = frame.Position or UDim2.new(0.5, -180, 0.82, -210)
	visualFrame.Active = true
	visualFrame.Draggable = true
	visualFrame.Visible = false
	visualFrame.BackgroundColor3 = Color3.fromRGB(16,29,31)
	visualFrame.Parent = screenGui
	local vfCorner = Instance.new("UICorner", visualFrame); vfCorner.CornerRadius = UDim.new(0,8)
	local vfStroke = Instance.new("UIStroke", visualFrame); vfStroke.Thickness = 1.6; vfStroke.Color = Color3.fromRGB(160,0,213)

	-- PlayerESP moved into VisualFrame (create a new button that reuses existing logic)
	local v_espBtn = Instance.new("TextButton", visualFrame)
	v_espBtn.Size = UDim2.new(0.46, -8, 0, 34)
	v_espBtn.Position = UDim2.new(0, 8, 0, 8)
	v_espBtn.Text = "PlayerESP"
	styleButton(v_espBtn)

	local v_espGear = Instance.new("TextButton", visualFrame)
	v_espGear.Size = UDim2.new(0.12, -6, 0, 34)
	v_espGear.Position = UDim2.new(0.66, 6, 0, 8)
	v_espGear.Text = "..."
	styleButton(v_espGear)

	-- make VisualFrame's PlayerESP the main espBtn used by the rest of the script
	espBtn = v_espBtn
	espGearBtn = v_espGear
	espBtn.Visible = true


	-- Hook into existing updateESP logic by calling the same function if present
	v_espBtn.MouseButton1Click:Connect(function()
		updateESP(not espEnabled)
	end)
	v_espGear.MouseButton1Click:Connect(function()
		-- show existing espPickerFrame if present, otherwise toggle our copy
		if espPickerFrame then
			espPickerFrame.Visible = not espPickerFrame.Visible
		end
	end)

	-- Target visuals small frame (compact)
	local targetFrame = Instance.new("Frame", screenGui)
	targetFrame.Name = "TargetVisualPicker_v5"
	targetFrame.Size = UDim2.new(0, 220, 0, 170)
	targetFrame.Position = visualFrame.Position + UDim2.new(visualFrame.Size.X.Scale, visualFrame.Size.X.Offset, 0, 40)
	targetFrame.BackgroundColor3 = Color3.fromRGB(20,34,36)
	targetFrame.Active = true
	targetFrame.Draggable = true
	targetFrame.Visible = false
	local tfCorner = Instance.new("UICorner", targetFrame); tfCorner.CornerRadius = UDim.new(0,8)
	local tfStroke = Instance.new("UIStroke", targetFrame); tfStroke.Thickness = 1.2; tfStroke.Color = Color3.fromRGB(170,0,220)

	-- Title
	local ttitle = Instance.new("TextLabel", targetFrame)
	ttitle.Size = UDim2.new(1, -12, 0, 26)
	ttitle.Position = UDim2.new(0,6,0,6)
	ttitle.BackgroundTransparency = 1
	ttitle.Text = "Target Visual"
	ttitle.Font = Enum.Font.Arcade
	ttitle.TextScaled = true

	-- Mutually exclusive buttons: RING, Fire, Sneak, Star
	local tvModes = {"RING","Fire","Sneak","Star"}
	local modeButtons = {}
	local selectedTargetMode = "RING"
	local function setTargetMode(m)
		selectedTargetMode = m
		for k,btn in pairs(modeButtons) do
			if k == m then
				btn.BackgroundColor3 = Color3.fromRGB(100,40,120)
			else
				btn.BackgroundColor3 = Color3.fromRGB(51,38,53)
			end
		end
		-- save persistently
		writePersistValue("Strafe_targetVisualMode", selectedTargetMode)

		-- ensure ring state matches mode (create ring only for RING, clear otherwise)
		if currentTarget then
			if selectedTargetMode == "RING" then
				if #ringParts == 0 then createRingSegments(SEGMENTS) end
			else
				clearRing()
			end
		end
	end

	for i, name in ipairs(tvModes) do
		local b = Instance.new("TextButton", targetFrame)
		b.Size = UDim2.new(0.48, -8, 0, 28)
		b.Position = UDim2.new(((i-1)%2)*0.5, 6, math.floor((i-1)/2)*0.28, 36)
		b.Text = name
		styleButton(b)
		b.MouseButton1Click:Connect(function() setTargetMode(name) end)
		modeButtons[name] = b
	end

	-- RGB sliders (reuse createSlider). We will poll their IsDragging to prevent draggable frames movement.
	local t_r = createSlider(targetFrame, 84, "R", 1, 255, espColor.R, function(v) return tostring(math.floor(v)) end)
	t_r.Container.Position = UDim2.new(0,8,0,84); t_r.Container.Size = UDim2.new(1,-16,0,24)
	local t_g = createSlider(targetFrame, 116, "G", 1, 255, espColor.G, function(v) return tostring(math.floor(v)) end)
	t_g.Container.Position = UDim2.new(0,8,0,116); t_g.Container.Size = UDim2.new(1,-16,0,24)
	local t_b = createSlider(targetFrame, 148, "B", 1, 255, espColor.B, function(v) return tostring(math.floor(v)) end)
	t_b.Container.Position = UDim2.new(0,8,0,148); t_b.Container.Size = UDim2.new(1,-16,0,24)

	-- Color preview & text
	local tPreview = Instance.new("TextLabel", targetFrame)
	tPreview.Size = UDim2.new(0, 42, 0, 42)
	tPreview.Position = UDim2.new(1, -50, 0, 8)
	tPreview.BackgroundColor3 = Color3.fromRGB(espColor.R, espColor.G, espColor.B)
	tPreview.Text = ""
	tPreview.Parent = targetFrame
	local tLabel = Instance.new("TextLabel", targetFrame)
	tLabel.Size = UDim2.new(1, -60, 0, 20)
	tLabel.Position = UDim2.new(0,8,0,8)
	tLabel.BackgroundTransparency = 1
	tLabel.TextXAlignment = Enum.TextXAlignment.Right
	tLabel.Font = Enum.Font.Arcade
	tLabel.TextScaled = true
	tLabel.Text = string.format("Color: %d, %d, %d", espColor.R, espColor.G, espColor.B)

	-- Fov button + picker
	local fovBtn = Instance.new("TextButton", visualFrame)
	fovBtn.Size = UDim2.new(0, 76, 0, 28)
	fovBtn.Position = UDim2.new(0.66, 6, 0, 48)
	fovBtn.Text = "Fov"
	styleButton(fovBtn)

	local fovPicker = Instance.new("Frame", screenGui)
	fovPicker.Size = UDim2.new(0, 260, 0, 88)
	fovPicker.Position = visualFrame.Position + UDim2.new(0, 0, 0, visualFrame.Size.Y.Offset + 10)
	fovPicker.BackgroundColor3 = Color3.fromRGB(16,29,31)
	fovPicker.Visible = false
	fovPicker.Active = true
	fovPicker.Draggable = true
	local fpCorner = Instance.new("UICorner", fovPicker); fpCorner.CornerRadius = UDim.new(0,8)
	local fovSlider = createSlider(fovPicker, 8, "Camera FOV", 20, 120, Camera.FieldOfView or 70, function(v) return string.format("%.1f", v) end)

	-- Bind camera FOV to FOV picker slider (live)
	RunService:BindToRenderStep("Strafe_UpdateFOV", Enum.RenderPriority.Camera.Value - 1, function()
		local cam = workspace and workspace.CurrentCamera
		if not cam then return end
		if fovSlider and fovSlider.GetValue then
			local v = tonumber(fovSlider.GetValue()) or cam.FieldOfView
			if cam.FieldOfView ~= v then pcall(function() cam.FieldOfView = v end) end
		end
	end)

	local savedFOV = tonumber(readPersistValue('Strafe_sliderFOV', nil))
	if savedFOV and fovSlider and fovSlider.SetValue then
		pcall(function() fovSlider.SetValue(savedFOV) end)
		if workspace and workspace.CurrentCamera then pcall(function() workspace.CurrentCamera.FieldOfView = savedFOV end) end
	end

	-- persist FOV when the picker is removed from the UI
	if fovPicker then
		fovPicker.AncestryChanged:Connect(function(_, parent)
			if not parent then
				if fovSlider and fovSlider.GetValue then
					pcall(function() writePersistValue('Strafe_sliderFOV', tostring(tonumber(fovSlider.GetValue()) or workspace.CurrentCamera.FieldOfView)) end)
				end
			end
		end)
	end
	fovSlider.Container.Position = UDim2.new(0,6,0,8)
	fovSlider.Container.Size = UDim2.new(1,-12,0,36)

	fovBtn.MouseButton1Click:Connect(function()
		fovPicker.Visible = not fovPicker.Visible
		if fovPicker.Visible then fovSlider.SetValue(Camera.FieldOfView or 70) end
	end)

	-- VisualFrame toggle
	visualsBtn.MouseButton1Click:Connect(function()
		visualFrame.Visible = not visualFrame.Visible
		if visualFrame.Visible then
			-- align newly opened frames to main frame position (open in same place)
			pcall(function()
				visualFrame.Position = frame.Position
				targetFrame.Position = visualFrame.Position + UDim2.new(visualFrame.Size.X.Scale, visualFrame.Size.X.Offset, 0, 40)
				fovPicker.Position = visualFrame.Position + UDim2.new(0, 0, 0, visualFrame.Size.Y.Offset + 10)
			end)
		end
	end)

	targetFrame.Visible = false
	-- Add a small "TargetEsp" button inside visualFrame to toggle targetFrame
	local targetToggleBtn = Instance.new("TextButton", visualFrame)
	targetToggleBtn.Size = UDim2.new(0, 120, 0, 30)
	targetToggleBtn.Position = UDim2.new(0, 8, 0, 48)
	targetToggleBtn.Text = "TargetEsp"
	styleButton(targetToggleBtn)
	targetToggleBtn.MouseButton1Click:Connect(function() targetFrame.Visible = not targetFrame.Visible end)

	-- Runtime: create simple Part-only visuals for Fire / Sneak / Star. Use a workspace folder.
	local tvFolderName = "StrafeTargetVisuals_v5_"..tostring(PlayerId)
	local tvFolder = workspace:FindFirstChild(tvFolderName)
	if not tvFolder then
		tvFolder = Instance.new("Folder")
		tvFolder.Name = tvFolderName
		tvFolder.Parent = workspace
	end





	local fireParts, sneakParts, starParts = {}, {}, {}
	local tvExtraFolder = Instance.new("Folder", tvFolder)
	tvExtraFolder.Name = "Extras_Tweens_Strong"
	tvExtraFolder.Parent = tvFolder

	local function extrasParent()
		-- If a current target exists and has a Character, create (or reuse) a folder there so parts become visible under the target model in Workspace.
		if currentTarget and currentTarget.Character then
			local fld = currentTarget.Character:FindFirstChild("StrafeExtras")
			if not fld then
				fld = Instance.new("Folder")
				fld.Name = "StrafeExtras"
				fld.Parent = currentTarget.Character
			end
			return fld
		end
		-- fallback to the global extras folder
		return tvExtraFolder
	end


	local TweenService = game:GetService("TweenService")
	local RunService = game:GetService("RunService")

	local function safeDestroy(o)
		pcall(function() if o and o.Parent then o:Destroy() end end)
	end

	local function makePart(kind, size, color)
		local ok, p = pcall(function()
			local part
			if kind == "Wedge" then
				part = Instance.new("WedgePart")
			elseif kind == "CornerWedge" then
				part = Instance.new("CornerWedgePart")
			else
				part = Instance.new("Part")
			end
			part.Size = size or Vector3.new(0.2,0.2,0.2)
			part.Anchored = true
			part.CanCollide = false
			part.Material = Enum.Material.Neon
			part.CastShadow = false
			if color then p.Color = color end
			p.Parent = extrasParent()
			return part
		end)
		if ok then return p end
		return nil
	end

	local function clearExtras()
		pcall(function()
			for _,v in ipairs(tvExtraFolder:GetChildren()) do
				if v._pulse and v._pulse.PlaybackState == Enum.PlaybackState.Playing then
					pcall(function() v._pulse:Cancel() end)
				end
				safeDestroy(v)
			end
			fireParts, sneakParts, starParts = {}, {}, {}
		end)
	end

	-- Immediately hide ring (no tween) or restore it
	local function setRingHiddenImmediate(hidden)
		pcall(function()
			if ringParts and type(ringParts) == "table" then
				for _,seg in ipairs(ringParts) do
					if seg and seg.Parent and seg:IsA("BasePart") then
						seg.Transparency = (hidden and 1) or (RING_TRANSP or 0.22)
					end
				end
			end
		end)
	end

	-- Smoothly tween ring color
	local function tweenRingColor(color)
		pcall(function()
			if typeof(color) ~= "Color3" then return end
			if ringParts and type(ringParts) == "table" then
				for _,seg in ipairs(ringParts) do
					if seg and seg.Parent and seg:IsA("BasePart") then
						local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
						pcall(function() TweenService:Create(seg, info, {Color = color}):Play() end)
					end
				end
			end
		end)
	end

	-- Spawn parts but don't show them until activated


	local function spawnFire(count)
		count = count or 36
		if #fireParts > 0 then return end
		local kinds = {"Wedge", "Block", "Wedge", "CornerWedge"}
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		for i=1,count do
			local kind = kinds[((i-1) % #kinds) + 1]
			local s1 = 0.04 + math.random() * 0.18
			local s2 = 0.04 + math.random() * 0.42
			local p = makePart(kind, Vector3.new(s1, s2, math.max(s1, 0.06)))
			if p then
				p.Name = "FirePart"..i
				p.Transparency = 0.12
				p.CanCollide = false
				p.Anchored = false
				if root then
					p.CFrame = root.CFrame * CFrame.new(math.cos(i) * 1.2, 0.2 + math.sin(i)*0.3, math.sin(i)*1.2)
				end
				table.insert(fireParts, p)
			end
		end

		-- animate: spiral outward and flicker
		spawn(function()
			local age = 0
			while #fireParts > 0 do
				local dt = RunService.RenderStepped:Wait()
				age = age + dt
				for idx, part in ipairs(fireParts) do
					if part and part.Parent then
						local ang = age * (0.6 + idx*0.02)
						local r = 0.6 + math.sin(age*1.5 + idx)*0.6
						if root then
							local pos = root.Position + Vector3.new(math.cos(ang)*r, 0.4 + math.sin(age*2+idx)*0.12, math.sin(ang)*r)
							part.CFrame = CFrame.new(pos) * CFrame.fromEulerAnglesXYZ(math.sin(age+idx)*0.3, ang, 0)
						end
						-- flicker transparency with tween-like numeric change
						part.Transparency = 0.2 + math.abs(math.sin(age*3 + idx))*0.6
					end
				end
			end
		end)
	end





	local function spawnSneak(count)
		count = 30
		if #sneakParts > 0 then return end
		local char = LocalPlayer.Character
		if not char then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		local neckTarget = char:FindFirstChild("Head") and char.Head or hrp
		-- create balls
		for i=1,count do
			local p = makePart("Part", Vector3.new(0.18,0.18,0.18))
			if p then
				p.Shape = Enum.PartType.Ball
				p.Name = "SneakSeg"..i
				p.Transparency = 0.12
				p.CanCollide = false
				p.Anchored = false
				table.insert(sneakParts, p)
			end
		end
		-- two neon eyes (static on head of snake)
		local eyeL = makePart("Part", Vector3.new(0.18,0.18,0.06))
		local eyeR = makePart("Part", Vector3.new(0.18,0.18,0.06))
		if eyeL and eyeR then
			eyeL.Name = "SneakEyeL"; eyeR.Name = "SneakEyeR"
			eyeL.Transparency = 1; eyeR.Transparency = 1
			eyeL.Material = Enum.Material.Neon; eyeR.Material = Enum.Material.Neon
			eyeL.Color = Color3.fromRGB(255,10,10); eyeR.Color = Color3.fromRGB(255,10,10)
			eyeL.CanCollide = false; eyeR.CanCollide = false
			table.insert(sneakParts, eyeL); table.insert(sneakParts, eyeR)
		end

		-- animate the snake traveling from feet up to neck and wrap
		spawn(function()
			local t = 0
			while #sneakParts > 0 do
				local dt = RunService.RenderStepped:Wait()
				t = t + dt * 1.4
				local basePos = hrp and hrp.Position or Vector3.new(0,0,0)
				local targetPos = neckTarget and neckTarget.Position or basePos + Vector3.new(0,1.5,0)
				for idx, part in ipairs(sneakParts) do
					if part and part.Parent then
						local frac = idx / (#sneakParts + 1)
						-- interpolate along a curve from feet to neck
						local pos = basePos:Lerp(targetPos, frac) + Vector3.new(math.sin(t + idx)*0.18, math.cos(t*0.6 + idx)*0.08 - frac*0.4, math.cos(t + idx)*0.18)
						part.CFrame = CFrame.new(pos)
						part.Transparency = 0.2 + (1-frac)*0.6
					end
				end
				-- place eyes near head of snake (first two neon parts)
				if eyeL and eyeR and neckTarget then
					local dir = (neckTarget.CFrame * CFrame.new(0,0,-0.3)).p
					eyeL.CFrame = CFrame.new(neckTarget.Position + Vector3.new(-0.12, 0.0, -0.2))
					eyeR.CFrame = CFrame.new(neckTarget.Position + Vector3.new(0.12, 0.0, -0.2))
				end
			end
		end)
	end





	local function spawnStar(spikes)
		spikes = spikes or 18
		-- clear existing starParts if any (prevent invisible leftovers and ensure fresh spawn)
		if #starParts > 0 then
			for i = #starParts, 1, -1 do
				local sp = starParts[i]
				if sp and sp.Parent then
					pcall(function() sp:Destroy() end)
				end
				table.remove(starParts, i)
			end
		end
		local center = makePart("Block", Vector3.new(0.18,0.18,0.18))
		if center then
			center.Name = "StarCore"
			center.Transparency = 0.02
			center.Anchored = true
			table.insert(starParts, center)
		end

		for i=1,spikes do
			local p = makePart("Wedge", Vector3.new(0.06, 0.06, 0.5))
			if p then
				p.Name = "StarSpike_"..i
				p.Transparency = 0.12
				p.Anchored = false
				p.CanCollide = false
				-- mesh for richness
				pcall(function()
					local m = Instance.new("SpecialMesh", p)
					m.MeshType = Enum.MeshType.FileMesh
					m.MeshId = "rbxassetid://1361171250"
					local scale = 0.6 + math.random() * 1.6
					m.Scale = Vector3.new(0.06*scale, 0.06*scale, 0.6*scale)
				end)
				-- place around core
				if center then
					p.CFrame = center.CFrame * CFrame.Angles(0, (2*math.pi/spikes)*i, 0) * CFrame.new(0, 0, -1.2)
				end
				table.insert(starParts, p)
			end
		end

		-- Animated behavior: grow + rotate + pulse transparency
		spawn(function()
			local rotSpeed = 0.9 + math.random()*1.2
			local pulseT = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			local pulseGoal = {Transparency = 0.1}
			local tweens = {}
			for _, part in ipairs(starParts) do
				if part and part:IsA("BasePart") then
					local ok, tw = pcall(function() return TweenService:Create(part, pulseT, pulseGoal) end)
					if ok and tw then
						table.insert(tweens, tw)
						pcall(function() tw:Play() end)
					end
				end
			end
			while #starParts > 0 do
				local dt = RunService.RenderStepped:Wait()
				-- rotate around center
				if center and center.Parent then
					center.CFrame = center.CFrame * CFrame.Angles(0, rotSpeed * dt, 0)
					for i=2, #starParts do
						local part = starParts[i]
						if part and part.Parent then
							local rel = (CFrame.new(center.Position) * CFrame.Angles(0, (rotSpeed*0.7)*dt, 0))
							part.CFrame = part.CFrame * CFrame.Angles(0, rotSpeed*dt, 0)
						end
					end
				end
				-- slowly expand/contract by scaling mesh if present
				for _, part in ipairs(starParts) do
					if part and part:IsA("BasePart") then
						-- small physics jitter
						part.Velocity = part.Velocity * 0.95
					end
				end
			end
		end)
	end



	-- Ensure parts exist
	spawnFire(36); spawnSneak(28); spawnStar(18)

	-- State
	local activeMode = nil

	-- Strong visible animations using RenderStepped math + some Tween smoothing
	local fireT = 0; local sneakT = 0; local starT = 0

	RunService.RenderStepped:Connect(function(dt)
		pcall(function()
			-- update preview color
			local rr = math.floor(t_r.GetValue() or espColor.R)
			local gg = math.floor(t_g.GetValue() or espColor.G)
			local bb = math.floor(t_b.GetValue() or espColor.B)
			local userCol = Color3.fromRGB(rr,gg,bb)
			if targetFrame and targetFrame.Visible then
				tPreview.BackgroundColor3 = userCol
				tLabel.Text = string.format("Color: %d, %d, %d", rr, gg, bb)
			end

			-- immediately hide ring if not RING (prevent any flash)
			if selectedTargetMode ~= "RING" then
				setRingHiddenImmediate(true)
			else
				-- ensure ring visible and color updated
				setRingHiddenImmediate(false)
				tweenRingColor(userCol)
			end

			-- detect mode change
			if activeMode ~= selectedTargetMode then
				activeMode = selectedTargetMode
				-- on switch, hide all extras and then reveal only chosen
				for _,p in ipairs(fireParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(sneakParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(starParts) do if p and p.Parent then p.Transparency = 0.12 end end
				if activeMode == "Fire" then
					spawnFire(#fireParts == 0 and 20 or #fireParts)
				elseif activeMode == "Sneak" then
					spawnSneak(#sneakParts == 0 and 18 or #sneakParts)
				elseif activeMode == "Star" then
					spawnStar(#starParts == 0 and 10 or #starParts)
				end
			end

			-- advance ticks
			fireT = fireT + dt * 3.6
			sneakT = sneakT + dt * 2.2
			starT = starT + dt * 2.4

			-- If no target, ensure extras hidden and return
			if not (currentTarget and currentTarget.Character and currentTarget.Character:FindFirstChild("HumanoidRootPart")) then
				for _,p in ipairs(fireParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(sneakParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(starParts) do if p and p.Parent then p.Transparency = 0.12 end end
				return
			end

			local tHRP = currentTarget.Character:FindFirstChild("HumanoidRootPart")
			if not tHRP then return end

			-- FIRE: clear cone, rising fast and visible
			if activeMode == "Fire" then
				for i,p in ipairs(fireParts) do
					if not p or not p.Parent then p.Parent = extrasParent() end
					local frac = i / #fireParts
					local ang = frac * math.pi * 2 + fireT * (1 + frac*0.8)
					local radius = 0.3 + frac*1.8 + math.sin(fireT*3 + i)*0.08
					local height = 0.8 + frac*2.6 + math.abs(math.sin(fireT*5 + i))*0.22
					local pos = tHRP.Position + Vector3.new(math.cos(ang)*radius, height, math.sin(ang)*radius)
					p.CFrame = CFrame.new(pos) * CFrame.Angles(math.sin(fireT*2 + i)*0.6, ang + fireT*0.4, 0)
					-- gradient color heavily weighted to warm tones, mix with user color slightly
					local c1 = Color3.fromRGB(255,210,90); local c2 = Color3.fromRGB(255,110,30); local c3 = Color3.fromRGB(255,30,140)
					local col = (frac < 0.5) and (c1:Lerp(c2, frac/0.5)) or (c2:Lerp(c3, (frac-0.5)/0.5))
					col = col:Lerp(userCol, 0.12)
					p.Color = col
					p.Transparency = 0.03 + math.abs(math.sin(fireT*6 + i))*0.12
					local baseS = 0.06 + frac*0.6
					p.Size = Vector3.new(baseS*1.8, baseS*2.6, baseS*0.9)
				end

			elseif activeMode == "Sneak" then
				-- snake body: segments follow a helix path; eyes at head, pulsing
				local segCount = math.max(1, #sneakParts - 2)
				local base = tHRP.Position + Vector3.new(0,0.9,0)
				for i=1,segCount do
					local p = sneakParts[i]
					if not p or not p.Parent then p.Parent = extrasParent() end
					local frac = i/segCount
					local ang = frac * math.pi * 2 + sneakT * (1 + frac*0.4) + math.noise(i*0.08, sneakT*0.2)
					local rad = 0.5 + frac*1.1 + math.sin(sneakT*1.3 + i)*0.12
					local y = 0.4 + math.cos(frac*math.pi*2 + sneakT*0.9)*0.5 + frac*0.5
					local pos = base + Vector3.new(math.cos(ang)*rad, y, math.sin(ang)*rad)
					p.CFrame = CFrame.new(pos) * CFrame.Angles(0, ang + math.sin(sneakT + i)*0.4, 0)
					p.Color = userCol
					p.Transparency = 0.02 + frac*0.2
					local sizev = 0.14 + (1-frac)*0.22
					p.Size = Vector3.new(sizev, sizev, sizev)
				end
				-- eyes
				local eyeL = sneakParts[#sneakParts-1]; local eyeR = sneakParts[#sneakParts]
				if eyeL and eyeR then
					local headAng = sneakT * 1.9
					local headPos = base + Vector3.new(math.cos(headAng)*0.95, 1.05 + math.sin(sneakT*1.6)*0.12, math.sin(headAng)*0.95)
					eyeL.CFrame = CFrame.new(headPos + Vector3.new(-0.18, 0, 0)) * CFrame.Angles(0, headAng, 0)
					eyeR.CFrame = CFrame.new(headPos + Vector3.new(0.18, 0, 0)) * CFrame.Angles(0, headAng, 0)
					eyeL.Color = Color3.fromRGB(255,10,10); eyeR.Color = Color3.fromRGB(255,10,10)
					eyeL.Transparency = 0.0; eyeR.Transparency = 0.0
				end

			elseif activeMode == "Star" then
				local cx = tHRP.Position + Vector3.new(0,1.4,0)
				local spikes = 0
				for i,p in ipairs(starParts) do
					if not p or not p.Parent then p.Parent = extrasParent() end
					if p.Name == "StarCore" then
						p.CFrame = CFrame.new(cx)
						p.Color = userCol
						p.Transparency = 0.02 + math.abs(math.sin(starT*2))*0.04
						p.Size = Vector3.new(0.18,0.18,0.18)
					else
						spikes = spikes + 1
						local ang = (spikes / (#starParts-1)) * math.pi * 2 + starT * 1.6
						local rad = 0.6 + math.sin(starT*2 + spikes)*0.18
						local pos = cx + Vector3.new(math.cos(ang)*rad, math.sin(starT*1.6 + spikes)*0.12, math.sin(ang)*rad)
						p.CFrame = CFrame.new(pos) * CFrame.Angles(math.pi/2, ang + starT*0.9, 0)
						p.Color = userCol
						p.Transparency = 0.02 + math.abs(math.cos(starT + spikes))*0.06
						p.Size = Vector3.new(0.04, 0.04, 1.2)
						-- ensure spike has subtle tween for length variance
						if not p._tween or p._tween.PlaybackState ~= Enum.PlaybackState.Playing then
							local info = TweenInfo.new(0.9 + (spikes/#starParts)*0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true)
							p._tween = TweenService:Create(p, info, {Size = Vector3.new(0.04,0.04,1.35)}); p._tween:Play()
						end
					end
				end
			else
				-- unknown mode: hide all extras and keep ring off if not RING
				for _,p in ipairs(fireParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(sneakParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(starParts) do if p and p.Parent then p.Transparency = 0.12 end end
			end
		end)
	end)
	-- load saved target visual mode
	local savedMode = readPersistValue("Strafe_targetVisualMode", nil)
	if savedMode and type(savedMode) == "string" then setTargetMode(savedMode) else setTargetMode("RING") end

	-- ensure preview sliders start with existing espColor values
	t_r.SetValue(espColor.R); t_g.SetValue(espColor.G); t_b.SetValue(espColor.B)
end)
if not _ok then warn('Visuals v5 failed to load: '..tostring(_err)) end
-- ===== End added block =====



-- ===== PATCHED: Improved Target Visuals with Physics & Strict Show Conditions =====
do
	-- ensure workspace folder exists (idempotent)
	local tvFolderName = "StrafeTargetVisuals_v5_"..tostring(PlayerId)
	local tvFolder = workspace:FindFirstChild(tvFolderName)
	if not tvFolder then
		tvFolder = Instance.new("Folder")
		tvFolder.Name = tvFolderName
		tvFolder.Parent = workspace
	end

	local tvExtraFolder = tvFolder:FindFirstChild("Extras_Tweens_Strong")
	if not tvExtraFolder then
		tvExtraFolder = Instance.new("Folder")
		tvExtraFolder.Name = "Extras_Tweens_Strong"
		tvExtraFolder.Parent = tvFolder
	end

	-- physical part factory (tries VectorForce then BodyVelocity fallback)
	local function makePhysPart(kind, size, color)
		local ok, part = pcall(function()
			local p
			if kind == "Wedge" then
				p = Instance.new("WedgePart")
			elseif kind == "CornerWedge" then
				p = Instance.new("CornerWedgePart")
			else
				p = Instance.new("Part")
			end
			p.Size = size or Vector3.new(0.2,0.2,0.2)
			p.Anchored = false
			p.CanCollide = false
			p.Material = Enum.Material.Neon
			p.CastShadow = false
			if color then p.Color = color end
			p.Parent = extrasParent()
			return p
		end)
		if not ok then return nil end

		-- add an Attachment for VectorForce (safe if not supported)
		local att = Instance.new("Attachment")
		att.Name = "VF_Attach"
		att.Parent = part

		local created = false
		pcall(function()
			local vf = Instance.new("VectorForce")
			vf.Name = "VF_"..tostring(math.random(0,999999))
			vf.Attachment0 = att
			vf.Force = Vector3.new((math.random()-0.5)*40, 60 + math.random()*120, (math.random()-0.5)*40)
			vf.Parent = part
			created = true
		end)
		if not created then
			pcall(function()
				local bv = Instance.new("BodyVelocity")
				bv.Name = "BV_"..tostring(math.random(0,999999))
				bv.MaxForce = Vector3.new(1e5,1e5,1e5)
				bv.P = 3000
				bv.Velocity = Vector3.new((math.random()-0.5)*6, 1 + math.random()*6, (math.random()-0.5)*6)
				bv.Parent = part
			end)
		end
		return part
	end

	-- precise spawners
	function spawnFire(count)
		count = tonumber(count) or 24
		-- clear old
		for i=#fireParts,1,-1 do local p=fireParts[i]; if p and p.Parent then p:Destroy() end; table.remove(fireParts,i) end
		for i=1,count do
			local baseS = 0.06 + math.random()*0.6
			local kind = ({ "Part", "Wedge", "CornerWedge" })[math.random(1,3)]
			local p = makePhysPart(kind, Vector3.new(baseS*1.8, baseS*2.6, baseS*0.9), Color3.fromRGB(255, 140 + math.random(-20,60), 60 + math.random(-20,80)))
			if p then
				p.Name = "FirePart"
				p.Parent = extrasParent()
				table.insert(fireParts, p)
			end
		end
	end

	function spawnSneak(_)
		-- MUST be exactly 30 balls; last two are eyes (neon red) and never change color
		local targetCount = 30
		for i=#sneakParts,1,-1 do local p=sneakParts[i]; if p and p.Parent then p:Destroy() end; table.remove(sneakParts,i) end
		for i=1,targetCount do
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.new(0.14, 0.14, 0.14)
			p.Anchored = false
			p.CanCollide = false
			p.Material = Enum.Material.Neon
			p.CastShadow = false
			p.Parent = extrasParent()
			if i > targetCount - 2 then
				-- eyes: fixed neon red, do not lerp/change color
				p.Color = Color3.fromRGB(255,10,10)
				p.Name = "SnakeEye"
			else
				p.Color = Color3.fromRGB(espColor.R or 255, espColor.G or 0, espColor.B or 170)
				p.Name = "SnakeSeg"
			end
			-- lightweight physics: small BodyVelocity to keep lively
			pcall(function()
				local bv = Instance.new("BodyVelocity")
				bv.MaxForce = Vector3.new(8e4, 8e4, 8e4)
				bv.P = 1000
				bv.Velocity = Vector3.new((math.random()-0.5)*0.4, 0, (math.random()-0.5)*0.4)
				bv.Parent = p
			end)
			table.insert(sneakParts, p)
		end
	end

	function spawnStar(count)
		count = tonumber(count) or 12
		for i=#starParts,1,-1 do local p=starParts[i]; if p and p.Parent then p:Destroy() end; table.remove(starParts,i) end
		-- central core
		local core = makePhysPart("Part", Vector3.new(0.18,0.18,0.18), Color3.fromRGB(espColor.R or 255, espColor.G or 0, espColor.B or 170))
		if core then core.Name = "StarCore"; table.insert(starParts, core) end
		local spikes = count - 1
		for i=1,spikes do
			local p = makePhysPart("Part", Vector3.new(0.04, 0.04, 1.0), Color3.fromRGB(espColor.R or 255, espColor.G or 0, espColor.B or 170))
			if p then
				-- attach decorative file mesh where available but don't error out
				pcall(function()
					local m = Instance.new("SpecialMesh", p)
					m.MeshType = Enum.MeshType.FileMesh
					m.MeshId = "rbxassetid://1361171250"
					local scale = 0.6 + math.random() * 1.6
					m.Scale = Vector3.new(0.06*scale, 0.06*scale, 0.6*scale)
				end)
				p.Name = "StarSpike"
				table.insert(starParts, p)
			end
		end
	end

	-- Replace visuals update loop with a stricter, physics-enabled loop.
	-- Uses RenderStepped binding (idempotent via name).
	local BIND_NAME = "StrafeTargetVisuals_v5_Update"
	-- unbind previous if present
	pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)

	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		pcall(function()
			-- Only show effects when:
			-- 1) Strafe is enabled (enabled)
			-- 2) currentTarget exists and is alive
			-- 3) VisualFrame is visible (if present)
			-- 4) CheckWall does NOT indicate a blocking wall (i.e., target visible) OR checkWall disabled
			if not enabled then
				-- hide parts quickly (no destruction to avoid garbage churn)
				for _,p in ipairs(fireParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(sneakParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(starParts) do if p and p.Parent then p.Transparency = 0.12 end end
				return
			end
			if not (currentTarget and currentTarget.Character) then
				return
			end
			local tHRP = currentTarget.Character:FindFirstChild("HumanoidRootPart")
			local hum = currentTarget.Character:FindFirstChildOfClass("Humanoid")
			if not tHRP or not hum or hum.Health <= 0 then
				return
			end
			local myHRP = getHRP(LocalPlayer)
			if not myHRP then return end
			local visualOpen = true
			if visualFrame ~= nil then visualOpen = visualFrame.Visible end
			local blocked = (checkWallEnabled and fastCheckWall(myHRP, tHRP))
			if not visualOpen or blocked then
				-- hide parts
				for _,p in ipairs(fireParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(sneakParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(starParts) do if p and p.Parent then p.Transparency = 0.12 end end
				return
			end

			-- compute user color (read sliders when available)
			local rr = espColor.R; local gg = espColor.G; local bb = espColor.B
			if type(t_r) == "table" and t_r.GetValue then rr = math.floor(t_r.GetValue()) end
			if type(t_g) == "table" and t_g.GetValue then gg = math.floor(t_g.GetValue()) end
			if type(t_b) == "table" and t_b.GetValue then bb = math.floor(t_b.GetValue()) end
			local userCol = Color3.fromRGB(rr, gg, bb)

			-- immediate ring color change (no tween) to avoid flashing issues
			if selectedTargetMode == "RING" and ringParts then
				for _,seg in ipairs(ringParts) do
					if seg and seg.Parent and seg:IsA("BasePart") then
						seg.Color = userCol
						seg.Transparency = RING_TRANSP or 0.22
					end
				end
			end

			-- advance tick counters (keep in sync)
			fireT = (fireT or 0) + dt * 3.6
			sneakT = (sneakT or 0) + dt * 2.2
			starT = (starT or 0) + dt * 2.4

			-- FIRE
			if selectedTargetMode == "Fire" then
				if #fireParts < 8 then spawnFire(36) end
				for i,p in ipairs(fireParts) do
					if p and p.Parent then
						local frac = i / (#fireParts + 1)
						local ang = frac * math.pi * 2 + fireT * (1 + frac*0.6)
						local radius = 0.3 + frac*1.8 + math.sin(fireT*3 + i)*0.06
						local height = 0.8 + frac*2.6 + math.abs(math.sin(fireT*5 + i))*0.22
						local pos = tHRP.Position + Vector3.new(math.cos(ang)*radius, height, math.sin(ang)*radius)
						p.CFrame = CFrame.new(pos) * CFrame.Angles(math.sin(fireT*2 + i)*0.6, ang + fireT*0.4, 0)
						p.Color = userCol:Lerp(Color3.fromRGB(255,110,30), 0.18)
						p.Transparency = 0.03 + math.abs(math.sin(fireT*6 + i))*0.12
						-- lively physics nudge
						p:ApplyImpulse(Vector3.new((math.random()-0.5)*2, 0.4 + math.random()*1.2, (math.random()-0.5)*2))
					end
				end

				-- SNEAK
			elseif selectedTargetMode == "Sneak" then
				if #sneakParts ~= 30 then spawnSneak(30) end
				local head = currentTarget.Character:FindFirstChild("Head")
				local baseFeet = tHRP.Position + Vector3.new(0,-1.0,0)
				local top = head and head.Position or (tHRP.Position + Vector3.new(0,1.4,0))
				local segCount = math.max(1, #sneakParts - 2)
				for i=1,segCount do
					local p = sneakParts[i]
					if p and p.Parent then
						local frac = i / segCount
						local pos = baseFeet:Lerp(top, frac) + Vector3.new(math.sin(sneakT*1.2 + i)*0.28, math.cos(frac*math.pi*2 + sneakT*0.6)*0.18, math.cos(sneakT*1.1 + i)*0.28)
						p.CFrame = CFrame.new(pos)
						p.Color = userCol
						p.Transparency = 0.02 + frac*0.2
						-- gentle impulses to keep parts lively
						p:ApplyImpulse(Vector3.new((math.random()-0.5)*0.2, (math.random()-0.5)*0.2, (math.random()-0.5)*0.2))
					end
				end
				-- eyes (last two) static neon red
				local eyeL = sneakParts[#sneakParts-1]; local eyeR = sneakParts[#sneakParts]
				if eyeL and eyeR then
					local headPos = top + Vector3.new(0,0.18,0)
					eyeL.CFrame = CFrame.new(headPos + Vector3.new(-0.18, 0, 0))
					eyeR.CFrame = CFrame.new(headPos + Vector3.new(0.18, 0, 0))
					eyeL.Color = Color3.fromRGB(255,10,10); eyeR.Color = Color3.fromRGB(255,10,10)
					eyeL.Transparency = 0; eyeR.Transparency = 0
				end

				-- STAR
			elseif selectedTargetMode == "Star" then
				if #starParts < 6 then spawnStar(18) end
				local cx = tHRP.Position + Vector3.new(0,1.4,0)
				local spikes = 0
				for i,p in ipairs(starParts) do
					if p and p.Parent then
						if p.Name == "StarCore" then
							p.CFrame = CFrame.new(cx)
							p.Color = userCol
							p.Transparency = 0.02 + math.abs(math.sin(starT*2))*0.04
						else
							spikes = spikes + 1
							local ang = (spikes / (#starParts-1)) * math.pi * 2 + starT * 1.6
							local rad = 0.6 + math.sin(starT*2 + spikes)*0.18
							local pos = cx + Vector3.new(math.cos(ang)*rad, math.sin(starT*1.6 + spikes)*0.12, math.sin(ang)*rad)
							p.CFrame = CFrame.new(pos) * CFrame.Angles(math.pi/2, ang + starT*0.9, 0)
							p.Color = userCol
							p.Transparency = 0.02 + math.abs(math.cos(starT + spikes))*0.06
							-- subtle impulse
							p:ApplyImpulse(Vector3.new((math.random()-0.5)*0.08, (math.random()-0.5)*0.08, (math.random()-0.5)*0.08))
						end
					end
				end
			else
				-- if RING or unknown: ensure extras are hidden
				for _,p in ipairs(fireParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(sneakParts) do if p and p.Parent then p.Transparency = 0.12 end end
				for _,p in ipairs(starParts) do if p and p.Parent then p.Transparency = 0.12 end end
			end
		end)
	end)
end
-- ===== End PATCH =====




-- ===== EMERGENCY OVERRIDE: Force-create visuals in Workspace and ensure ring cleanup =====
do
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local folderName = "Strafe_ForcedVisuals_v2_"..tostring(LocalPlayer and LocalPlayer.UserId or math.random(1,999999))
	local rootFolder = workspace:FindFirstChild(folderName)
	if rootFolder then
		pcall(function() rootFolder:Destroy() end)
	end
	rootFolder = Instance.new("Folder")
	rootFolder.Name = folderName
	rootFolder.Parent = workspace

	local ringContainer = Instance.new("Folder"); ringContainer.Name = "RingParts"; ringContainer.Parent = rootFolder
	local fireContainer = Instance.new("Folder"); fireContainer.Name = "FireParts"; fireContainer.Parent = rootFolder
	local sneakContainer = Instance.new("Folder"); sneakContainer.Name = "SneakParts"; sneakContainer.Parent = rootFolder
	local starContainer = Instance.new("Folder"); starContainer.Name = "StarParts"; starContainer.Parent = rootFolder

	-- small helper creators
	local function makePart(kind, size, color, parent)
		local p
		if kind == "Wedge" then p = Instance.new("WedgePart") 
		elseif kind == "CornerWedge" then p = Instance.new("CornerWedgePart")
		else p = Instance.new("Part") end
		p.Size = size or Vector3.new(0.2,0.2,0.2)
		p.Anchored = false
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = color or Color3.fromRGB(255,0,170)
		p.Transparency = 0
		p.Parent = parent
		return p
	end

	local function clearFolderContents(folder)
		for i = #folder:GetChildren(), 1, -1 do
			local c = folder:GetChildren()[i]
			pcall(function() c:Destroy() end)
		end
	end

	local function ensureRing(hrp, color)
		if not hrp then return end
		color = color or Color3.fromRGB(255,0,170)
		if #ringContainer:GetChildren() > 0 then
			-- update positions/colors
			for i,seg in ipairs(ringContainer:GetChildren()) do
				if seg and seg:IsA("BasePart") then
					local ang = (i / 18) * math.pi * 2
					local offset = Vector3.new(math.cos(ang)*1.2, -0.8, math.sin(ang)*1.2)
					seg.CFrame = CFrame.new(hrp.Position + offset)
					seg.Color = color
					seg.Transparency = 0
				end
			end
			return
		end
		-- create new ring
		for i = 1, 18 do
			local seg = makePart("Part", Vector3.new(0.12,0.05,0.6), color, ringContainer)
			seg.Name = "RingSeg_"..i
			seg.CFrame = CFrame.new(hrp.Position + Vector3.new(math.cos((i/18)*math.pi*2)*1.2, -0.8, math.sin((i/18)*math.pi*2)*1.2))
			seg.Transparency = 0
		end
	end

	local function ensureFire(hrp, color)
		if not hrp then return end
		color = color or Color3.fromRGB(255,80,40)
		if #fireContainer:GetChildren() == 0 then
			for i=1,24 do
				local kinds = {"Part","Wedge","CornerWedge"}
				local kind = kinds[(i%3)+1]
				local s = 0.06 + math.random()*0.4
				local p = makePart(kind, Vector3.new(s*1.6, s*2.0, s), color, fireContainer)
				p.Name = "Fire_"..i
				p.CFrame = CFrame.new(hrp.Position + Vector3.new((math.random()-0.5)*1.5, 0.6 + math.random()*1.8, (math.random()-0.5)*1.5))
			end
		end
		-- always update positions to orbit a bit
		for i,p in ipairs(fireContainer:GetChildren()) do
			if p and p:IsA("BasePart") and hrp then
				local ang = tick() * 2 + i
				local rad = 0.4 + (i/#fireContainer:GetChildren()) * 1.2
				p.CFrame = CFrame.new(hrp.Position + Vector3.new(math.cos(ang)*rad, 0.8 + math.sin(ang)*0.6, math.sin(ang)*rad))
				p.Transparency = 0
			end
		end
	end

	local function ensureSneak(char, color)
		if not char then return end
		color = color or Color3.fromRGB(255,0,170)
		if #sneakContainer:GetChildren() == 0 then
			for i=1,30 do
				local p = makePart("Part", Vector3.new(0.14,0.14,0.14), (i>28 and Color3.fromRGB(255,10,10) or color), sneakContainer)
				p.Shape = Enum.PartType.Ball
				p.Name = "Sneak_"..i
			end
		end
		local head = char:FindFirstChild("Head")
		local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
		local feet = hrp and (hrp.Position + Vector3.new(0,-1,0)) or (char:GetModelCFrame().p + Vector3.new(0,-1,0))
		local top = head and head.Position or (hrp and hrp.Position + Vector3.new(0,1.4,0))
		local segCount = 28
		for i=1,segCount do
			local p = sneakContainer:GetChildren()[i]
			if p then
				local frac = i/segCount
				p.CFrame = CFrame.new(feet:Lerp(top, frac) + Vector3.new(math.sin(tick()*1.2 + i)*0.28, math.cos(frac*math.pi*2 + tick()*0.6)*0.18, math.cos(tick()*1.1 + i)*0.28))
				p.Transparency = 0
			end
		end
		-- eyes
		local eyeL = sneakContainer:GetChildren()[29]; local eyeR = sneakContainer:GetChildren()[30]
		if eyeL and eyeR and top then
			eyeL.CFrame = CFrame.new(top + Vector3.new(-0.18, 0.18, 0))
			eyeR.CFrame = CFrame.new(top + Vector3.new(0.18, 0.18, 0))
			eyeL.Transparency = 0; eyeR.Transparency = 0
		end
	end

	local function ensureStar(hrp, color)
		if not hrp then return end
		color = color or Color3.fromRGB(255,0,170)
		if #starContainer:GetChildren() == 0 then
			local core = makePart("Part", Vector3.new(0.16,0.16,0.16), color, starContainer)
			core.Name = "StarCore"
			for i=1,12 do
				local p = makePart("Part", Vector3.new(0.06,0.06,1.0), color, starContainer)
				local mesh = Instance.new("SpecialMesh", p)
				mesh.MeshType = Enum.MeshType.FileMesh
				mesh.MeshId = "rbxassetid://1361171250"
				mesh.Scale = Vector3.new(0.06 + math.random()*0.9, 0.06 + math.random()*0.9, 0.4 + math.random()*0.9)
				p.Name = "StarSpike_"..i
			end
		end
		local cx = hrp.Position + Vector3.new(0,1.4,0)
		for i,p in ipairs(starContainer:GetChildren()) do
			if p.Name == "StarCore" then
				p.CFrame = CFrame.new(cx)
				p.Transparency = 0
			else
				local idx = tonumber(p.Name:match("_(%d+)$") or "1")
				local ang = (idx / math.max(1, (#starContainer:GetChildren()-1))) * math.pi * 2 + tick() * 1.6
				local rad = 0.6 + math.sin(tick()*2 + idx)*0.18
				p.CFrame = CFrame.new(cx + Vector3.new(math.cos(ang)*rad, math.sin(tick()*1.6 + idx)*0.12, math.sin(ang)*rad)) * CFrame.Angles(math.pi/2, ang + tick()*0.9, 0)
				p.Transparency = 0
			end
		end
	end

	-- helper to destroy ring parts immediately
	local function clearRingImmediate()
		clearFolderContents(ringContainer)
	end

	-- Main enforcement loop; runs every RenderStepped but is lightweight
	local enforced = true
	local function enforce(dt)
		pcall(function()
			-- read likely globals from main script
			local enabled = false
			if _G and _G.enabled ~= nil then enabled = _G.enabled end
			if not enabled then
				clearFolderContents(fireContainer); clearFolderContents(sneakContainer); clearFolderContents(starContainer); clearFolderContents(ringContainer)
				return
			end
			local selMode = (_G and _G.selectedTargetMode) or (selectedTargetMode) or "RING"
			local tgt = (_G and _G.currentTarget) or (currentTarget)
			local visualFrameVisible = true
			if _G and _G.visualFrame ~= nil then
				local vf = _G.visualFrame
				if type(vf) == "table" and vf.Visible ~= nil then visualFrameVisible = vf.Visible
				elseif typeof(vf) == "Instance" and (vf:IsA("Frame") or vf:IsA("ScreenGui")) then visualFrameVisible = vf.Visible end
			end
			if not visualFrameVisible then
				clearFolderContents(fireContainer); clearFolderContents(sneakContainer); clearFolderContents(starContainer); clearFolderContents(ringContainer)
				return
			end
			if not tgt or not tgt.Character then
				clearFolderContents(fireContainer); clearFolderContents(sneakContainer); clearFolderContents(starContainer)
				-- if not RING mode, ensure ring removed
				if selMode ~= "RING" then clearRingImmediate() end
				return
			end
			local char = tgt.Character
			local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
			if not hrp then return end

			-- ensure only the selected mode is visible
			if selMode == "RING" then
				ensureRing(hrp, (_G and _G.espColor) or Color3.fromRGB(255,0,170))
				clearFolderContents(fireContainer); clearFolderContents(sneakContainer); clearFolderContents(starContainer)
			elseif selMode == "Fire" then
				ensureFire(hrp, (_G and _G.espColor) or Color3.fromRGB(255,80,40))
				clearRingImmediate(); clearFolderContents(sneakContainer); clearFolderContents(starContainer)
			elseif selMode == "Sneak" or selMode == "Snake" then
				ensureSneak(char, (_G and _G.espColor) or Color3.fromRGB(255,0,170))
				clearRingImmediate(); clearFolderContents(fireContainer); clearFolderContents(starContainer)
			elseif selMode == "Star" then
				ensureStar(hrp, (_G and _G.espColor) or Color3.fromRGB(255,0,170))
				clearRingImmediate(); clearFolderContents(fireContainer); clearFolderContents(sneakContainer)
			else
				-- unknown mode: clear everything
				clearFolderContents(fireContainer); clearFolderContents(sneakContainer); clearFolderContents(starContainer); clearRingImmediate()
			end
		end)
	end

	-- Bind and ensure only one binder exists
	pcall(function() RunService:UnbindFromRenderStep("Strafe_ForceVisuals") end)
	RunService:BindToRenderStep("Strafe_ForceVisuals", Enum.RenderPriority.Character.Value + 1, function(dt) enforce(dt) end)
end
