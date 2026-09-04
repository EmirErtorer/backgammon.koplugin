-- Persistent board preferences: which colour player 1 (the person seeing the
-- device logo upright) plays, and which bottom corner they bear off to.
--
-- Persisted via KOReader's LuaSettings when available. Falls back to in-memory
-- defaults when those modules are absent (e.g. headless tests), so the rest of
-- the plugin never has to care whether saving worked.

local Settings = {}

local DEFAULTS = { user_color = "white", bear_off = "right" }

local values, store

local function load()
    if values then return end
    values = { user_color = DEFAULTS.user_color, bear_off = DEFAULTS.bear_off }
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if ok_ls and ok_ds then
        local ok, s = pcall(function()
            return LuaSettings:open(DataStorage:getSettingsDir() .. "/backgammon.lua")
        end)
        if ok and s then
            store = s
            local c = s:readSetting("user_color")
            local b = s:readSetting("bear_off")
            if c == "white" or c == "black" then values.user_color = c end
            if b == "right" or b == "left" then values.bear_off = b end
        end
    end
end

function Settings.get(key)
    load()
    return values[key]
end

function Settings.set(key, val)
    load()
    values[key] = val
    if store then
        pcall(function() store:saveSetting(key, val); store:flush() end)
    end
end

return Settings
