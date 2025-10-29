local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- URLS на внешние модули (raw GitHub). Если хотите заменить, редактируйте эти строки.
local URL_LOGIC1 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua"
local URL_LOGIC2 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua"
local Logic1, Logic2 = {}, {}

-- Функция безопасной загрузки модуля через HttpGet -> loadstring. Если не удаётся, остаётся пустая таблица.
local function tryLoad(url)
    local ok, res = pcall(function()
        local s = game:HttpGet(url)
        if s and #s > 8 then
            local f = loadstring(s)
            if f then
                local ok2, ret = pcall(f)
                if ok2 and type(ret) == "table" then return ret end
            end
        end
    end)
    return ok and res or nil
end

-- Попытка загрузить внешние модули. Если вы тестируете оффлайн, можно положить модули локально и заменить логику.
pcall(function() local m = tryLoad(URL_LOGIC1); if m then Logic1 = m end end)
pcall(function() local m = tryLoad(URL_LOGIC2); if m then Logic2 = m end end)

-- Простая UI панель — только кнопки управления и индикаторы. Полная реализация UI из оригинала находится в основном файле (mодулях).
local screenGui = Instance.new("ScreenGui", playerGui)
screenGui.Name = "FioletusHub_UI"
local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Size = UDim2.new(0, 520, 0, 260)
mainFrame.Position = UDim2.new(0.5, -260, 0.7, -130)
mainFrame.BackgroundColor3 = Color3.fromRGB(18,18,20)
local title = Instance.new("TextLabel", mainFrame)
title.Size = UDim2.new(1, -12, 0, 28)
title.Position = UDim2.new(0,6,0,6)
title.BackgroundTransparency = 1
title.Text = "FioletusHub (UI)"
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.new(1,1,1)

-- Кнопки: Toggle, CheckWall, PlayerESP, AimView (управляют состоянием в модулях через _G API)
local function makeButton(parent, name, pos, text)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(0, 120, 0, 28)
    b.Position = pos
    b.Text = text
    b.Name = name
    return b
end
local toggleBtn = makeButton(mainFrame, "Toggle", UDim2.new(0,8,0,44), "Enable")
local checkWallBtn = makeButton(mainFrame, "CheckWall", UDim2.new(0,140,0,44), "CheckWall: OFF")
local espBtn = makeButton(mainFrame, "ESP", UDim2.new(0,272,0,44), "PlayerESP: OFF")
local aimBtn = makeButton(mainFrame, "Aim", UDim2.new(0,404,0,44), "AimView: OFF")

-- State reflected into modules via _G if modules are present
local enabled = false
local checkWallEnabled = false
local espEnabled = false
local aimEnabled = false

toggleBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    toggleBtn.Text = enabled and "Disable" or "Enable"
    if Logic1 and Logic1.OnToggle then pcall(Logic1.OnToggle, enabled) end
end)
checkWallBtn.MouseButton1Click:Connect(function()
    checkWallEnabled = not checkWallEnabled
    checkWallBtn.Text = "CheckWall: " .. (checkWallEnabled and "ON" or "OFF")
    if Logic1 and Logic1.SetCheckWall then pcall(Logic1.SetCheckWall, checkWallEnabled) end
end)
espBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    espBtn.Text = "PlayerESP: " .. (espEnabled and "ON" or "OFF")
    if Logic2 and Logic2.SetESP then pcall(Logic2.SetESP, espEnabled) end
end)
aimBtn.MouseButton1Click:Connect(function()
    aimEnabled = not aimEnabled
    aimBtn.Text = "AimView: " .. (aimEnabled and "ON" or "OFF")
    if Logic1 and Logic1.SetAimView then pcall(Logic1.SetAimView, aimEnabled) end
end)

-- Expose minimal _G API so heavy modules can receive state if HttpGet failed and modules loaded locally.
_G.FioletusHub = {
    GetState = function() return { enabled = enabled, checkWall = checkWallEnabled, esp = espEnabled, aim = aimEnabled } end,
}

-- Clean up on destroy
screenGui.Destroying:Connect(function()
    if Logic1 and Logic1.Cleanup then pcall(Logic1.Cleanup) end
    if Logic2 and Logic2.Cleanup then pcall(Logic2.Cleanup) end
end)
