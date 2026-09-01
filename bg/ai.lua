-- Computer opponent. Pure Lua, no KOReader dependencies, so it can be exercised
-- and calibrated headlessly.
--
-- Levels are data, not code: each entry says how deep to look (`ply`), which
-- position evaluator to use, and how often to deliberately play a non-best move
-- (`blunder`). The engine reads those fields generically, so adding a level is
-- adding a row here -- including the later 2-ply and neural-net (GNU) levels,
-- which only need a new evaluator or a higher `ply`.

local R = require("bg/rules")

local WHITE, BLACK, BAR, OFF = R.WHITE, R.BLACK, R.BAR, R.OFF

local AI = {}

--------------------------------------------------------------------------
-- evaluators: score a finished position from `me`'s point of view.
-- higher is better for `me`.
--------------------------------------------------------------------------

-- Pure race: only pip counts matter. Ignores safety entirely, so it happily
-- leaves blots all over the board -- deliberately weak.
local function evalPip(s, me)
    return R.pipCount(s, -me) - R.pipCount(s, me)
end

-- Count the opponent's hitting numbers against a blot `me` owns at point `bi`,
-- out of 36 rolls: direct shots (a checker exactly d away, d in 1..6) and
-- combined shots (d1+d2 away with an open landing point in between). A rough
-- but faithful "how exposed is this blot" measure.
local function shotsAgainst(s, me, bi)
    local opp = -me
    -- distance an opponent checker at `j` must travel to reach `bi`
    local function dist(j)
        if opp == WHITE then           -- WHITE moves high -> low
            return (j > bi) and (j - bi) or nil
        else                            -- BLACK moves low -> high
            return (j < bi) and (bi - j) or nil
        end
    end
    -- is `pt` open for the opponent to land on (empty, theirs, or our blot)?
    local function oppOpen(pt)
        if pt < 1 or pt > 24 then return false end
        return R.isOpen(s, pt, opp)
    end

    local direct = {}      -- direct[d] = true if a single die of d hits
    local combo = {}       -- combo[d1][d2]
    for i = 1, 24 do
        if R.countAt(s, i, opp) > 0 then
            local d = dist(i)
            if d and d >= 1 and d <= 6 then direct[d] = true end
            if d and d >= 2 and d <= 12 then
                -- two-die path: split d into a+b, landing at the midpoint
                for a = 1, 6 do
                    local b = d - a
                    if b >= 1 and b <= 6 then
                        local mid = (opp == WHITE) and (i - a) or (i + a)
                        if oppOpen(mid) then
                            combo[a] = combo[a] or {}
                            combo[a][b] = true
                        end
                    end
                end
            end
        end
    end

    local hits = 0
    for d1 = 1, 6 do
        for d2 = 1, 6 do
            local hit = direct[d1] or direct[d2]
            if not hit and combo[d1] and combo[d1][d2] then hit = true end
            if not hit and d1 == d2 then
                -- doubles reach with repeated pips too
                if direct[d1] then hit = true end
            end
            if hit then hits = hits + 1 end
        end
    end
    return hits
end

-- Positional evaluation: race, plus safety and structure. Good enough to play a
-- sensible game and clearly stronger than the race-only evaluator.
local function evalPositional(s, me)
    local opp = -me
    local score = 0

    -- race
    score = score + (R.pipCount(s, opp) - R.pipCount(s, me))

    -- material off and on the bar
    score = score + (s.off[me] - s.off[opp]) * 18
    score = score - s.bar[me] * 20 + s.bar[opp] * 14

    local lo, hi = R.homeRange(me)          -- my home board
    local olo, ohi = R.homeRange(opp)       -- opponent's home board

    for i = 1, 24 do
        local n = R.countAt(s, i, me)
        if n >= 2 then
            -- a made point is good, more so inside my home board (priming/blocking)
            score = score + 4
            if i >= lo and i <= hi then score = score + 6 end
            -- holding an anchor in the opponent's home board is valuable
            if i >= olo and i <= ohi then score = score + 5 end
            if n >= 4 then score = score - (n - 3) * 3 end   -- stacking is wasteful
        elseif n == 1 then
            -- a blot is a liability in proportion to how easily it is hit
            score = score - shotsAgainst(s, me, i) * 1.1
        end
    end

    -- reward consecutive made points (a prime is hard to escape)
    local run = 0
    for i = lo, hi do
        if R.countAt(s, i, me) >= 2 then
            run = run + 1
            if run >= 2 then score = score + run * 2 end
        else
            run = 0
        end
    end

    return score
end

AI.evaluators = {
    pip = evalPip,
    positional = evalPositional,
}

--------------------------------------------------------------------------
-- level registry (data-driven; add a row to add a level)
--------------------------------------------------------------------------

AI.levels = {
    { id = 1, name = "Beginner", desc = "Loose play, leaves easy shots",
      ply = 1, eval = "pip",        blunder = 0.55 },
    { id = 2, name = "Casual",   desc = "Plays safe, punishes blots",
      ply = 1, eval = "positional", blunder = 0.10 },
    -- planned, not yet enabled:
    -- { id = 3, name = "Skilled",  ply = 2, eval = "positional", blunder = 0.0 },
    -- { id = 4, name = "Expert",   ply = 1, eval = "gnu",        blunder = 0.0 },
    -- { id = 5, name = "Master",   ply = 2, eval = "gnu",        blunder = 0.0 },
}

function AI.level(id)
    for _, lv in ipairs(AI.levels) do
        if lv.id == id then return lv end
    end
    return nil
