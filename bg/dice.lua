-- Dice.
--
-- KOReader's frontend/random.lua seeds with os.time() alone, which repeats if
-- something reseeds within the same second. Mixing in os.clock() and a heap
-- address gives a different stream on every launch.

local M = {}

local seeded = false

function M.seed()
    local addr = tostring({}):match("0x(%x+)") or "0"
    local mix = (tonumber(addr, 16) or 0) % 1000000
    math.randomseed(os.time() + os.clock() * 1000 + mix)
    -- LuaJIT's first value after seeding is weakly correlated with the seed
    for _ = 1, 8 do math.random() end
    seeded = true
end

function M.rollOne()
    if not seeded then M.seed() end
    return math.random(6)
end

-- Fills `out` with the dice to play: two values, or four when they match.
-- Returns the count and the two raw dice.
function M.roll(out)
    if not seeded then M.seed() end
    local a, b = math.random(6), math.random(6)
    if a == b then
        out[1], out[2], out[3], out[4] = a, a, a, a
        return 4, a, b
    end
    out[1], out[2] = a, b
    return 2, a, b
end

return M
