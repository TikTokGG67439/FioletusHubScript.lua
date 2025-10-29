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

	-- NoFall check: if enabled and no ground beneath target within threshold -> drop target
	if noFallEnabled and targetHRP then
		local under = raycastDown(targetHRP.Position + Vector3.new(0,1,0), noFallThreshold, currentTarget.Character)
		if not under then
			setTarget(nil, true)
			return
		end
	end

	-- draw ring
	if currentTarget and #ringParts == 0 then createRingSegments(SEGMENTS) end
	if currentTarget and targetHRP and #ringParts > 0 then
		local levOffset = math.sin(t * 1.0) * 0.22 + (math.noise(t * 0.7, PlayerId * 0.01) - 0.5) * 0.06
		local basePos = targetHRP.Position + Vector3.new(0, RING_HEIGHT_BASE + levOffset, 0)
		local angleStep = (2 * math.pi) / #ringParts
		for i, part in ipairs(ringParts) do
			if not part or not part.Parent then createRingSegments(SEGMENTS); break end
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

	-- CheckWall: if enabled and direct line blocked, try to get a sample waypoint
	if checkWallEnabled then
		local rpParams = RaycastParams.new()
		rpParams.FilterType = Enum.RaycastFilterType.Blacklist
		rpParams.FilterDescendantsInstances = {LocalPlayer.Character, targetHRP.Parent}
		local rp = Workspace:Raycast(myHRP.Position, (targetHRP.Position - myHRP.Position), rpParams)
		if rp then
			local wp = findAlternateWaypoint(myHRP, targetHRP)
			if wp then targetPos = wp end
		end
	end

	-- LookAim: rotate camera toward target part (smooth)
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
