local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0
local Camera = workspace.CurrentCamera

-- ---------- ЗАГРУЗКА ВНЕШНИХ ЛОГИК (ВАШИ ССЫЛКИ) ----------
local success1, FioletusLogic1 = pcall(function()
	local s = game:HttpGet("https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua")
	return loadstring(s)()
end)
if not success1 or type(FioletusLogic1) ~= "table" then
	warn("FioletusLogic1 load failed; CheckWall will be basic fallback.")
	FioletusLogic1 = {
		CheckWall = function(localHRP, targetHRP)
			-- очень простой fallback
			if not localHRP or not targetHRP then return false end
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Blacklist
			rp.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}
			local dir = (targetHRP.Position - localHRP.Position)
			local res = workspace:Raycast(localHRP.Position, dir, rp)
			if res and res.Instance and not res.Instance:IsDescendantOf(targetHRP.Parent) then
				return true
			end
			return false
		end
	}
end

local success2, FioletusLogic2 = pcall(function()
	local s = game:HttpGet("https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua")
	return loadstring(s)()
end)
if not success2 or type(FioletusLogic2) ~= "table" then
	warn("FioletusLogic2 load failed; creating local fallback manager.")
	-- минимальные заглушки (чтобы остальной код не падал)
	FioletusLogic2 = {
		InitESP = function() end,
		EnableESPForPlayer = function() end,
		DisableESPForPlayer = function() end,
		UpdateAllColor = function() end,
		ApplyAimView = function() end,
		DestroyAimGyro = function() end,
		EnsureAimGyro = function() end
	}
end

-- ---- UTILS ----
local function getHRP(player)
	local ch = player and player.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function isAlive(player)
	local ch = player and player.Character
	if not ch then return false end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health and hum.Health > 0
end

-- ---- STATE ----
local enabled = false
local currentTarget = nil
local checkWallEnabled = false -- заменяет старый Pathing (CheckWall toggle)
local aimViewCfg = {enabled = false, range = 6, axesY = true, rotateMode = "All"} -- будет передаваться в FioletusLogic2.ApplyAimView

-- --- UI (минимальный, только нужное: toggle, change target, CheckWall, ESP, AimView) ---
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui"); gui.Name = "StrafeMainGUI_"..tostring(PlayerId); gui.ResetOnSpawn = false; gui.Parent = playerGui
local frame = Instance.new("Frame", gui); frame.Size = UDim2.new(0, 420, 0, 52); frame.Position = UDim2.new(0.02,0,0.02,0); frame.BackgroundTransparency = 0.2
local function newBtn(name, posX, text)
	local b = Instance.new("TextButton", frame)
	b.Size = UDim2.new(0, 80, 1, -8)
	b.Position = UDim2.new(0, posX, 0, 4)
	b.Text = text or name
	b.Name = name
	return b
end
local toggleBtn = newBtn("Toggle", 0, "OFF")
local changeBtn = newBtn("Cycle", 0.20, "Cycle")
local checkWallBtn = newBtn("CheckWall", 0.40, "CheckWall: OFF")
local espBtn = newBtn("ESP", 0.60, "ESP: OFF")
local aimViewBtn = newBtn("AimView", 0.80, "AimView: OFF")

