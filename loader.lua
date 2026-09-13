# Local-only reference loader. Prefer Multscript.lua (GitHub fetch).
local USER    = "yukiyuki22"
local REPO    = "aw_cs2v6_femboytap"
local VERSION = "latest"

local function ref()
    if VERSION == nil or VERSION == "" or VERSION == "latest" then return "main" end
    return VERSION
end

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. ref() .. "/"

local function fetch(url, cacheFile)
    local src
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    if type(src) == "string" and #src > 500 then
        pcall(function()
            local f = file.Open(cacheFile, "w")
            if f then f:Write(src); f:Close() end
        end)
        return src, "server"
    end
    pcall(function()
        local f = file.Open(cacheFile, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then return src, "cache" end
    return nil
end

local src, where = fetch(BASE .. "femboytap.lua", ".\\femboytap_lua\\femboytap.lua")
if not src then print("[loader] FATAL: cannot fetch femboytap.lua") return end

local chunk, err = loadstring(src, "=femboytap.lua")
if not chunk then print("[loader] compile error: " .. tostring(err)) return end

_G.FEMBOY_BASE = BASE
print(string.format("[loader] femboytap %s from %s", ref(), tostring(where)))

local ok, e = pcall(chunk)
if not ok then print("[loader] run error: " .. tostring(e)) end
