local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- Remote URLs (exact as you specified)
local URL_LOGIC1 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua"
local URL_LOGIC2 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua"

-- Minimal safe loader using explicit game:HttpGet when available, otherwise HttpService:GetAsync
local function loadRemoteModule(url)
    local code = nil
    local ok, res = pcall(function()
        if typeof(game.HttpGet) == "function" then
            return game:HttpGet(url)
        else
            return HttpService:GetAsync(url)
        end
    end)
    if not ok then return nil, ("Http failed: %s"):format(tostring(res)) end
    code = res
    local loadFn = loadstring or load
    if not loadFn then return nil, "no load function available" end
    local ok2, chunk = pcall(function() return loadFn(code) end)
    if not ok2 then return nil, ("load failed: %s"):format(tostring(chunk)) end
    local ok3, result = pcall(function() return chunk() end)
    if not ok3 then return nil, ("chunk exec failed: %s"):format(tostring(result)) end
    return result, nil
end

-- Try explicit loadstring(game:HttpGet(...)) style first (user asked for this style)
local Logic1, Logic2, err1, err2
do
    local ok, res = pcall(function()
        if typeof(game.HttpGet) == "function" then
            local s1 = game:HttpGet(URL_LOGIC1)
            local s2 = game:HttpGet(URL_LOGIC2)
            local f1 = (loadstring or load)(s1)
            local f2 = (loadstring or load)(s2)
            return f1(), f2()
        else
            return nil, nil
        end
    end)
    if ok and res then
        Logic1 = res
        -- second returned as multiple returns might complicate; try safer
        -- above returns only first; so attempt individually
        -- Try separate safer attempts next if nil
    end
end

-- If above didn't populate modules, use safe loader individually
if not Logic1 then
    local m1, e1 = loadRemoteModule(URL_LOGIC1)
    if m1 then Logic1 = m1 else err1 = e1 end
end
if not Logic2 then
    local m2, e2 = loadRemoteModule(URL_LOGIC2)
    if m2 then Logic2 = m2 else err2 = e2 end
end

-- Fallback: try to require local ModuleScripts named exactly "FioletusLogic1" and "FioletusLogic2"
if not Logic1 or not Logic2 then
    pcall(function()
        local parent = script.Parent
        if not Logic1 and parent then
            local mod1 = parent:FindFirstChild("FioletusLogic1")
            if mod1 and mod1:IsA("ModuleScript") then
                Logic1 = require(mod1)
            end
        end
        if not Logic2 and parent then
            local mod2 = parent:FindFirstChild("FioletusLogic2")
            if mod2 and mod2:IsA("ModuleScript") then
                Logic2 = require(mod2)
            end
        end
    end)
end

-- Final safe stubs if modules still missing (so main never errors)
if not Logic1 then
    Logic1 = {}
    function Logic1.Init() end
    function Logic1.ApplyStrafeForces() end
    function Logic1.HandleNoFall() return false end
    function Logic1.EnableAimView() end
    function Logic1.DisableAimView() end
    function Logic1.OnEnable() end
    function Logic1.OnDisable() end
    function Logic1.OnTargetChanged() end
end
if not Logic2 then
    Logic2 = {}
    function Logic2.Init() end
    function Logic2.IsTargetVisible() return true end
    function Logic2.SetESPEnabled() end
    function Logic2.SetCheckWallEnabled() end
    function Logic2.Cleanup() end
    function Logic2.Init() end
end

-- Host callbacks to pass to modules
local Host = {}
function Host.GetLocalPlayer() return LocalPlayer end
function Host.GetCamera() return Camera end
function Host.GetWorkspace() return Workspace end
function Host.GetPlayers() return Players end
function Host.Warn(...) warn(...) end
function Host.RegisterHighlightForPlayer(p, hl) end

pcall(function() if Logic1.Init then Logic1.Init(Host) end end)
pcall(function() if Logic2.Init then Logic2.Init(Host) end end)

-- UI: simple toggles to control system (keeps main small)
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Fioletus_HttpMain_UI_"..tostring(LocalPlayer.UserId)
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame", screenGui)
frame.Size = UDim2.new(0, 360, 0, 96)
frame.Position = UDim2.new(0, 12, 0, 12)
frame.BackgroundTransparency = 0.2

local function mkBtn(txt, x, y)
    local b = Instance.new("TextButton", frame)
    b.Size = UDim2.new(0, 120, 0, 28)
    b.Position = UDim2.new(0, x, 0, y)
    b.Text = txt
    b.Font = Enum.Font.SourceSansBold
    b.TextSize = 14
    return b
end

