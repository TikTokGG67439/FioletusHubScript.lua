local Module = {}
local Host = nil
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

Module.espEnabled = false
Module.checkWallEnabled = false
Module.espColor = Color3.fromRGB(212,61,146)

local playerHighl = {}

local function safeDestroy(obj) if obj and obj.Parent then pcall(function() obj:Destroy() end) end end

local function makeHighlightForCharacter(ch)
    if not ch then return nil end
    local existing = ch:FindFirstChild("Fioletus_ESP_Highlight")
    if existing and existing:IsA("Highlight") then return existing end
    local hl = Instance.new("Highlight")
    hl.Name = "Fioletus_ESP_Highlight"
    hl.Adornee = ch
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.FillColor = Module.espColor
    hl.Parent = ch
    return hl
end

local function enableForPlayer(p)
    if not p or (Host and Host.GetLocalPlayer and p == Host.GetLocalPlayer()) then return end
    local ch = p.Character
    if not ch then return end
    local hl = makeHighlightForCharacter(ch)
    playerHighl[p] = hl
end

local function disableForPlayer(p)
    local hl = playerHighl[p]
    if hl then safeDestroy(hl) end
    playerHighl[p] = nil
end

local function onPlayerAdded(p)
    p.CharacterAdded:Connect(function(ch)
        if Module.espEnabled then enableForPlayer(p) end
    end)
end

function Module.SetESPEnabled(v)
    Module.espEnabled = not not v
    if Module.espEnabled then
        for _,p in ipairs(Players:GetPlayers()) do
            if Host and Host.GetLocalPlayer and p ~= Host.GetLocalPlayer() then
                enableForPlayer(p)
            end
        end
    else
        for p,_ in pairs(playerHighl) do disableForPlayer(p) end
    end
end

function Module.SetCheckWallEnabled(v) Module.checkWallEnabled = not not v end

function Module.IsTargetVisible(myHRP, targetHRP)
    if not targetHRP or not myHRP then return true end
    if not Module.checkWallEnabled then return true end
    local cam = Host and Host.GetCamera and Host.GetCamera() or workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local dir = (targetHRP.Position - origin)
    local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Blacklist; rp.FilterDescendantsInstances = {}
    if Host and Host.GetLocalPlayer and Host.GetLocalPlayer().Character then table.insert(rp.FilterDescendantsInstances, Host.GetLocalPlayer().Character) end
    if targetHRP.Parent then table.insert(rp.FilterDescendantsInstances, targetHRP.Parent) end
    local res = workspace:Raycast(origin, dir, rp)
    if not res then return true end
    if res.Instance and res.Instance:IsDescendantOf(targetHRP.Parent) then return true end
    return false
end

function Module.Init(host)
    Host = host or {}
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(function(p) disableForPlayer(p) end)
    for _,p in ipairs(Players:GetPlayers()) do onPlayerAdded(p) end
    return Module
end

return Module
