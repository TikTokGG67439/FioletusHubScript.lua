-- MainScript_bootloader.txt
-- This Main script loads remote logic and visuals via HttpGet (as requested).
-- It then continues with the original main tail from the uploaded script.
local LOGIC1_URL = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua"
local LOGIC2_URL = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua"

local function safeLoadUrl(url)
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if not ok then
        warn("HttpGet failed for", url, res)
        return nil, res
    end
    return res, nil
end

pcall(function()
    local code, err = safeLoadUrl(LOGIC1_URL)
    if code then
        local fn, lerr = loadstring(code)
        if fn then pcall(fn) else warn("loadstring failed for LOGIC1:", lerr) end
    end
end)

pcall(function()
    local code, err = safeLoadUrl(LOGIC2_URL)
    if code then
        local fn, lerr = loadstring(code)
        if fn then pcall(fn) else warn("loadstring failed for LOGIC2:", lerr) end
    end
end)

-- Original main tail follows:

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

	-- Pathing: if enabled and direct line blocked, try to get a sample waypoint
	if pathingEnabled then
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