local btnStrafe = mkBtn("Strafe: OFF", 6, 6)
local btnCheckWall = mkBtn("CheckWall: OFF", 126, 6)
local btnNoFall = mkBtn("NoFall: OFF", 246, 6)
local btnESP = mkBtn("PlayerESP: OFF", 6, 42)
local btnAimView = mkBtn("AimView: OFF", 126, 42)

local enabled, checkWallEnabled, noFallEnabled, espEnabled, aimViewEnabled = false, false, false, false, false

-- Helper for HRP
local function getHRP(player)
    if not player or not player.Character then return nil end
    return player.Character:FindFirstChild("HumanoidRootPart")
end

local currentTarget = nil
local function setTarget(p)
    currentTarget = p
    pcall(function() if Logic1.OnTargetChanged then Logic1.OnTargetChanged(p) end end)
end

local SEARCH_RADIUS = 15
local function findNearestTarget(radius)
    local myHRP = getHRP(LocalPlayer)
    if not myHRP then return nil end
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = getHRP(p)
            local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health and hum.Health > 0 then
                local d = (hrp.Position - myHRP.Position).Magnitude
                if d <= radius and d < bestD then bestD, best = d, p end
            end
        end
    end
    return best
end

-- Core loop
local last = tick()
RunService.RenderStepped:Connect(function()
    local now = tick()
    local dt = now - last
    last = now
    if not enabled then return end
    if not currentTarget or not currentTarget.Character then
        local nt = findNearestTarget(SEARCH_RADIUS)
        setTarget(nt)
    end
    if not currentTarget or not currentTarget.Character then return end
    local myHRP = getHRP(LocalPlayer)
    local targetHRP = getHRP(currentTarget)
    if not myHRP or not targetHRP then return end
    -- CheckWall via Logic2
    if checkWallEnabled and Logic2 and Logic2.IsTargetVisible then
        local ok, vis = pcall(function() return Logic2.IsTargetVisible(myHRP, targetHRP) end)
        if ok and not vis then return end
    end
    -- NoFall handling via Logic1
    if noFallEnabled and Logic1 and Logic1.HandleNoFall then
        local ok, suspended = pcall(function() return Logic1.HandleNoFall(myHRP) end)
        if ok and suspended then return end
    end
    -- Apply strafe
    if Logic1 and Logic1.ApplyStrafeForces then
        pcall(function() Logic1.ApplyStrafeForces(myHRP, targetHRP, {dt = dt, aimView = aimViewEnabled}) end)
    end
end)

-- Buttons behavior
btnStrafe.MouseButton1Click:Connect(function()
    enabled = not enabled
    btnStrafe.Text = "Strafe: " .. (enabled and "ON" or "OFF")
    if Logic1 then pcall(function() if enabled and Logic1.OnEnable then Logic1.OnEnable() end end) end
    if Logic1 then pcall(function() if (not enabled) and Logic1.OnDisable then Logic1.OnDisable() end end) end
    if not enabled and aimViewEnabled then
        aimViewEnabled = false
        btnAimView.Text = "AimView: OFF"
        if Logic1 and Logic1.DisableAimView then pcall(function() Logic1.DisableAimView() end) end
    end
end)

btnCheckWall.MouseButton1Click:Connect(function()
    checkWallEnabled = not checkWallEnabled
    btnCheckWall.Text = "CheckWall: " .. (checkWallEnabled and "ON" or "OFF")
    if Logic2 and Logic2.SetCheckWallEnabled then pcall(function() Logic2.SetCheckWallEnabled(checkWallEnabled) end) end
end)

btnNoFall.MouseButton1Click:Connect(function()
    noFallEnabled = not noFallEnabled
    btnNoFall.Text = "NoFall: " .. (noFallEnabled and "ON" or "OFF")
end)

btnESP.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    btnESP.Text = "PlayerESP: " .. (espEnabled and "ON" or "OFF")
    if Logic2 and Logic2.SetESPEnabled then pcall(function() Logic2.SetESPEnabled(espEnabled) end) end
end)

btnAimView.MouseButton1Click:Connect(function()
    if aimViewEnabled then
        aimViewEnabled = false
        btnAimView.Text = "AimView: OFF"
        if Logic1 and Logic1.DisableAimView then pcall(function() Logic1.DisableAimView() end) end
    else
        aimViewEnabled = true
        btnAimView.Text = "AimView: ON"
        if Logic1 and Logic1.EnableAimView then pcall(function() Logic1.EnableAimView() end) end
    end
end)

-- Cleanup
script.AncestryChanged:Connect(function(_, parent)
    if not parent then
        pcall(function() if Logic2 and Logic2.Cleanup then Logic2.Cleanup() end end)
        pcall(function() if Logic1 and Logic1.OnDisable then Logic1.OnDisable() end end)
    end
end)
