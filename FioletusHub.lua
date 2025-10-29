-- Fioletus_MAIN_FINAL.txt (reconstructed UI)
-- Lightweight main LocalScript: builds UI and proxies actions to external logic modules loaded via HttpGet.
local URL_LOGIC1 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua"
local URL_LOGIC2 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua"

local Logic1 = nil
local Logic2 = nil

local function safeLoadRemote(url)
    local ok, res = pcall(function()
        local s = game:HttpGet(url)
        if s and #s > 8 then
            local f = loadstring(s)
            if f then
                local ok2, ret = pcall(f)
                if ok2 and type(ret) == 'table' then return ret end
            end
        end
    end)
    return ok and res or nil
end

-- Try to load modules asynchronously (pcall protected)
spawn(function()
    pcall(function() Logic1 = safeLoadRemote(URL_LOGIC1); _G.FioletusLogic1 = Logic1 or {} end)
    pcall(function() Logic2 = safeLoadRemote(URL_LOGIC2); _G.FioletusLogic2 = Logic2 or {} end)
end)

-- Basic services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0

-- UI parameters (kept visually similar to original)
local UI_POS = UDim2.new(0.5, -310, 0.82, -210)
local FRAME_SIZE = UDim2.new(0, 620, 0, 460)

-- Utility styling helpers
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

-- Create main ScreenGui and frame
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FioletusHub_UI_"..tostring(PlayerId)
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

local frameCorner = Instance.new("UICorner", frame); frameCorner.CornerRadius = UDim.new(0,10)
local frameStroke = Instance.new("UIStroke", frame); frameStroke.Thickness = 2; frameStroke.Color = Color3.fromRGB(212,61,146)

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, -12, 0, 42)
title.Position = UDim2.new(0, 6, 0, 6)
title.BackgroundTransparency = 1
title.Text = "FioletusHub"
title.Font = Enum.Font.Arcade
title.TextSize = 32
title.TextColor3 = Color3.fromRGB(212,61,146)
title.TextStrokeTransparency = 0.7

-- Minimal UI elements (toggle, change target, hotkeys)
local toggleBtn = Instance.new("TextButton", frame)
toggleBtn.Size = UDim2.new(0.20, -6, 0, 44)
toggleBtn.Position = UDim2.new(0, 6, 0, 66)
toggleBtn.Text = "OFF"
styleButton(toggleBtn)

local changeTargetBtn = Instance.new("TextButton", frame)
changeTargetBtn.Size = UDim2.new(0.28, -6, 0, 44)
changeTargetBtn.Position = UDim2.new(0.22, 6, 0, 66)
changeTargetBtn.Text = "Change Target"
styleButton(changeTargetBtn)

local hotkeyBox = Instance.new("TextBox", frame)
hotkeyBox.Size = UDim2.new(0.24, -6, 0, 44)
hotkeyBox.Position = UDim2.new(0.52, 6, 0, 66)
hotkeyBox.Text = "Hotkey: F"
styleTextBox(hotkeyBox)

local chargeHotkeyBox = Instance.new("TextBox", frame)
chargeHotkeyBox.Size = UDim2.new(0.24, -6, 0, 44)
chargeHotkeyBox.Position = UDim2.new(0.76, 6, 0, 66)
chargeHotkeyBox.Text = "Charge: G"
styleTextBox(chargeHotkeyBox)

-- Info label
local infoLabel = Instance.new("TextLabel", frame)
infoLabel.Size = UDim2.new(1, -12, 0, 24)
infoLabel.Position = UDim2.new(0, 6, 0, 116)
infoLabel.BackgroundTransparency = 1
infoLabel.Text = "Nearest: — | Dist: — | R: 3.2"
infoLabel.Font = Enum.Font.Arcade
infoLabel.TextSize = 14
infoLabel.TextColor3 = Color3.fromRGB(220,220,220)
infoLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Mode buttons (preserve names)
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

-- ESP toggle
local espBtn = Instance.new("TextButton", frame)
espBtn.Size = UDim2.new(0.24, -6, 0, 36)
espBtn.Position = UDim2.new(0.76, 6, 0, 148)
espBtn.Text = "PlayerESP"
styleButton(espBtn)

-- AimView / NoFall / LookAim buttons (simple proxies)
local lookAimBtn = Instance.new("TextButton", frame)
lookAimBtn.Size = UDim2.new(0, 120, 0, 34)
lookAimBtn.Position = UDim2.new(0, 6, 0, 232)
lookAimBtn.Text = "LookAim: OFF"
styleButton(lookAimBtn)

local noFallBtn = Instance.new("TextButton", frame)
noFallBtn.Size = UDim2.new(0, 120, 0, 34)
noFallBtn.Position = UDim2.new(0, 156, 0, 232)
noFallBtn.Text = "NoFall: OFF"
styleButton(noFallBtn)

