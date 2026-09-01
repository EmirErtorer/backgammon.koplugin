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
    { id = 3, name = "Skilled",  desc = "Looks a roll ahead, plays the odds",
      ply = 2, eval = "positional", blunder = 0.0 },
    { id = 4, name = "Expert",   desc = "GNU neural net, world-class judgement",
      ply = 1, eval = "gnu", blunder = 0.0 },
    { id = 5, name = "Master",   desc = "GNU neural net, looks a roll ahead",
      ply = 2, eval = "gnu", blunder = 0.0 },
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

local function chooseTurn1ply(s, player, turns, evaluator)
    local best, best_score = turns[1], scoreTurn(s, player, turns[1].moves, evaluator)
    for i = 2, #turns do
        local v = scoreTurn(s, player, turns[i].moves, evaluator)
        if v > best_score then
            best, best_score = turns[i], v
        end
    end
    return best.moves
end

--------------------------------------------------------------------------
-- 2-ply search: value a candidate by the opponent's best reply, averaged over
-- every roll they might make. Twice as expensive per level of look-ahead, so a
-- move filter keeps only the most promising candidates before looking deeper --
-- the same idea gnubg uses.
--------------------------------------------------------------------------

-- The 21 distinct dice combinations, with the weight each carries out of 36
-- (doubles happen one way, other rolls two). Doubles give four dice to play.
local ROLLS = {}
for a = 1, 6 do
    for b = a, 6 do
        ROLLS[#ROLLS + 1] = { a, b, (a == b) and 4 or 2, (a == b) and 1 or 2 }
    end
end

-- separate undo buffers per search layer, so applying the candidate and the
-- opponent's reply never share scratch space
local cand_undo = {}
for i = 1, 4 do cand_undo[i] = { from = 0, to = 0, hit = false } end
local reply_undo = {}
for i = 1, 4 do reply_undo[i] = { from = 0, to = 0, hit = false } end
local roll_dice = { 0, 0, 0, 0 }

local PLY2_WIN = 1e6      -- a move that wins outright dominates any evaluation

-- Expected value to `me` of a position where the opponent rolls next: for each
-- roll, the opponent plays the reply that is worst for `me`; average over rolls.
local function opponentReplyValue(s, me, evaluator)
    local opp = -me
    local total, wsum = 0, 0
    for ri = 1, #ROLLS do
        local rc = ROLLS[ri]
        local a, b, ndice, w = rc[1], rc[2], rc[3], rc[4]
        if ndice == 4 then
            roll_dice[1], roll_dice[2], roll_dice[3], roll_dice[4] = a, a, a, a
        else
            roll_dice[1], roll_dice[2] = a, b
        end
        local replies = AI.enumerateTurns(s, opp, roll_dice, ndice)
        local worst           -- min over replies of eval(.., me)
        if #replies == 0 then
            worst = evaluator(s, me)          -- opponent is stuck, no move
        else
            for i = 1, #replies do
                local mv = replies[i].moves
                for j = 1, #mv do
                    R.applyMove(s, opp, mv[j].from, mv[j].to, reply_undo[j])
                end
                local v = (R.winner(s) == opp) and -PLY2_WIN or evaluator(s, me)
                for j = #mv, 1, -1 do
                    R.undoMove(s, opp, reply_undo[j])
                end
                if not worst or v < worst then worst = v end
            end
        end
        total = total + worst * w
        wsum = wsum + w
    end
    return total / wsum
end

local function chooseTurn2ply(s, player, turns, evaluator)
    if #turns == 1 then return turns[1].moves end

    -- 1-ply screen: rank every candidate, keep the strongest few
    local scored = {}
    for i = 1, #turns do
        scored[i] = { t = turns[i], v = scoreTurn(s, player, turns[i].moves, evaluator) }
    end
    table.sort(scored, function(x, y) return x.v > y.v end)
    local keep = math.min(8, #scored)

    -- look a full roll ahead for the survivors
    local best, best_v
    for i = 1, keep do
        local mv = scored[i].t.moves
        for j = 1, #mv do
            R.applyMove(s, player, mv[j].from, mv[j].to, cand_undo[j])
        end
        local v = (R.winner(s) == player) and PLY2_WIN
                  or opponentReplyValue(s, player, evaluator)
        for j = #mv, 1, -1 do
            R.undoMove(s, player, cand_undo[j])
        end
        if not best_v or v > best_v then best, best_v = scored[i].t, v end
    end
    return best.moves
end

--------------------------------------------------------------------------
-- GNU neural-net levels (4 and 5). The net's equity is turn-dependent (it
-- bakes in the on-roll advantage), unlike the static heuristic, so these need
-- their own search that tracks whose roll it is at each leaf.
--------------------------------------------------------------------------

local GNU = require("bg/gnu")
local gnu_nets

-- convert engine state to gnubg's board, with `me` on roll (anBoard[1]).
-- reuses buffers so the search stays allocation-free.
local gnuBoard = { [0] = {}, [1] = {} }
local function toGnu(s, me)
    local b0, b1 = gnuBoard[0], gnuBoard[1]
    for k = 0, 24 do b0[k] = 0; b1[k] = 0 end
    local pts = s.points
    for p = 1, 24 do
        local v = pts[p]
        if v > 0 then                       -- WHITE checkers: index p-1
            gnuBoard[(me == WHITE) and 1 or 0][p - 1] = v
        elseif v < 0 then                   -- BLACK checkers: index 24-p
            gnuBoard[(me == BLACK) and 1 or 0][24 - p] = -v
        end
    end
    gnuBoard[(me == WHITE) and 1 or 0][24] = s.bar[WHITE]
    gnuBoard[(me == BLACK) and 1 or 0][24] = s.bar[BLACK]
    return gnuBoard
end

-- value of position `s` to `side`, assuming `side` is on roll. Terminal
-- positions dominate so a winning move is always taken over a non-winning one.
local function gnuValue(s, side)
    local w = R.winner(s)
    if w == side then return 3.0 end
    if w == -side then return -3.0 end
    return GNU.equity(toGnu(s, side), gnu_nets) or 0.0
end

-- The opponent typically has ~15 legal replies per roll; net-evaluating all of
-- them at 2-ply is too slow on a device. So we screen replies with the fast
-- positional heuristic and only net-evaluate the opponent's most promising few
-- (the ones best for the opponent). gnubg uses the same move-filter idea.
local GNU_OPP_KEEP = 8
local rep_scored = {}

-- expected value to `player` after its move: average over the opponent's 21
-- rolls of the reply that is worst for `player` (opponent then, us next).
local function opponentReplyValueGNU(s, player)
    local opp = -player
    local total, wsum = 0, 0
    for ri = 1, #ROLLS do
        local rc = ROLLS[ri]
        local a, b, ndice, w = rc[1], rc[2], rc[3], rc[4]
        if ndice == 4 then
            roll_dice[1], roll_dice[2], roll_dice[3], roll_dice[4] = a, a, a, a
        else
            roll_dice[1], roll_dice[2] = a, b
        end
        local replies = AI.enumerateTurns(s, opp, roll_dice, ndice)
        local nrep = #replies
        local worst
        if nrep == 0 then
            worst = gnuValue(s, player)          -- opponent stuck, our roll next
        else
            -- pick which replies to net-evaluate: all of them, or the top few
            -- by a quick heuristic screen (best for the opponent)
            local pick, npick = replies, nrep
            if nrep > GNU_OPP_KEEP then
                for i = 1, nrep do
                    local mv = replies[i].moves
                    for j = 1, #mv do R.applyMove(s, opp, mv[j].from, mv[j].to, reply_undo[j]) end
                    rep_scored[i] = { t = replies[i], v = evalPositional(s, opp) }
                    for j = #mv, 1, -1 do R.undoMove(s, opp, reply_undo[j]) end
                end
                for i = nrep + 1, #rep_scored do rep_scored[i] = nil end
                table.sort(rep_scored, function(x, y) return x.v > y.v end)
                pick, npick = rep_scored, GNU_OPP_KEEP
            end
            for i = 1, npick do
                local mv = (pick == replies) and pick[i].moves or pick[i].t.moves
                for j = 1, #mv do R.applyMove(s, opp, mv[j].from, mv[j].to, reply_undo[j]) end
                local v = gnuValue(s, player)    -- our roll next; opponent minimises this
                for j = #mv, 1, -1 do R.undoMove(s, opp, reply_undo[j]) end
                if not worst or v < worst then worst = v end
            end
        end
        total = total + worst * w
        wsum = wsum + w
    end
    return total / wsum
end

local function chooseTurnGNU(s, player, turns, ply)
    if #turns == 1 then return turns[1].moves end
    local opp = -player

    -- 1-ply value of each candidate: after our move the opponent is on roll,
    -- so our value is minus the opponent's equity there
    local scored = {}
    for i = 1, #turns do
        local mv = turns[i].moves
        for j = 1, #mv do R.applyMove(s, player, mv[j].from, mv[j].to, cand_undo[j]) end
        local v = (R.winner(s) == player) and 3.0 or -gnuValue(s, opp)
        for j = #mv, 1, -1 do R.undoMove(s, player, cand_undo[j]) end
        scored[i] = { t = turns[i], v = v }
    end

    if (ply or 1) < 2 then
        local best = scored[1]
        for i = 2, #scored do if scored[i].v > best.v then best = scored[i] end end
        return best.t.moves
    end

    -- 2-ply: look a full roll ahead for the strongest handful
    table.sort(scored, function(x, y) return x.v > y.v end)
    local keep = math.min(8, #scored)
    local best, best_v
    for i = 1, keep do
        local mv = scored[i].t.moves
        for j = 1, #mv do R.applyMove(s, player, mv[j].from, mv[j].to, cand_undo[j]) end
        local v = (R.winner(s) == player) and 3.0 or opponentReplyValueGNU(s, player)
        for j = #mv, 1, -1 do R.undoMove(s, player, cand_undo[j]) end
        if not best_v or v > best_v then best, best_v = scored[i].t, v end
    end
    return best.moves
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

    if lv.eval == "gnu" then
        gnu_nets = gnu_nets or GNU.load()
        return chooseTurnGNU(s, player, turns, lv.ply or 1)
    end
    if (lv.ply or 1) >= 2 then
        return chooseTurn2ply(s, player, turns, evaluator)
    end
    return chooseTurn1ply(s, player, turns, evaluator)
end

-- Let a caller supply pre-loaded nets (e.g. a test), else GNU.load() is used.
function AI.setGnuNets(nets) gnu_nets = nets end

return AI
