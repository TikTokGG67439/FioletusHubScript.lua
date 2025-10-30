local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local function GetLocalPlayer(timeout)
    timeout = tonumber(timeout) or 10
    local p = Players.LocalPlayer
    if p then return p end
    if RunService:IsClient() then
        local t0 = tick()
        repeat
            p = Players.LocalPlayer
            if p then return p end
            task.wait(0.05)
        until tick() - t0 > timeout
        p = Players.LocalPlayer or Players:GetPlayers()[1]
        return p
    end
    return nil
end

local LocalPlayer = GetLocalPlayer(10)
local playerGui = nil
if LocalPlayer then
    local ok, pg = pcall(function() return LocalPlayer:WaitForChild('PlayerGui', 5) end)
    if ok and pg then playerGui = pg end
end


-- LOGIC1 BLOCK (core)
-myclient.lua
-For use only in [MyGameName] private development builds.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0
local Camera = workspace.CurrentCamera

-- CONFIG
local SEARCH_RADIUS_DEFAULT = 15

-- Named config table for quick edits (colors / common sliders)
local tab = {
	ESP_R = 212,
	ESP_G = 61,
	ESP_B = 146,
	ORBIT_RADIUS_DEFAULT = 3.2,
	ORBIT_SPEED_BASE = 2.2,
	SEARCH_RADIUS_DEFAULT = 15,
	PATH_SAMPLE_DIST_STEP = 1.2,
	PATH_MAX_SAMPLES = 18,
}

local SEGMENTS = 64
local RING_RADIUS = 2.6
local SEGMENT_HEIGHT = 0.14
local SEGMENT_THICK = 0.45
local RING_HEIGHT_BASE = -1.5
local RING_COLOR = Color3.fromRGB(255, 0, 170)
local RING_TRANSP = 0.22

local SLIDER_LIMITS = {
	BV_POWER_MIN = 50,
	BV_POWER_MAX = 1000,
	BV_POWER_DEFAULT = 200,

	TWIST_MIN = 10,
	TWIST_MAX = 1000,
	TWIST_DEFAULT = 120,

	FORCE_SPEED_MIN = 10,
	FORCE_SPEED_MAX = 10000,
	FORCE_SPEED_DEFAULT = 120,

	FORCE_POWER_MIN = 50,
	FORCE_POWER_MAX = 8000,
	FORCE_POWER_DEFAULT = 1200,
}

local ORBIT_RADIUS_DEFAULT = 3.2
local ORBIT_SPEED_BASE = 2.2
local ALIGN_MAX_FORCE = 5e4
local ALIGN_MIN_FORCE = 500
local ALIGN_RESPONSIVENESS = 18

local HELPER_SPRING = 90
local HELPER_DAMP = 14
local HELPER_MAX_SPEED = 60
local HELPER_MAX_ACCEL = 4000
local HELPER_SMOOTH_INTERP = 12

local ORBIT_NOISE_FREQ = 0.45
local ORBIT_NOISE_AMP = 0.9
local ORBIT_BURST_CHANCE_PER_SEC = 0.6
local ORBIT_BURST_MIN = 1.2
local ORBIT_BURST_MAX = 3.2
local DRIFT_FREQ = 0.12
local DRIFT_AMP = 0.45

-- PATHING (heuristic)
local PATH_SAMPLE_ANGLE_STEPS = 24
local PATH_SAMPLE_DIST_STEP = 1.2
local PATH_MAX_SAMPLES = 18

local UI_POS = UDim2.new(0.5, -310, 0.82, -210)
local FRAME_SIZE = UDim2.new(0, 620, 0, 460) -- немного выше для дополнительных кнопок

-- UTIL
local function getHRP(player)
	local ch = player and player.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

local function safeDestroy(obj)
	if obj and obj.Parent then
		pcall(function() obj:Destroy() end)
	end
end

local function charToKeyCode(str)
	if not str or #str == 0 then return nil end
	local s = tostring(str):upper()
	if s == "-" then return "-" end
	local ok, val = pcall(function() return Enum.KeyCode[s] end)
	if ok and val then return val end
	return nil
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a,b,t) return a + (b-a) * t end

-- robust raycast down helper
local function raycastDown(origin, maxDist, ignoreInst)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	if ignoreInst then rp.FilterDescendantsInstances = {ignoreInst} end
	local res = Workspace:Raycast(origin, Vector3.new(0, -maxDist, 0), rp)
	return res
end

-- reliableGroundBelow: multi-ray ground check for NoFall/AutoJump
local function reliableGroundBelow(position, maxDist, ignoreInst)
    local offsets = {
        Vector3.new(0,0,0),
        Vector3.new(0.4,0,0),
        Vector3.new(-0.4,0,0),
        Vector3.new(0,0,0.4),
        Vector3.new(0,0,-0.4),
    }
    for _, off in ipairs(offsets) do
        local res = raycastDown(position + off, maxDist, ignoreInst)
        if res and res.Instance then
            return true, res
        end
    end
    return false, nil
end


-- PERSISTENCE: store values under Player to survive respawn; also use Attributes if present
local persistFolder = nil
local function ensurePersistFolder()
	if persistFolder and persistFolder.Parent then return end
	persistFolder = LocalPlayer:FindFirstChild("StrafePersist")
	if not persistFolder then
		persistFolder = Instance.new("Folder")
		persistFolder.Name = "StrafePersist"
		persistFolder.Parent = LocalPlayer
	end
end

local function writePersistValue(name, value)
	ensurePersistFolder()
	local existing = persistFolder:FindFirstChild(name)
	if existing then
		if existing:IsA("BoolValue") then existing.Value = (value and true or false) end
		if existing:IsA("NumberValue") then existing.Value = tonumber(value) or 0 end
		if existing:IsA("StringValue") then existing.Value = tostring(value) end
	else
		local typ = type(value)
		if typ == "boolean" then
			local v = Instance.new("BoolValue")
			v.Name = name
			v.Value = value
			v.Parent = persistFolder
		elseif typ == "number" then
			local v = Instance.new("NumberValue")
			v.Name = name
			v.Value = value
			v.Parent = persistFolder
		else
			local v = Instance.new("StringValue")
			v.Name = name
			v.Value = tostring(value)
			v.Parent = persistFolder
		end
	end
	pcall(function() if LocalPlayer.SetAttribute then LocalPlayer:SetAttribute(name, value) end end)
end

local function readPersistValue(name, default)
	ensurePersistFolder()
	local existing = persistFolder:FindFirstChild(name)
	if existing then
		if existing:IsA("BoolValue") then return existing.Value end
		if existing:IsA("NumberValue") then return existing.Value end
		if existing:IsA("StringValue") then return existing.Value end
	end
	if LocalPlayer.GetAttribute then
		local ok, val = pcall(function() return LocalPlayer:GetAttribute(name) end)
		if ok and val ~= nil then return val end
	end
	return default
end

-- UI CREATION
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- remove old ui if exists
for _, c in ipairs(playerGui:GetChildren()) do
	if c.Name == "StrafeRingUI_v4_"..tostring(PlayerId) then safeDestroy(c) end
end

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
