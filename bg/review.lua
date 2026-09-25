-- Post-game analysis, framed so a player can actually learn from it.
--
-- For every turn it compares the turn played against the GNU net's best turn and
-- reports the change in *winning chances* (a percentage anyone understands),
-- not raw equity. Where the difference has a clear, reliable cause -- a hit the
-- player missed, or a point they passed up -- it says so in plain words.

local R = require("bg/rules")
local AI = require("bg/ai")

local Review = {}

local function buildState(before)
    local s = R.newState()
    for i = 1, 24 do s.points[i] = before.points[i] end
    s.bar[R.WHITE] = before.bw; s.bar[R.BLACK] = before.bb
    s.off[R.WHITE] = before.ow; s.off[R.BLACK] = before.ob
    return s
end

local function applyMoves(s, player, moves)
    local undo = { from = 0, to = 0, hit = false }
    for i = 1, #moves do R.applyMove(s, player, moves[i].from, moves[i].to, undo) end
end

-- move notation from the mover's own perspective (both count toward their 1 pt)
local function pointName(player, pt)
    if pt == R.BAR then return "bar" end
    if pt == R.OFF then return "off" end
    return tostring(player == R.WHITE and pt or (25 - pt))
end
local function notation(player, moves)
    if #moves == 0 then return "\u{2014}" end
    local parts = {}
    for i = 1, #moves do
        parts[i] = pointName(player, moves[i].from) .. "/" .. pointName(player, moves[i].to)
    end
    return table.concat(parts, " ")
end

-- player's winning chance (0..1) after their move (opponent is on roll next)
local function winAfter(s, player) return 1 - AI.positionWin(s, -player) end

-- set of points where `player` holds a made point (>= 2)
local function madePoints(s, player)
    local m = {}
    for i = 1, 24 do if R.countAt(s, i, player) >= 2 then m[i] = true end end
    return m
end

-- Why was the best turn better? Only returns a reason we can state reliably:
-- a hit the player missed, or a point they passed up. Otherwise nil.
local function reasonFor(before, player, actualState, bestState)
    local opp = -player
    if bestState.bar[opp] > actualState.bar[opp] then return "hit" end
    local was = madePoints(before, player)
    local ap, bp = madePoints(actualState, player), madePoints(bestState, player)
    for i = 1, 24 do
        if bp[i] and not ap[i] and not was[i] then return "point" end
    end
    return nil
end

-- Analyse the recorded turns. Returns a per-colour table:
--   { total, best (count matched), worst = { {n, drop, reason, actual, best} },
--     hits_missed, points_missed }
-- `drop` is the lost winning chance as a fraction (0..1).
function Review.analyse(history)
    local out = {
        [R.WHITE] = { total = 0, best = 0, worst = {}, hits_missed = 0, points_missed = 0 },
        [R.BLACK] = { total = 0, best = 0, worst = {}, hits_missed = 0, points_missed = 0 },
    }
    for _, t in ipairs(history) do
        local before = buildState(t.before)
        local actualState = buildState(t.before); applyMoves(actualState, t.player, t.moves)
        local best_moves = AI.chooseTurn(buildState(t.before), t.player, t.dice, t.ndice, 4)
        local bestState = buildState(t.before); applyMoves(bestState, t.player, best_moves)

        local drop = winAfter(bestState, t.player) - winAfter(actualState, t.player)
        if drop < 0 then drop = 0 end

        local p = out[t.player]
        p.total = p.total + 1        -- also this player's turn number
        if drop < 0.01 then
            p.best = p.best + 1
        else
            local reason
            if drop >= 0.02 then
                reason = reasonFor(before, t.player, actualState, bestState)
                if reason == "hit" then p.hits_missed = p.hits_missed + 1
                elseif reason == "point" then p.points_missed = p.points_missed + 1 end
            end
            p.worst[#p.worst + 1] = { n = p.total, drop = drop, reason = reason,
                actual = notation(t.player, t.moves), best = notation(t.player, best_moves) }
        end
    end
    for _, p in pairs(out) do
        table.sort(p.worst, function(a, b) return a.drop > b.drop end)
    end
    return out
end

return Review
