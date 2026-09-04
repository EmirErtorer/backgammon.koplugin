-- Tavla rules engine. Pure Lua, no KOReader dependencies, so it can be run and
-- tested from a plain luajit prompt.
--
-- Board is 24 absolute points, 1..24. points[i] is signed: positive counts
-- WHITE checkers, negative counts BLACK. One flat array of numbers, no per
-- point tables.
--
-- WHITE travels 24 -> 1 and bears off past 1, home board 1..6.
-- BLACK travels 1 -> 24 and bears off past 24, home board 19..24.
--
-- Move generation applies and undoes moves in place rather than copying the
-- board. Search depth is at most four, so the undo records are preallocated and
-- the whole search allocates nothing.

local M = {}

M.WHITE = 1
M.BLACK = -1

M.BAR = 0     -- pseudo point: on the bar
M.OFF = 25    -- pseudo point: borne off

local WHITE, BLACK, BAR, OFF = M.WHITE, M.BLACK, M.BAR, M.OFF

function M.opponent(player)
    return -player
end

-- Home board bounds for a player, and the direction of travel.
local function homeRange(player)
    if player == WHITE then return 1, 6 else return 19, 24 end
end

function M.homeRange(player) return homeRange(player) end

-- How far a checker on `point` still has to travel, counting the bear off
-- square as one step past the last point. Used for pip counts and to decide
-- whether a die overshoots.
local function distanceToOff(player, point)
    if player == WHITE then return point else return 25 - point end
end
M.distanceToOff = distanceToOff

function M.newState()
    local s = {
        points = {},
        bar = { [WHITE] = 0, [BLACK] = 0 },
        off = { [WHITE] = 0, [BLACK] = 0 },
    }
    for i = 1, 24 do s.points[i] = 0 end
    return s
end

-- Standard opening position: 2 on the 24 point, 5 on the 13, 3 on the 8 and
-- 5 on the 6, from each player's own perspective.
function M.setupStart(s)
    for i = 1, 24 do s.points[i] = 0 end
    s.points[24] = 2
    s.points[13] = 5
    s.points[8] = 3
    s.points[6] = 5
    s.points[1] = -2
    s.points[12] = -5
    s.points[17] = -3
    s.points[19] = -5
    s.bar[WHITE], s.bar[BLACK] = 0, 0
    s.off[WHITE], s.off[BLACK] = 0, 0
    return s
end

function M.copyInto(dst, src)
    for i = 1, 24 do dst.points[i] = src.points[i] end
    dst.bar[WHITE], dst.bar[BLACK] = src.bar[WHITE], src.bar[BLACK]
    dst.off[WHITE], dst.off[BLACK] = src.off[WHITE], src.off[BLACK]
    return dst
end

function M.countAt(s, point, player)
    local v = s.points[point]
    if player == WHITE then
        return v > 0 and v or 0
    else
        return v < 0 and -v or 0
    end
end

-- A point is open if it is empty, ours, or holds a single enemy checker.
local function isOpen(s, point, player)
    local v = s.points[point]
    if player == WHITE then return v >= -1 else return v <= 1 end
end
M.isOpen = isOpen

function M.isBlot(s, point, player)
    return s.points[point] == -player
end

function M.pipCount(s, player)
    local pips = s.bar[player] * 25
    for i = 1, 24 do
        local n = M.countAt(s, i, player)
        if n > 0 then pips = pips + n * distanceToOff(player, i) end
    end
    return pips
end

-- Bearing off needs every checker home, and nothing on the bar.
function M.canBearOff(s, player)
    if s.bar[player] > 0 then return false end
    local lo, hi = homeRange(player)
    for i = 1, 24 do
        if i < lo or i > hi then
            if M.countAt(s, i, player) > 0 then return false end
        end
    end
    return true
end

-- Highest occupied point measured as distance from the bear off square, so a
-- die larger than this may bear off. WHITE counts up from point 1.
local function highestOccupiedDistance(s, player)
    local lo, hi = homeRange(player)
    local best = 0
    for i = lo, hi do
        if M.countAt(s, i, player) > 0 then
            local d = distanceToOff(player, i)
            if d > best then best = d end
        end
    end
    return best
end
M.highestOccupiedDistance = highestOccupiedDistance

