-- Fioletus_MAIN.txt
-- UI + loader for FioletusLogic1.lua (strafe, aim) and FioletusLogic2.lua (visuals)
-- This script tries to HttpGet the two logic files from the provided URLs.
-- If HttpGet fails, it will attempt to run local copies placed under PlayerScripts or PlayerGui.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or script.Parent
local PlayerId = LocalPlayer and LocalPlayer.UserId or 0
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Remote URLs (as requested)
local LOGIC1_URL = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua"
local LOGIC2_URL = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua"

-- Safe http get wrapper (tries several common methods)
local function httpGetRaw(url)
	local ok, res = pcall(function()
		if typeof(game.HttpGet) == "function" then
			return game:HttpGet(url, true)
		elseif syn and syn.request then
			local r = syn.request({Url = url, Method = "GET"})
			return r and r.Body
		elseif request then
			local r = request({Url = url, Method = "GET"})
			return r and r.Body
		else
			local HttpService = game:GetService("HttpService")
			return HttpService:GetAsync(url, true)
		end
	end)
	if ok and res and #res > 0 then return res end
	return nil
end

local function tryRunString(code, name)
	if not code then return false, "no_code" end
	local ok, f = pcall(function() return loadstring(code) end)
	if not ok or type(f) ~= "function" then return false, "load_failed" end
	local ok2, err = pcall(function() f() end)
	return ok2, err
end

-- Try remote load with fallback to local
local function loadLogic(url, localName)
	local code = httpGetRaw(url)
	if code then
		local ok, err = tryRunString(code, localName)
		if ok then return true, "loaded_remote" end
	end
	-- fallback: try to find local LocalScript/ModuleScript under PlayerScripts or PlayerGui
	local function tryContainer(parent)
		if not parent then return false end
		local obj = parent:FindFirstChild(localName)
		if obj and (obj:IsA("LocalScript") or obj:IsA("ModuleScript")) then
			-- If ModuleScript, require it; if LocalScript, it's already running
			if obj:IsA("ModuleScript") then
				local ok, _ = pcall(function() require(obj) end)
				return ok
			end
			return true
		end
		return false
	end
	if tryContainer(LocalPlayer:FindFirstChild("PlayerScripts")) then return true, "loaded_local_playerscripts" end
	if tryContainer(playerGui) then return true, "loaded_local_playergui" end
	return false, "failed_all"
end

-- UI bootstrap note:
-- The heavy UI used by the original script was already present in StrafeScript1498_final_v3_fixed_pathing.txt.
-- This MAIN acts as a loader — it will try to load remote logic first, then local fallbacks.
-- Place the other two files (FioletusLogic1.lua and FioletusLogic2.lua) as LocalScripts under PlayerScripts if HttpGet is not allowed.

-- Attempt to load logics
local ok1, msg1 = loadLogic(LOGIC1_URL, "FioletusLogic1.lua")
local ok2, msg2 = loadLogic(LOGIC2_URL, "FioletusLogic2.lua")

-- If both failed, notify in PlayerGui (simple text)
if not ok1 or not ok2 then
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FioletusLoaderNotice_"..tostring(PlayerId)
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	local label = Instance.new("TextLabel", screenGui)
	label.Size = UDim2.new(0, 420, 0, 64)
	label.Position = UDim2.new(0.5, -210, 0.05, 0)
	label.BackgroundTransparency = 0.2
	label.BackgroundColor3 = Color3.fromRGB(20,20,20)
	label.TextColor3 = Color3.fromRGB(255,200,200)
	label.TextScaled = true
	label.Text = "Fioletus: failed to load remote logic. Places to check: HttpGet enabled or place FioletusLogic1.lua and FioletusLogic2.lua under PlayerScripts/PlayerGui."
end

-- End of MAIN loader.