end

function AI.maxLevel()
    local m = 0
    for _, lv in ipairs(AI.levels) do if lv.id > m then m = lv.id end end
    return m
end

--------------------------------------------------------------------------
-- full-turn enumeration
--------------------------------------------------------------------------

-- Working buffers, allocated once. The AI thinks once per turn, not per frame,
-- so this is not a hot path, but there is no reason to churn the heap either.
local src_stack = {}          -- one source list per search depth
for i = 1, 5 do src_stack[i] = {} end
local move_stack = { {}, {}, {} }
for i = 1, 4 do move_stack[i] = { from = 0, to = 0 } end
local undo_stack = {}
for i = 1, 4 do undo_stack[i] = { from = 0, to = 0, hit = false } end
local used = { false, false, false, false }

local function listSources(s, player, buf)
    if s.bar[player] > 0 then
        buf[1] = BAR
        return 1
    end
    local n = 0
    for i = 1, 24 do
        if R.countAt(s, i, player) > 0 then
            n = n + 1
            buf[n] = i
        end
    end
    return n
end

local function positionKey(s)
    -- compact enough to dedup terminal positions within one turn
    local parts = {}
    for i = 1, 24 do parts[i] = s.points[i] end
    parts[25] = "b" .. s.bar[WHITE] .. "," .. s.bar[BLACK]
    parts[26] = "o" .. s.off[WHITE] .. "," .. s.off[BLACK]
    return table.concat(parts, ".")
end

-- Depth-first walk of every legal sequence of length `target`, recording the
-- resulting position (deduped) and the moves that reach it. `seen`/`out` are
-- caller-provided and reused.
local function walk(s, player, dice, ndice, depth, target, seen, out)
    if depth > target then return end
    if depth == target then
        local key = positionKey(s)
        if not seen[key] then
            seen[key] = true
            local moves = {}
            for i = 1, target do
                moves[i] = { from = move_stack[i].from, to = move_stack[i].to }
            end
            out[#out + 1] = { key = key, moves = moves, first_die = move_stack[1].die }
        end
        return
    end

    local buf = src_stack[depth + 1]
    local nsrc = listSources(s, player, buf)
    for di = 1, ndice do
        if not used[di] then
            local die = dice[di]
            local dup = false
            for dj = 1, di - 1 do
                if not used[dj] and dice[dj] == die then dup = true break end
            end
            if not dup then
                used[di] = true
                for k = 1, nsrc do
                    local from = buf[k]
                    local to = R.destination(s, player, from, die)
                    if to then
                        local u = undo_stack[depth + 1]
                        R.applyMove(s, player, from, to, u)
                        move_stack[depth + 1].from = from
                        move_stack[depth + 1].to = to
                        move_stack[depth + 1].die = die
                        walk(s, player, dice, ndice, depth + 1, target, seen, out)
                        R.undoMove(s, player, u)
                    end
                end
                used[di] = false
            end
        end
    end
end

-- Every maximal legal turn from this position, as a list of
-- { moves = {{from,to},...}, first_die = n }. Empty when there is no move.
function AI.enumerateTurns(s, player, dice, ndice)
    local r = R.analyse(s, player, dice, ndice)
    local target = r.max_depth
    local out = {}
    if target == 0 then return out end

    for i = 1, 4 do used[i] = false end
    local seen = {}
    walk(s, player, dice, ndice, 0, target, seen, out)

    -- the higher-die rule: if only one die can be played and the two differ,
    -- keep only turns that use the higher one (mirrors rules.analyse)
    if target == 1 and ndice == 2 and dice[1] ~= dice[2] then
        local hi = dice[1] > dice[2] and dice[1] or dice[2]
        local any = false
        for _, t in ipairs(out) do if t.first_die == hi then any = true break end end
        if any then
            local kept = {}
            for _, t in ipairs(out) do
                if t.first_die == hi then kept[#kept + 1] = t end
            end
            out = kept
        end
    end
    return out
end

--------------------------------------------------------------------------
-- choosing a turn
--------------------------------------------------------------------------

-- Score a candidate turn by applying it, evaluating, then undoing.
local score_undo = {}
for i = 1, 4 do score_undo[i] = { from = 0, to = 0, hit = false } end

local function scoreTurn(s, player, moves, evaluator)
    for i = 1, #moves do
        R.applyMove(s, player, moves[i].from, moves[i].to, score_undo[i])
    end
    local v = evaluator(s, player)
    for i = #moves, 1, -1 do
        R.undoMove(s, player, score_undo[i])
    end
    return v
end

--- Pick the turn the computer will play.
-- @return array of { from, to } moves (empty if the player has no legal move)
function AI.chooseTurn(s, player, dice, ndice, level_id)
    local lv = AI.level(level_id) or AI.levels[1]
    local evaluator = AI.evaluators[lv.eval] or evalPip

    local turns = AI.enumerateTurns(s, player, dice, ndice)
    if #turns == 0 then return {} end
    if #turns == 1 then return turns[1].moves end

    -- deliberate weak play: sometimes ignore the evaluation and pick at random
    if lv.blunder and lv.blunder > 0 and math.random() < lv.blunder then
        return turns[math.random(#turns)].moves
    end

    local best, best_score = turns[1], scoreTurn(s, player, turns[1].moves, evaluator)
    for i = 2, #turns do
        local v = scoreTurn(s, player, turns[i].moves, evaluator)
        if v > best_score then
            best, best_score = turns[i], v
        end
    end
    return best.moves
end

return AI
