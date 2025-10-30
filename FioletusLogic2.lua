local Module = {}
local Host = nil
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function createHighlightForCharacter(ch, color3)
    if not ch then return nil end
    local existing = ch:FindFirstChild("StrafeESP_Highlight")
    if existing then pcall(function() existing:Destroy() end) end
    local hl = Instance.new("Highlight")
    hl.Name = "StrafeESP_Highlight"
    hl.Adornee = ch
    hl.FillTransparency = 0.4
    hl.OutlineTransparency = 0
    hl.FillColor = color3 or Color3.fromRGB(212,61,146)
    hl.Parent = ch
    return hl
end

function Module.Init(host)
    Host = host or {}
    for _,p in ipairs(Players:GetPlayers()) do
        p.CharacterAdded:Connect(function(ch)
            if Module.espEnabled then createHighlightForCharacter(ch, Module.espColor) end
        end)
    end
end

Module.espEnabled = false
Module.espColor = Color3.fromRGB(212,61,146)

function Module.SetESPEnabled(v)
    Module.espEnabled = not not v
    if Module.espEnabled then
        for _,p in ipairs(Players:GetPlayers()) do
            if p.Character and p ~= Host.GetLocalPlayer() then
                createHighlightForCharacter(p.Character, Module.espColor)
            end
        end
    else
        for _,p in ipairs(Players:GetPlayers()) do
            if p.Character then
                local ex = p.Character:FindFirstChild("StrafeESP_Highlight")
                if ex then pcall(function() ex:Destroy() end) end
            end
        end
    end
end

function Module.SetESPColor(r,g,b)
    Module.espColor = Color3.fromRGB(r or 212, g or 61, b or 146)
end

function Module.Cleanup()
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local ex = p.Character:FindFirstChild("StrafeESP_Highlight")
            if ex then pcall(function() ex:Destroy() end) end
        end
    end
end

return Module