-- Where a die lands a checker sitting on `from`. Returns the destination point,
-- or OFF, or nil when the move is not possible.
local function destination(s, player, from, die)
    if from == BAR then
        local to = (player == WHITE) and (25 - die) or die
        if isOpen(s, to, player) then return to end
        return nil
    end

    local to = (player == WHITE) and (from - die) or (from + die)
    if to >= 1 and to <= 24 then
        if isOpen(s, to, player) then return to end
        return nil
    end

    -- Past the edge of the board: only legal as a bear off.
    if not M.canBearOff(s, player) then return nil end
    local dist = distanceToOff(player, from)
    if die == dist then return OFF end
    -- Overshooting only allowed from the highest occupied point.
    if die > dist and dist == highestOccupiedDistance(s, player) then return OFF end
    return nil
end
M.destination = destination

-- Apply a move in place, recording what is needed to undo it.
-- `undo` is a caller supplied table that gets reused.
function M.applyMove(s, player, from, to, undo)
    undo.from, undo.to, undo.hit = from, to, false

    if from == BAR then
        s.bar[player] = s.bar[player] - 1
    else
        s.points[from] = s.points[from] - player
    end

    if to == OFF then
        s.off[player] = s.off[player] + 1
    else
        if s.points[to] == -player then
            -- hitting a blot
            undo.hit = true
            s.points[to] = 0
            s.bar[-player] = s.bar[-player] + 1
        end
        s.points[to] = s.points[to] + player
    end
end

function M.undoMove(s, player, undo)
    local from, to = undo.from, undo.to

    if to == OFF then
        s.off[player] = s.off[player] - 1
    else
        s.points[to] = s.points[to] - player
        if undo.hit then
            s.points[to] = -player
            s.bar[-player] = s.bar[-player] - 1
        end
    end

    if from == BAR then
        s.bar[player] = s.bar[player] + 1
    else
        s.points[from] = s.points[from] + player
    end
end

-- Every source point the player could move from, in board order. Written into
-- `out` (reused) as a count plus values, to keep the search allocation free.
local function sources(s, player, out)
    if s.bar[player] > 0 then
        out[1] = BAR
        out.n = 1
        return out
    end
    local n = 0
    for i = 1, 24 do
        if M.countAt(s, i, player) > 0 then
            n = n + 1
            out[n] = i
        end
    end
    out.n = n
    return out
end

--------------------------------------------------------------------------
-- turn analysis
--------------------------------------------------------------------------

-- Scratch space, allocated once. The search is depth four at most and single
-- threaded, so sharing these across calls is safe.
local scratch_undo = {}
local scratch_src = {}
for i = 1, 4 do
    scratch_undo[i] = { from = 0, to = 0, hit = false }
    scratch_src[i] = { n = 0 }
end
local scratch_used = { false, false, false, false }

-- Depth first search over the remaining dice, returning the longest sequence
-- length reachable from this position.
--
-- At the top level `record` is called once per candidate opening move with the
-- sequence length that move leads to, which is what lets the caller keep only
-- the moves that start a maximal sequence.
local function search(s, player, dice, ndice, depth, record)
    local best = 0
    local src = scratch_src[depth]
    local undo = scratch_undo[depth]
    sources(s, player, src)

    for di = 1, ndice do
        if not scratch_used[di] then
            local die = dice[di]
            -- Equal dice values give identical subtrees; explore one of them.
            local dup = false
            for dj = 1, di - 1 do
                if not scratch_used[dj] and dice[dj] == die then dup = true break end
            end
            if not dup then
                scratch_used[di] = true
                for k = 1, src.n do
                    local from = src[k]
                    local to = destination(s, player, from, die)
                    if to then
                        M.applyMove(s, player, from, to, undo)
                        local sub = 0
                        if depth < ndice then
                            sub = search(s, player, dice, ndice, depth + 1, nil)
                        end
                        M.undoMove(s, player, undo)

                        local total = 1 + sub
                        if total > best then best = total end
                        if record then record(from, to, die, total) end
                    end
                end
                scratch_used[di] = false
            end
        end
    end
    return best
end

