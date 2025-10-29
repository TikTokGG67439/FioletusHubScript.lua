local function isTargetOccludedByWall(localHRP, targetHRP)
	if not localHRP or not targetHRP then return false end
	local startPos = localHRP.Position + Vector3.new(0,1.2,0)
	local endPos = targetHRP.Position + Vector3.new(0,1.2,0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	rp.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}
	local res = Workspace:Raycast(startPos, (endPos - startPos), rp)
	if not res then return false end
	if res.Instance and res.Instance:IsDescendantOf(targetHRP.Parent) then return false end
	return true
end

-- Logic1: part of original starting at RenderStepped
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
pathBtn.Text = "Pathing: OFF"
styleButton(pathBtn)

pathBtn.MouseButton1Click:Connect(function()
	checkWallEnabled = not checkWallEnabled
	pathBtn.Text = "Pathing: " .. (checkWallEnabled and "ON" or "OFF")
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
