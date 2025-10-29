local Module = {}
local Host = nil

-- Persistent force objects (create once)
local bv = nil -- BodyVelocity
local bg = nil -- BodyGyro
local forceParent = nil -- part to attach forces to

-- Simple ensure function to avoid repeated allocations
local function ensureForces(hrp)
	if not hrp then return end
	forceParent = hrp
	if not bv or not bv.Parent then
		bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(0,0,0)
		bv.P = 8000
		bv.Velocity = Vector3.new(0,0,0)
		bv.Parent = hrp
	end
	if not bg or not bg.Parent then
		bg = Instance.new("BodyGyro")
		bg.MaxTorque = Vector3.new(0,0,0)
		bg.P = 1200
		bg.Parent = hrp
	end
end

-- Cleanly disable forces without destroying (so references stay small)
function Module.DisableForces()
	pcall(function()
		if bv then bv.MaxForce = Vector3.new(0,0,0); bv.Velocity = Vector3.new(0,0,0) end
		if bg then bg.MaxTorque = Vector3.new(0,0,0) end
	end)
end
function Module.EnableForces()
	pcall(function()
		if bv then bv.MaxForce = Vector3.new(4e5,4e5,4e5) end
		if bg then bg.MaxTorque = Vector3.new(3e5,3e5,3e5) end
	end)
end

-- AimView: save/restore camera
local savedCameraType = nil
local savedCFrame = nil
local aimActive = false

function Module.EnableAimView()
	if aimActive then return end
	aimActive = true
	pcall(function()
		local cam = Host and Host.GetCamera and Host.GetCamera()
		if cam then
			savedCameraType = cam.CameraType
			savedCFrame = cam.CFrame
			cam.CameraType = Enum.CameraType.Scriptable
		end
	end)
end
function Module.DisableAimView()
	if not aimActive then return end
	aimActive = false
	pcall(function()
		local cam = Host and Host.GetCamera and Host.GetCamera()
		if cam then
			if savedCameraType then cam.CameraType = savedCameraType end
			if savedCFrame then cam.CFrame = savedCFrame end
		end
	end)
end

-- Basic ground check used by NoFall
local function hasGroundBelow(pos, maxDist)
	local ws = Host and Host.GetWorkspace and Host.GetWorkspace()
	if not ws then return false end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Blacklist
	local selfChar = Host and Host.GetLocalPlayer and Host.GetLocalPlayer().Character or nil
	if selfChar then rp.FilterDescendantsInstances = {selfChar} end
	local r = ws:Raycast(pos + Vector3.new(0,1.3,0), Vector3.new(0,-maxDist,0), rp)
	return r ~= nil
end

-- Called by Main to allow Logic1 perform NoFall handling; returns true if forces were suspended
function Module.HandleNoFall(myHRP)
	if not myHRP then return false end
	local player = Host and Host.GetLocalPlayer and Host.GetLocalPlayer()
	if not player then return false end
	local attrs = player and player:GetAttribute and player:GetAttribute("NoFallThreshold") or nil
	local threshold = (attrs and tonumber(attrs)) or 6
	if not hasGroundBelow(myHRP.Position, threshold) then
		Module.DisableForces()
		return true
	end
	Module.EnableForces()
	return false
end

-- Main application of strafe forces; keeps function small and simple
function Module.ApplyStrafeForces(myHRP, targetHRP, params)
	if not myHRP or not targetHRP then return end
	ensureForces(myHRP)
	-- do not recreate BV/BG here to avoid register/alloc issues
	-- compute direction and set velocities
	local dir = (targetHRP.Position - myHRP.Position)
	local horiz = Vector3.new(dir.X, 0, dir.Z)
	local dist = horiz.Magnitude
	if dist <= 0 then return end
	-- orbit offset perpendicular
	local perp = Vector3.new(-horiz.Z, 0, horiz.X).Unit
	local radius = tonumber(params and params.radius) or 3.2
	local speed = tonumber(params and params.speed) or 12
	-- simple circling velocity: tangent + slight toward target
	local tangent = perp * speed
	local toward = horiz.Unit * (math.max(0, 6 - (dist/2)))
	local finalVel = tangent + toward
	-- apply BodyVelocity
	pcall(function()
		if bv then bv.MaxForce = Vector3.new(4e5,4e5,4e5); bv.Velocity = Vector3.new(finalVel.X, bv.Velocity.Y, finalVel.Z) end
		if bg then bg.MaxTorque = Vector3.new(3e5,3e5,3e5); bg.CFrame = CFrame.new(Vector3.new(), (targetHRP.Position - myHRP.Position).Unit) end
	end)
	-- AimView assistance: rotate camera if requested (delegated minimal)
	if params and params.aimView and Host and Host.GetCamera then
		pcall(function()
			local cam = Host.GetCamera()
			if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
				-- small lookat using CFrame.lookAt without excessive allocations
				cam.CFrame = CFrame.new(cam.CFrame.Position, targetHRP.Position)
			end
		end)
	end
end

function Module.OnEnable() end
function Module.OnDisable() Module.DisableForces() end
function Module.OnTargetChanged(newTarget) end

function Module.Init(host)
	Host = host or {}
end

-- Expose API
return Module

