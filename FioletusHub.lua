local HttpGet = game.HttpGet or (function(url, cache) return game:HttpGet(url, cache) end)
local loadfun = loadstring or load

local function HttpGetSafe(url)
    local ok, res = pcall(function() return HttpGet(game, url, true) end)
    if not ok then error("HttpGet failed: "..tostring(res)) end
    return res
end

local function CompileAndRun(code, name)
    if not loadfun then error("loadstring/load not available in this environment") end
    local fn, perr = pcall(function() return loadfun(code) end)
    if not fn or type(perr) ~= "function" then error("Compile error for "..tostring(name).." : "..tostring(perr)) end
    local ok, ret = pcall(perr)
    if not ok then error("Runtime error in "..tostring(name)..": "..tostring(ret)) end
    return ret
end

local BASE = "https://raw.githubusercontent.com/<ТВОЙ_НИК>/<REPO>/main/"
local LOGIC1_URL = BASE .. "FioletusLogic1.lua"
local LOGIC2_URL = BASE .. "FioletusLogic2.lua"

local ok, code1 = pcall(HttpGetSafe, LOGIC1_URL)
local ok2, code2 = pcall(HttpGetSafe, LOGIC2_URL)

local Module1, Module2
if ok then
    local okc, m1 = pcall(function() return CompileAndRun(code1, "FioletusLogic1") end)
    if okc then Module1 = m1 else warn("Compile/run failed for Logic1") end
end
if ok2 then
    local okc2, m2 = pcall(function() return CompileAndRun(code2, "FioletusLogic2") end)
    if okc2 then Module2 = m2 else warn("Compile/run failed for Logic2") end
end

local Host = {}
function Host.GetLocalPlayer() return game:GetService("Players").LocalPlayer end
function Host.GetWorkspace() return workspace end
function Host.GetCamera() return workspace.CurrentCamera end
function Host.RegisterHighlightForPlayer(p, h) end

if type(Module1) == "table" and Module1.Init then
    pcall(function() Module1.Init(Host) end)
end
if type(Module2) == "table" and Module2.Init then
    pcall(function() Module2.Init(Host) end)
end

_G.FioletusLogic1 = Module1
_G.FioletusLogic2 = Module2
