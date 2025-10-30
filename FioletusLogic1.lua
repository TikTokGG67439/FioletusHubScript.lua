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