local aimViewBtn = Instance.new("TextButton", frame)
aimViewBtn.Size = UDim2.new(0, 120, 0, 34)
aimViewBtn.Position = UDim2.new(0, 456, 0, 232)
aimViewBtn.Text = "AimView: OFF"
styleButton(aimViewBtn)

-- Slider helper (minimal visual-only slider creator)
local function createSlider(parent, yOffset, labelText, minVal, maxVal, initialVal)
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
    valLabel.Text = tostring(initialVal)
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

    local fill = Instance.new("Frame", sliderBg)
    fill.Size = UDim2.new(0.5, 0, 1, 0)
    fill.Position = UDim2.new(0,0,0,0)
    fill.BackgroundColor3 = Color3.fromRGB(245,136,212)
    fill.BorderSizePixel = 0
    local fillCorner = Instance.new("UICorner", fill); fillCorner.CornerRadius = UDim.new(0,4)

    return {Container = container, SetValue = function(v) valLabel.Text = tostring(v); fill.Size = UDim2.new((v-minVal)/(maxVal-minVal),0,1,0) end, GetValue = function() return tonumber(valLabel.Text) or initialVal end}
end

local sliderSpeed = createSlider(frame, 236, "Orbit Speed", 0.2, 6.0, 2.2)
local sliderRadius = createSlider(frame, 284, "Orbit Radius", 0.5, 8.0, 3.2)
local sliderForce = createSlider(frame, 332, "Force Power", 50, 8000, 1200)
local sliderSearch = createSlider(frame, 380, "Search Radius", 5, 150, 15)

-- Proxy invocation helpers: call into Logic1/Logic2 if available, else print feedback
local function callLogic1(funcName, ...)
    if _G and _G.FioletusLogic1 and type(_G.FioletusLogic1[funcName]) == 'function' then
        pcall(_G.FioletusLogic1[funcName], ...)
        return true
    end
    return false
end
local function callLogic2(funcName, ...)
    if _G and _G.FioletusLogic2 and type(_G.FioletusLogic2[funcName]) == 'function' then
        pcall(_G.FioletusLogic2[funcName], ...)
        return true
    end
    return false
end

-- Wire UI: toggle button toggles mode via Logic1.ToggleEnabled or fallback local label change
local enabled = false
local function updateToggleUI()
    toggleBtn.Text = enabled and "ON" or "OFF"
    toggleBtn.BackgroundColor3 = enabled and Color3.fromRGB(120,220,120) or Color3.fromRGB(220,120,120)
end
toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    updateToggleUI()
    if not callLogic1("SetEnabled", enabled) then
        infoLabel.Text = enabled and "Enabled (local proxy)" or "Disabled (local proxy)"
    else
        infoLabel.Text = "Sent to Logic1"
    end
end)

changeTargetBtn.MouseButton1Click:Connect(function()
    if not callLogic1("CycleTarget") then
        infoLabel.Text = "CycleTarget not available (Logic1)"
    end
end)

-- Mode buttons proxy
btnSmooth.MouseButton1Click:Connect(function() callLogic1("SetMode", "smooth") end)
btnVelocity.MouseButton1Click:Connect(function() callLogic1("SetMode", "velocity") end)
btnTwisted.MouseButton1Click:Connect(function() callLogic1("SetMode", "twisted") end)
btnForce.MouseButton1Click:Connect(function() callLogic1("SetMode", "force") end)

-- ESP button proxy
espBtn.MouseButton1Click:Connect(function()
    if callLogic1("ToggleESP") then return end
    infoLabel.Text = "ESP toggle proxy (Logic1 missing)"
end)

-- LookAim / NoFall / AimView toggles proxy
lookAimBtn.MouseButton1Click:Connect(function() callLogic1("ToggleLookAim") end)
noFallBtn.MouseButton1Click:Connect(function() callLogic1("ToggleNoFall") end)
aimViewBtn.MouseButton1Click:Connect(function() callLogic1("ToggleAimView") end)

-- Sliders send values to Logic1 if function exists
sliderSpeed.Container.InputEnded:Connect(function() callLogic1("SetOrbitSpeed", sliderSpeed.GetValue()) end)
sliderRadius.Container.InputEnded:Connect(function() callLogic1("SetOrbitRadius", sliderRadius.GetValue()) end)
sliderForce.Container.InputEnded:Connect(function() callLogic1("SetForcePower", sliderForce.GetValue()) end)
sliderSearch.Container.InputEnded:Connect(function() callLogic1("SetSearchRadius", sliderSearch.GetValue()) end)

-- Final note
print("Fioletus MAIN UI loaded. Waiting for Logic1/Logic2 modules to be available via HttpGet.")
