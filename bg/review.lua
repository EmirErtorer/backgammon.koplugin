-- Post-game analysis. Replays the recorded turns and, for each, compares the
-- turn actually played against the GNU net's best turn, reporting the equity
-- lost. Pure logic (no KOReader), so it can be tested headlessly.

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

-- move notation from the mover's own perspective: both players count toward
-- their own 1 point (White uses the board points as-is, Black mirrors them).
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

-- value to `player` after their move (the opponent is on roll next)
local function valueAfter(s, player)
    return -AI.positionValue(s, -player)
end

-- Analyse a game's turn history. Returns an array of per-turn results
-- { n, player, loss, actual, best } sorted worst-first, plus per-colour counts.
function Review.analyse(history)
    local turns, counts = {}, {
        [R.WHITE] = { blunder = 0, slip = 0 }, [R.BLACK] = { blunder = 0, slip = 0 } }
    for idx, t in ipairs(history) do
        local actualState = buildState(t.before)
        applyMoves(actualState, t.player, t.moves)
        local actual = valueAfter(actualState, t.player)

        local best_moves = AI.chooseTurn(buildState(t.before), t.player, t.dice, t.ndice, 4)
        local bestState = buildState(t.before)
        applyMoves(bestState, t.player, best_moves)
        local best = valueAfter(bestState, t.player)

        local loss = best - actual
        if loss < 0 then loss = 0 end
        if loss >= 0.08 then counts[t.player].blunder = counts[t.player].blunder + 1
        elseif loss >= 0.02 then counts[t.player].slip = counts[t.player].slip + 1 end

        turns[#turns + 1] = { n = idx, player = t.player, loss = loss,
                              actual = notation(t.player, t.moves),
                              best = notation(t.player, best_moves) }
    end
    table.sort(turns, function(a, b) return a.loss > b.loss end)
    return turns, counts
end

return Review
