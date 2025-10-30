-- Универсальный Fioletus loader (работает в эксплойтах и в Studio)
-- Замените <ТВОЙ_НИК> и <REPO> на свои значения или используйте прямые raw-ссылки

local HttpService = game:GetService("HttpService")

-- Попытки разных request-функций (в зависимости от эксплойта)
local function find_request()
    if syn and syn.request then return "syn", syn.request end
    if http and http.request then return "http", http.request end
    if http_request then return "http_request", http_request end
    if request then return "request", request end
    if http_request or (type(rawget(_G, "http_request")) == "function") then return "http_request", http_request end
    -- game:HttpGet (экзекуторы иногда реализуют как метод DataModel)
    if type(game.HttpGet) == "function" then return "gameHttpGet", function(url) return { Body = game:HttpGet(url) } end end
    -- HttpService:GetAsync для Studio/Serverside (если разрешено)
    if HttpService and HttpService.GetAsync then
        return "httpservice", function(url)
            local ok, res = pcall(function() return HttpService:GetAsync(url) end)
            if ok then return { Body = res } end
            return nil, res
        end
    end
    return nil, nil
end

local reqType, requester = find_request()

local function SafeHttpGet(url)
    if not requester then
        warn("[Fioletus Loader] Нет доступной HTTP-функции в окружении.")
        return nil, "no-http"
    end

    -- syn.request / http.request style: table -> table with Body
    if reqType == "syn" or reqType == "http" or reqType == "http_request" or reqType == "request" then
        local ok, resp = pcall(function()
            -- синтаксис syn.request({Url=..., Method="GET"})
            return requester({ Url = url, Method = "GET" })
        end)
        if not ok then
            return nil, resp
        end
        -- resp may be table or string
        if type(resp) == "table" then
            return resp.Body or resp.body or resp
        elseif type(resp) == "string" then
            return resp
        else
            return nil, "bad-response-type"
        end
    end

    -- gameHttpGet wrapper returns table with Body
    if reqType == "gameHttpGet" then
        local ok, res = pcall(function() return requester(url) end)
        if not ok then return nil, res end
        if type(res) == "table" and res.Body then return res.Body end
        if type(res) == "string" then return res end
        return nil, "bad-gameHttpGet-response"
    end

    -- HttpService:GetAsync wrapper
    if reqType == "httpservice" then
        local ok, res = pcall(function() return requester(url) end)
        if not ok then return nil, res end
        return res
    end

    return nil, "unknown-request-type"
end

local loadfun = loadstring or load

local function CompileAndRun(code, name)
    if type(code) ~= "string" then
        return nil, "no-code"
    end
    if not loadfun then
        return nil, "no-load"
    end
    local ok, fn_or_err = pcall(function() return loadfun(code) end)
    if not ok then
        return nil, ("compile-error: " .. tostring(fn_or_err))
    end
    if type(fn_or_err) ~= "function" then
        return nil, ("compile-not-function: " .. tostring(fn_or_err))
    end
    local ok2, result = pcall(fn_or_err)
    if not ok2 then
        return nil, ("runtime-error: " .. tostring(result))
    end
    return result
end

-- === Настройки ===
local BASE = "https://raw.githubusercontent.com/<ТВОЙ_НИК>/<REPO>/main/"
local URL1 = BASE .. "FioletusLogic1.lua"
local URL2 = BASE .. "FioletusLogic2.lua"

-- Попытка загрузки и компиляции
local code1, err1 = SafeHttpGet(URL1)
if not code1 then warn("[Fioletus Loader] HttpGet failed for Logic1:", err1) end

local code2, err2 = SafeHttpGet(URL2)
if not code2 then warn("[Fioletus Loader] HttpGet failed for Logic2:", err2) end

local Module1, m1err
if code1 then Module1, m1err = CompileAndRun(code1, "FioletusLogic1") end
if not Module1 and m1err then warn("[Fioletus Loader] Compile/run failed Logic1:", m1err) end

local Module2, m2err
if code2 then Module2, m2err = CompileAndRun(code2, "FioletusLogic2") end
if not Module2 and m2err then warn("[Fioletus Loader] Compile/run failed Logic2:", m2err) end

-- Минимальный Host (см. твои модули)
local Host = {}
function Host.GetLocalPlayer() return game:GetService("Players").LocalPlayer end
function Host.GetWorkspace() return workspace end
function Host.GetCamera() return workspace.CurrentCamera end
function Host.RegisterHighlightForPlayer(p, h) end

-- Инициализация, если модули дали Init
if type(Module1) == "table" and Module1.Init then
    pcall(function() Module1.Init(Host) end)
end
if type(Module2) == "table" and Module2.Init then
    pcall(function() Module2.Init(Host) end)
end

-- Для отладки
_G.FioletusLogic1 = Module1
_G.FioletusLogic2 = Module2
print("[Fioletus Loader] done, modules:", (Module1 and "loaded" or "nil"), (Module2 and "loaded" or "nil"))
