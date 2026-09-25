-- Persistent preferences and lifetime stats.
--
-- Preferences: which colour player 1 plays, which corner they bear off to,
-- whether the board flips to face the player on move (two-player), and the UI
-- language. Stats: cumulative counts keyed by name.
--
-- Persisted via KOReader's LuaSettings when available; falls back to in-memory
-- defaults otherwise (e.g. headless tests), so callers never care if saving
-- actually worked.

local Settings = {}

local DEFAULTS = {
    user_color = "white",   -- "white" | "black"
    bear_off = "right",     -- "right" | "left"
    flip_turns = "off",     -- "on" | "off" (two-player: flip board each turn)
    cube = "off",           -- "on" | "off" (doubling cube)
    language = "auto",      -- "auto" | "en" | "tr"
}
local ENUMS = {
    user_color = { white = true, black = true },
    bear_off = { right = true, left = true },
    flip_turns = { on = true, off = true },
    cube = { on = true, off = true },
    language = { auto = true, en = true, tr = true },
}

local values, stats, store, saved

local function load()
    if values then return end
    values, stats = {}, {}
    for k, v in pairs(DEFAULTS) do values[k] = v end
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if ok_ls and ok_ds then
        local ok, s = pcall(function()
            return LuaSettings:open(DataStorage:getSettingsDir() .. "/backgammon.lua")
        end)
        if ok and s then
            store = s
            for k in pairs(DEFAULTS) do
                local v = s:readSetting(k)
                if v ~= nil and (not ENUMS[k] or ENUMS[k][v]) then values[k] = v end
            end
            stats = s:readSetting("stats") or {}
            saved = s:readSetting("saved_game")
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
    if store then pcall(function() store:saveSetting(key, val); store:flush() end) end
end

-- lifetime stats: plain numeric counters keyed by name
function Settings.getStat(key)
    load()
    return stats[key] or 0
end

function Settings.setStat(key, val)
    load()
    stats[key] = val
    if store then pcall(function() store:saveSetting("stats", stats); store:flush() end) end
end

function Settings.incStat(key, by)
    Settings.setStat(key, Settings.getStat(key) + (by or 1))
end

-- A single in-progress game, saved when the board is closed and cleared when it
-- is finished or abandoned. Stored as a plain table (numbers and short strings).
function Settings.saveGame(tbl)
    load()
    saved = tbl
    if store then pcall(function() store:saveSetting("saved_game", tbl); store:flush() end) end
end

function Settings.loadGame()
    load()
    return saved
end

function Settings.clearGame()
    load()
    saved = nil
    if store then pcall(function() store:delSetting("saved_game"); store:flush() end) end
end

function Settings.hasSavedGame()
    return Settings.loadGame() ~= nil
end

return Settings