-- Result object for analyse(). Reused between calls so that recomputing the
-- legal moves after every tap does not churn the heap.
local result = {
    n = 0,
    max_depth = 0,
    from = {},
    to = {},
    die = {},
}

local collect_max = 0
local function recorder(from, to, die, depth)
    if depth < collect_max then return end
    -- keep one entry per (from, to) pair; the die that got there is what the
    -- move will consume
    for i = 1, result.n do
        if result.from[i] == from and result.to[i] == to then return end
    end
    local n = result.n + 1
    result.n = n
    result.from[n] = from
    result.to[n] = to
    result.die[n] = die
end

--- Work out which moves the player may make right now.
--
-- Legality is a property of the whole turn, not of a single die: a move is only
-- allowed if it starts a sequence that uses as many dice as any other sequence
-- does. That is the "you must play both numbers if you can" rule, and it cannot
-- be decided one die at a time.
--
-- @param dice array of remaining die values (1..4 entries)
-- @return the shared result table: n, max_depth, from[], to[], die[]
function M.analyse(s, player, dice, ndice)
    ndice = ndice or #dice
    result.n = 0
    result.max_depth = 0
    for i = 1, 4 do scratch_used[i] = false end

    if ndice == 0 then return result end

    local max_depth = search(s, player, dice, ndice, 1, nil)
    result.max_depth = max_depth
    if max_depth == 0 then return result end

    collect_max = max_depth
    for i = 1, 4 do scratch_used[i] = false end
    search(s, player, dice, ndice, 1, recorder)

    -- When only one die can be played and the two are different, the higher one
    -- must be used if that is legal at all.
    if max_depth == 1 and ndice == 2 and dice[1] ~= dice[2] then
        local hi = dice[1] > dice[2] and dice[1] or dice[2]
        local has_hi = false
        for i = 1, result.n do
            if result.die[i] == hi then has_hi = true break end
        end
        if has_hi then
            local w = 0
            for i = 1, result.n do
                if result.die[i] == hi then
                    w = w + 1
                    result.from[w] = result.from[i]
                    result.to[w] = result.to[i]
                    result.die[w] = result.die[i]
                end
            end
            result.n = w
        end
    end

    return result
end

-- True when the player has a checker on the bar and cannot enter with any die
-- (the opponent has closed all six entry points). Such a turn is hopeless for
-- every possible roll, so the caller can skip it without rolling.
function M.closedOut(s, player)
    if s.bar[player] <= 0 then return false end
    for die = 1, 6 do
        if destination(s, player, BAR, die) ~= nil then return false end
    end
    return true
end

--------------------------------------------------------------------------
-- outcome
--------------------------------------------------------------------------

function M.winner(s)
    if s.off[WHITE] >= 15 then return WHITE end
    if s.off[BLACK] >= 15 then return BLACK end
    return nil
end

--- Points won: 1 normal, 2 mars, 3 when the loser still has a checker in the
--- winner's home board.
---
--- A checker on the bar counts as being in the winner's home board, since that
--- is where it would have to enter. See the README if that needs changing.
function M.scoreFor(s, winner)
    local loser = -winner
    if s.off[loser] > 0 then return 1 end

    if s.bar[loser] > 0 then return 3 end
    local lo, hi = homeRange(winner)
    for i = lo, hi do
        if M.countAt(s, i, loser) > 0 then return 3 end
    end
    return 2
end

--------------------------------------------------------------------------
-- invariants, used by the tests
--------------------------------------------------------------------------

function M.check(s)
    local total = { [WHITE] = s.bar[WHITE] + s.off[WHITE],
                    [BLACK] = s.bar[BLACK] + s.off[BLACK] }
    for i = 1, 24 do
        local v = s.points[i]
        if v > 0 then
            total[WHITE] = total[WHITE] + v
        elseif v < 0 then
            total[BLACK] = total[BLACK] - v
        end
    end
    if total[WHITE] ~= 15 then return false, "white has " .. total[WHITE] .. " checkers" end
    if total[BLACK] ~= 15 then return false, "black has " .. total[BLACK] .. " checkers" end
    if s.bar[WHITE] < 0 or s.bar[BLACK] < 0 then return false, "negative bar count" end
    if s.off[WHITE] < 0 or s.off[BLACK] < 0 then return false, "negative off count" end
    return true
end

return M