-- wire UI
toggleBtn.MouseButton1Click:Connect(function()
	enabled = not enabled
	toggleBtn.Text = enabled and "ON" or "OFF"
	if not enabled then
		currentTarget = nil
		pcall(function() FioletusLogic2.DestroyAimGyro() end)
	end
end)
changeBtn.MouseButton1Click:Connect(function()
	local myHRP = getHRP(LocalPlayer)
	if not myHRP then return end
	local list = {}
	for _,p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and isAlive(p) then
			local hrp = getHRP(p)
			if hrp then table.insert(list, {p=p, d=(hrp.Position - myHRP.Position).Magnitude}) end
		end
	end
	table.sort(list, function(a,b) return a.d < b.d end)
	if #list == 0 then currentTarget = nil else
		if not currentTarget then currentTarget = list[1].p else
			local idx = nil
			for i,v in ipairs(list) do if v.p == currentTarget then idx = i; break end end
			if not idx then currentTarget = list[1].p else currentTarget = list[(idx % #list) + 1].p end
		end
	end
end)
checkWallBtn.MouseButton1Click:Connect(function()
	checkWallEnabled = not checkWallEnabled
	checkWallBtn.Text = "CheckWall: " .. (checkWallEnabled and "ON" or "OFF")
end)
local espOn = false
espBtn.MouseButton1Click:Connect(function()
	espOn = not espOn
	espBtn.Text = "ESP: " .. (espOn and "ON" or "OFF")
	pcall(function()
		if espOn then
			if FioletusLogic2.InitESP then FioletusLogic2.InitESP() end
			for _,p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character then if FioletusLogic2.EnableESPForPlayer then FioletusLogic2.EnableESPForPlayer(p) end end end
		else
			for _,p in ipairs(Players:GetPlayers()) do if FioletusLogic2.DisableESPForPlayer then FioletusLogic2.DisableESPForPlayer(p) end end
		end
	end)
end)
aimViewBtn.MouseButton1Click:Connect(function()
	aimViewCfg.enabled = not aimViewCfg.enabled
	aimViewBtn.Text = "AimView: " .. (aimViewCfg.enabled and "ON" or "OFF")
	if not aimViewCfg.enabled then
		pcall(function() FioletusLogic2.DestroyAimGyro() end)
	end
end)

-- keep ESP up to date on joins/resets
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		if espOn and p ~= LocalPlayer then pcall(function() if FioletusLogic2.EnableESPForPlayer then FioletusLogic2.EnableESPForPlayer(p) end end) end
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	pcall(function() if FioletusLogic2.DisableESPForPlayer then FioletusLogic2.DisableESPForPlayer(p) end end)
	if p == currentTarget then currentTarget = nil end
end)

-- ---- CORE TARGET LOOP (RenderStepped) ----
RunService.RenderStepped:Connect(function(dt)
	if not enabled then return end
	if currentTarget and (not isAlive(currentTarget) or not getHRP(currentTarget)) then currentTarget = nil end

	if not currentTarget then
		local myHRP = getHRP(LocalPlayer)
		if myHRP then
			local closest, bestD = nil, math.huge
			for _,p in ipairs(Players:GetPlayers()) do
				if p ~= LocalPlayer and isAlive(p) then
					local hrp = getHRP(p)
					if hrp then
						local d = (hrp.Position - myHRP.Position).Magnitude
						if d < bestD then closest, bestD = p, d end
					end
				end
			end
			if closest and bestD < 100 then currentTarget = closest end
		end
	end

	if currentTarget then
		local myHRP = getHRP(LocalPlayer)
		local targetHRP = getHRP(currentTarget)
		if not myHRP or not targetHRP then currentTarget = nil; return end

		local blocked = false
		pcall(function()
			if checkWallEnabled and FioletusLogic1 and FioletusLogic1.CheckWall then
				blocked = FioletusLogic1.CheckWall(myHRP, targetHRP)
			end
		end)

		if blocked then
			pcall(function() if FioletusLogic2 and FioletusLogic2.DestroyAimGyro then FioletusLogic2.DestroyAimGyro() end end)
		else
			pcall(function()
				if FioletusLogic2 and FioletusLogic2.ApplyAimView then
					FioletusLogic2.ApplyAimView(myHRP, targetHRP, aimViewCfg)
				end
			end)
		end
	end
end)

LocalPlayer.CharacterAdded:Connect(function(ch)
	ch:WaitForChild("HumanoidRootPart", 2)
	pcall(function() FioletusLogic2.DestroyAimGyro() end)
end)

script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		pcall(function() FioletusLogic2.DestroyAimGyro() end)
	end
end)
