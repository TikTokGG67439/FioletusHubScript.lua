
local Module = {}
local Host = nil
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local playerConns = {}
local espEnabled = false
local checkWallEnabled = false

local function tryCreateHighlight(ch)
	if not ch then return nil end
	local existing = ch:FindFirstChild("StrafeESP_Highlight")
	if existing and existing:IsA("Highlight") then return existing end
	local hl = Instance.new("Highlight")
	hl.Name = "StrafeESP_Highlight"
	hl.Adornee = ch
	hl.FillTransparency = 0.4
	hl.OutlineTransparency = 0
	hl.FillColor = Color3.fromRGB(212,61,146)
	hl.Parent = ch
	return hl
end

local function cleanupEntry(p)
	local e = playerConns[p]
	if not e then return end
	if e.charConn then pcall(function() e.charConn:Disconnect() end) end
	if e.remConn then pcall(function() e.remConn:Disconnect() end) end
	if e.hl then pcall(function() e.hl:Destroy() end) end
	playerConns[p] = nil
end

local function setupPlayer(p)
	if p == Host.GetLocalPlayer() then return end
	cleanupEntry(p)
	local entry = {}
	entry.charConn = p.CharacterAdded:Connect(function(ch)
		if espEnabled then
			entry.hl = tryCreateHighlight(ch)
			-- inform Host if needed
			if Host and Host.RegisterHighlightForPlayer then
				pcall(function() Host.RegisterHighlightForPlayer(p, entry.hl) end)
			end
		end
	end)
	entry.remConn = p.AncestryChanged:Connect(function()
		if not p.Parent then cleanupEntry(p) end
	end)
	playerConns[p] = entry
	-- if character exists now and espEnabled, create highlight
	if p.Character and espEnabled then entry.hl = tryCreateHighlight(p.Character) end
end

function Module.SetESPEnabled(v)
	espEnabled = not not v
	if espEnabled then
		for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
		Players.PlayerAdded:Connect(setupPlayer)
		Players.PlayerRemoving:Connect(function(p) cleanupEntry(p) end)
	else
		-- disable: destroy highlights and disconnect
		for p,e in pairs(playerConns) do
			if e.hl then pcall(function() e.hl:Destroy() end) end
			if e.charConn then pcall(function() e.charConn:Disconnect() end) end
			if e.remConn then pcall(function() e.remConn:Disconnect() end) end
			playerConns[p] = nil
		end
	end
end

function Module.SetCheckWallEnabled(v)
	checkWallEnabled = not not v
end

-- Visibility check via raycast: returns true if visible (not occluded)
function Module.IsTargetVisible(myHRP, targetHRP)
	if not myHRP or not targetHRP then return true end
	if not checkWallEnabled then return true end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	local localChar = Host and Host.GetLocalPlayer and Host.GetLocalPlayer().Character
	rp.FilterDescendantsInstances = {}
	if localChar then table.insert(rp.FilterDescendantsInstances, localChar) end
	if targetHRP.Parent then table.insert(rp.FilterDescendantsInstances, targetHRP.Parent) end
	local origin = myHRP.Position + Vector3.new(0,1.5,0)
	local dir = (targetHRP.Position - origin)
	local res = Workspace:Raycast(origin, dir, rp)
	if res and res.Instance then
		-- if hit is inside target's character, visible; otherwise occluded
		if targetHRP.Parent and res.Instance:IsDescendantOf(targetHRP.Parent) then
			return true
		end
		return false
	end
	return true
end

function Module.Cleanup()
	for p,e in pairs(playerConns) do
		if e.hl then pcall(function() e.hl:Destroy() end) end
		if e.charConn then pcall(function() e.charConn:Disconnect() end) end
		if e.remConn then pcall(function() e.remConn:Disconnect() end) end
		playerConns[p] = nil
	end
end

function Module.Init(host)
	Host = host or {}
	-- initial setup for existing players
	for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
end

return Module
