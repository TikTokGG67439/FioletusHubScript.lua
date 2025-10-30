local HttpService = game:GetService('HttpService')

local URL_LOGIC1 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic1.lua"
local URL_LOGIC2 = "https://raw.githubusercontent.com/TikTokGG67439/FioletusHubScript.lua/refs/heads/main/FioletusLogic2.lua"

local function fetchRaw(url)
    local ok, res = pcall(function() return HttpService:GetAsync(url, true) end)
    if not ok then
        error('Http Get failed for '..tostring(url)..' : '..tostring(res))
    end
    return res
end

local function compileAndRun(code, name)
    local fn, err = loadstring and loadstring(code) or load(code)
    if not fn then
        error('Compile error for '..tostring(name)..' : '..tostring(err))
    end
    local ok, ret = pcall(fn)
    if not ok then
        error('Runtime error while executing '..tostring(name)..' : '..tostring(ret))
    end
    return ret
end

local function readLocal(path)
    local ok, content = pcall(function()
        local f = io.open(path, 'r')
        if not f then return nil end
        local d = f:read('*a') f:close()
        return d
    end)
    if ok then return content end
    return nil
end

local code1_ok, code1 = pcall(fetchRaw, URL_LOGIC1)
local code2_ok, code2 = pcall(fetchRaw, URL_LOGIC2)

if (not code1_ok or not code1 or #code1 < 20) then
    local local1 = readLocal('FioletusLogic1.txt') or readLocal('/mnt/data/FioletusLogic1.txt')
    if local1 then code1 = local1 end
end
if (not code2_ok or not code2 or #code2 < 20) then
    local local2 = readLocal('FioletusLogic2.txt') or readLocal('/mnt/data/FioletusLogic2.txt')
    if local2 then code2 = local2 end
end

local Module1 = compileAndRun(code1 or 'return nil', 'FioletusLogic1')
local Module2 = compileAndRun(code2 or 'return nil', 'FioletusLogic2')

local Host = {}
function Host.GetLocalPlayer() return game:GetService('Players').LocalPlayer end
function Host.GetWorkspace() return workspace end
function Host.GetCamera() return workspace.CurrentCamera end
function Host.RegisterHighlightForPlayer(p, h) end

if Module1 and Module1.Init then pcall(function() Module1.Init(Host) end) end
if Module2 and Module2.Init then pcall(function() Module2.Init(Host) end) end

_G.FioletusLogic1 = Module1
_G.FioletusLogic2 = Module2

print('Loader: modules loaded (remote or local fallback).')
