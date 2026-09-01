-- Headless tests for the rules engine. Run with:
--   luajit tests/run.lua
-- from the plugin directory. Needs no KOReader.

package.path = "./?.lua;" .. package.path

local R = require("bg/rules")

local WHITE, BLACK, BAR, OFF = R.WHITE, R.BLACK, R.BAR, R.OFF

local failures, checks = 0, 0
local function ok(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. what)
    end
end
local function eq(got, want, what)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(("FAIL: %s (got %s, want %s)"):format(what, tostring(got), tostring(want)))
    end
end

-- Build a position from a sparse table of point -> signed count.
local function pos(spec)
    local s = R.newState()
    for k, v in pairs(spec) do
        if k == "bar_w" then s.bar[WHITE] = v
        elseif k == "bar_b" then s.bar[BLACK] = v
        elseif k == "off_w" then s.off[WHITE] = v
        elseif k == "off_b" then s.off[BLACK] = v
        else s.points[k] = v end
    end
    return s
end

local function movesOf(s, player, ...)
    local dice = { ... }
    local r = R.analyse(s, player, dice, #dice)
    local list = {}
    for i = 1, r.n do
        list[#list + 1] = ("%s>%s/%d"):format(
            r.from[i] == BAR and "bar" or tostring(r.from[i]),
            r.to[i] == OFF and "off" or tostring(r.to[i]),
            r.die[i])
    end
    table.sort(list)
    return table.concat(list, " "), r
end

local function has(str, needle)
    return str:find(needle, 1, true) ~= nil
end

--------------------------------------------------------------------------
print("-- opening position")
--------------------------------------------------------------------------
do
    local s = R.setupStart(R.newState())
    ok(R.check(s), "opening position passes invariants")
    eq(R.pipCount(s, WHITE), 167, "white opening pip count")
    eq(R.pipCount(s, BLACK), 167, "black opening pip count")
    eq(R.canBearOff(s, WHITE), false, "cannot bear off at the start")

    local str = movesOf(s, WHITE, 3, 1)
    ok(has(str, "8>5/3"), "white 3 from the 8 point")
    ok(has(str, "6>5/1"), "white 1 from the 6 point")
    ok(has(str, "24>23/1"), "white 1 from the 24 point onto the empty 23")
end

--------------------------------------------------------------------------
print("-- blocked points and hitting")
--------------------------------------------------------------------------
do
    -- white on 10, black owns 8 with two checkers, 9 holds one black blot
    local s = pos{ [10] = 1, [9] = -1, [8] = -2, [1] = -12, [24] = 14 }
    local str = movesOf(s, WHITE, 1, 2)
    ok(has(str, "10>9/1"), "may land on a blot")
    ok(not has(str, "10>8/2"), "may not land on a point held by two enemies")

    -- hitting sends the blot to the bar
    local undo = {}
    R.applyMove(s, WHITE, 10, 9, undo)
    eq(s.bar[BLACK], 1, "hit sends the checker to the bar")
    eq(s.points[9], 1, "hitter occupies the point")
    R.undoMove(s, WHITE, undo)
    eq(s.bar[BLACK], 0, "undo restores the bar")
    eq(s.points[9], -1, "undo restores the blot")
    ok(R.check(s), "invariants hold after apply/undo")
end

--------------------------------------------------------------------------
print("-- entering from the bar")
--------------------------------------------------------------------------
do
    -- White enters on 25-die. Black owns 24, 23 and 22; 21 is open.
    local s = pos{ bar_w = 1, [24] = -2, [23] = -2, [22] = -2, [21] = 0,
                   [1] = -9, [10] = 14 }
    local str = movesOf(s, WHITE, 1, 4)
    ok(not has(str, "bar>24/1"), "cannot enter onto a blocked point")
    ok(has(str, "bar>21/4"), "enters on the open point")
    ok(not has(str, "10>"), "no other move while a checker sits on the bar")

    -- fully blocked home board: no move at all, turn passes
    local s2 = pos{ bar_w = 1, [24] = -2, [23] = -2, [22] = -2, [21] = -2,
                    [20] = -2, [19] = -2, [1] = -3, [10] = 14 }
    local _, r2 = movesOf(s2, WHITE, 1, 6)
    eq(r2.n, 0, "no legal move when every entry point is blocked")
    eq(r2.max_depth, 0, "max depth is zero when nothing can be played")

    -- two on the bar: both must enter before anything else
    local s3 = pos{ bar_w = 2, [21] = 0, [1] = -13, [10] = 13 }
    local str3 = movesOf(s3, WHITE, 4, 4)
    ok(has(str3, "bar>21/4"), "first checker enters")
    ok(not has(str3, "10>"), "cannot move elsewhere with a checker still on the bar")
end

--------------------------------------------------------------------------
print("-- must play both dice, and the higher one when only one fits")
--------------------------------------------------------------------------
do
    -- These positions give white exactly one mobile checker, with the other
    -- fourteen already borne off, so nothing else can supply a legal move and
    -- the sequence length is entirely determined by the blockers.

    -- 13-1=12 open, then 12-5=7 open, so both dice can be played.
    local s = pos{ [13] = 1, off_w = 14, [8] = -2, [1] = -13 }
    local _, r = movesOf(s, WHITE, 1, 5)
    eq(r.max_depth, 2, "both dice are playable")

    -- Block the follow ups: 13-5=8 is blocked and 12-5=7 is blocked, so after
    -- the 1 there is nothing left. Only one die can ever be played.
    local s2 = pos{ [13] = 1, off_w = 14, [8] = -2, [7] = -2, [1] = -11 }
    local str2, r2 = movesOf(s2, WHITE, 1, 5)
    eq(r2.max_depth, 1, "only one die can be played")
    ok(has(str2, "13>12/1"), "the playable die is offered")

    -- Higher die rule: 13-1=12 and 13-4=9 are both open, but from either one
    -- the other die lands on the blocked 8. Neither leads anywhere, so the
    -- higher die must be the one played.
    local s3 = pos{ [13] = 1, off_w = 14, [8] = -2, [1] = -13 }
    local str3, r3 = movesOf(s3, WHITE, 1, 4)
    eq(r3.max_depth, 1, "neither die leaves a follow up")
    ok(has(str3, "13>9/4"), "the higher die is offered")
    ok(not has(str3, "13>12/1"), "the lower die is withheld when the higher is legal")
end

--------------------------------------------------------------------------
print("-- doubles give four moves")
--------------------------------------------------------------------------
do
    local s = pos{ [24] = 4, [1] = -11, [13] = 11, [20] = -4 }
    local _, r = movesOf(s, WHITE, 2, 2, 2, 2)
    eq(r.max_depth, 4, "a double allows four moves")
end

--------------------------------------------------------------------------
print("-- bearing off")
--------------------------------------------------------------------------
do
    -- all fifteen home
    local s = pos{ [6] = 2, [5] = 3, [4] = 3, [3] = 3, [2] = 2, [1] = 2,
                   [24] = -15 }
    eq(R.canBearOff(s, WHITE), true, "all checkers home means bearing off is allowed")
    local str = movesOf(s, WHITE, 6, 3)
    ok(has(str, "6>off/6"), "exact roll bears off")
    ok(has(str, "3>off/3"), "exact roll bears off from the 3 point")

    -- a higher roll than the highest occupied point bears off from it
    local s2 = pos{ [4] = 2, [2] = 2, [24] = -15, [1] = 11 }
    local str2 = movesOf(s2, WHITE, 6, 6, 6, 6)
    ok(has(str2, "4>off/6"), "a 6 bears off from the highest occupied point")

    -- but not while checkers sit behind it
    local s3 = pos{ [6] = 1, [4] = 2, [24] = -15, [1] = 12 }
    local str3 = movesOf(s3, WHITE, 5, 5, 5, 5)
    ok(not has(str3, "4>off/5"), "cannot bear off from 4 with a 5 while the 6 point is occupied")
    ok(has(str3, "6>1/5"), "the 5 must be played as an ordinary move instead")

    -- a checker on the bar stops bearing off entirely
    local s4 = pos{ bar_w = 1, [6] = 2, [5] = 3, [4] = 3, [3] = 3, [2] = 2,
                    [1] = 1, [24] = -15 }
    eq(R.canBearOff(s4, WHITE), false, "a checker on the bar blocks bearing off")
end

--------------------------------------------------------------------------
print("-- scoring")
--------------------------------------------------------------------------
do
    local s = pos{ off_w = 15, off_b = 3, [24] = -12 }
    eq(R.winner(s), WHITE, "white has borne off fifteen")
    eq(R.scoreFor(s, WHITE), 1, "normal win is one point")

    local s2 = pos{ off_w = 15, off_b = 0, [24] = -15 }
    eq(R.scoreFor(s2, WHITE), 2, "mars is two points when the loser is clear of the winner's home")

    local s3 = pos{ off_w = 15, off_b = 0, [3] = -1, [24] = -14 }
    eq(R.scoreFor(s3, WHITE), 3, "three points with an enemy checker in the winner's home board")

    local s4 = pos{ off_w = 15, off_b = 0, bar_b = 1, [24] = -14 }
    eq(R.scoreFor(s4, WHITE), 3, "a checker on the bar counts as being in the winner's home")

    local s5 = pos{ off_b = 15, off_w = 0, [22] = 1, [1] = 14 }
    eq(R.winner(s5), BLACK, "black can win too")
    eq(R.scoreFor(s5, BLACK), 3, "three points for black, mirrored")
end

--------------------------------------------------------------------------
print("-- random games to completion")
--------------------------------------------------------------------------
do
    math.randomseed(20260901)

    local GAMES = tonumber(os.getenv("GAMES")) or 3000
    local dice = {}
    local undo = {}
    local total_moves, total_turns = 0, 0
    local score_counts = { 0, 0, 0 }
    local max_turns_seen = 0
    local bad = 0

    local t0 = os.clock()
    for g = 1, GAMES do
        local s = R.setupStart(R.newState())
        local player = (math.random(2) == 1) and WHITE or BLACK
        local turns = 0

        while not R.winner(s) do
            turns = turns + 1
            if turns > 2000 then
                bad = bad + 1
                print("FAIL: game " .. g .. " did not terminate")
                break
            end

            local d1, d2 = math.random(6), math.random(6)
            local n
            if d1 == d2 then
                dice[1], dice[2], dice[3], dice[4] = d1, d1, d1, d1
                n = 4
            else
                dice[1], dice[2] = d1, d2
                n = 2
            end

            while n > 0 do
                local r = R.analyse(s, player, dice, n)
                if r.n == 0 then break end
                local pick = math.random(r.n)
                local from, to, die = r.from[pick], r.to[pick], r.die[pick]

                R.applyMove(s, player, from, to, undo)
                total_moves = total_moves + 1

                local good, why = R.check(s)
                if not good then
                    bad = bad + 1
                    print("FAIL: invariant broken in game " .. g .. ": " .. tostring(why))
                    break
                end
                -- no point may hold both colours: guaranteed by the sign
                -- representation, but check the counts stay sane
                for i = 1, 24 do
                    local v = s.points[i]
                    if v > 15 or v < -15 then
                        bad = bad + 1
                        print("FAIL: impossible stack of " .. v .. " on point " .. i)
                        break
                    end
                end

                -- consume the die that made this move legal
                local removed = false
                for i = 1, n do
                    if dice[i] == die then
                        dice[i] = dice[n]
                        n = n - 1
                        removed = true
                        break
                    end
                end
                if not removed then
                    bad = bad + 1
                    print("FAIL: move reported a die that was not available")
                    break
                end

                if R.winner(s) then break end
            end

            total_turns = total_turns + 1
            player = -player
        end

        if turns > max_turns_seen then max_turns_seen = turns end

        local w = R.winner(s)
        if w then
            local sc = R.scoreFor(s, w)
            if sc < 1 or sc > 3 then
                bad = bad + 1
                print("FAIL: score out of range: " .. tostring(sc))
            else
                score_counts[sc] = score_counts[sc] + 1
                -- cross check the score against the final position
                local loser = -w
                if sc == 1 and s.off[loser] == 0 then
                    bad = bad + 1
                    print("FAIL: scored 1 but the loser bore off nothing")
                end
                if sc >= 2 and s.off[loser] > 0 then
                    bad = bad + 1
                    print("FAIL: scored " .. sc .. " but the loser bore off checkers")
                end
            end
        else
            bad = bad + 1
            print("FAIL: game ended with no winner")
        end
    end
    local elapsed = os.clock() - t0

    ok(bad == 0, "no invariant violations across " .. GAMES .. " games")
    print(("   %d games, %d turns, %d moves in %.2fs (%.0f moves/sec)")
        :format(GAMES, total_turns, total_moves, elapsed, total_moves / elapsed))
    print(("   longest game %d turns; wins by score: 1pt=%d 2pt=%d 3pt=%d")
        :format(max_turns_seen, score_counts[1], score_counts[2], score_counts[3]))
end

--------------------------------------------------------------------------
print("-- allocation behaviour")
--------------------------------------------------------------------------
do
    local s = R.setupStart(R.newState())
    local dice = { 6, 5 }
    R.analyse(s, WHITE, dice, 2)      -- warm up
    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 20000 do
        R.analyse(s, WHITE, dice, 2)
    end
    local after = collectgarbage("count")
    local grew = after - before
    ok(grew < 16, ("analyse() allocates almost nothing: heap grew %.1f KB over 20000 calls"):format(grew))
    print(("   heap grew %.1f KB over 20000 analyse() calls"):format(grew))

    local dice4 = { 6, 6, 6, 6 }
    R.analyse(s, WHITE, dice4, 4)
    collectgarbage("collect")
    before = collectgarbage("count")
    local t0 = os.clock()
    for _ = 1, 5000 do
        R.analyse(s, WHITE, dice4, 4)
    end
    local el = os.clock() - t0
    after = collectgarbage("count")
    print(("   doubles: %.1f KB over 5000 calls, %.3f ms per call"):format(after - before, el * 1000 / 5000))
end

--------------------------------------------------------------------------
print("-- full games through the Game API")
--------------------------------------------------------------------------
do
    local G = require("bg/game")
    -- dice.lua seeds itself from the clock on first use, so claim the seed
    -- first and then set our own, or this test is not reproducible
    require("bg/dice").seed()
    math.randomseed(4242)

    local GAMES = tonumber(os.getenv("APIGAMES")) or 300
    local g = G.new()
    local bad = 0
    local moves, passes = 0, 0


    for n = 1, GAMES do
        g:newGame()
        -- decide who starts
        local guard = 0
        while g.phase == "opening" do
            g:openingRoll()
            guard = guard + 1
            if guard > 200 then bad = bad + 1 print("FAIL: opening roll never resolved") break end
        end

        local turns = 0
        while g.phase ~= "over" do
            turns = turns + 1
            if turns > 2000 then bad = bad + 1 print("FAIL: game " .. n .. " ran away") break end

            if g.phase == "roll" then
                local what = g:roll()
                if what == "pass" then
                    passes = passes + 1
                    if g.message ~= "No legal move" then
                        bad = bad + 1
                        print("FAIL: dead roll did not set a message")
                    end
                    g:passTurn()
                end
            elseif g.phase == "move" then
                if g.legal_n == 0 then
                    g:passTurn()
                else
                    -- pick a legal source, then one of its destinations, the
                    -- same way a tap on the board would
                    local pick = math.random(g.legal_n)
                    local from = g.legal_from[pick]
                    if not g:select(from) then
                        bad = bad + 1
                        print("FAIL: a legal source could not be selected")
                        break
                    end
                    local d = g.dests[math.random(g.dests_n)]
                    if not g:isDestination(d) then
                        bad = bad + 1
                        print("FAIL: destination list disagrees with isDestination")
                    end
                    local res = g:move(d)
                    if res == nil then
                        bad = bad + 1
                        print("FAIL: a move produced from the legal list was rejected")
                        break
                    end
                    moves = moves + 1
                    local good, why = R.check(g.state)
                    if not good then
                        bad = bad + 1
                        print("FAIL: invariant broken: " .. tostring(why))
                        break
                    end
                    if res == "turn_over" then g:passTurn() end
                end
            end
        end

        if g.phase == "over" then
            if not (g.win_points >= 1 and g.win_points <= 3) then
                bad = bad + 1
                print("FAIL: bad win value " .. tostring(g.win_points))
            end
        end

    end

    ok(bad == 0, "no failures across " .. GAMES .. " games driven through the Game API")
    ok(g.score[WHITE] + g.score[BLACK] > 0, "the scoreboard accumulated points")
    print(("   %d games, %d moves, %d dead rolls; score %d-%d over %d games")
        :format(GAMES, moves, passes, g.score[WHITE], g.score[BLACK], g.games))
end

--------------------------------------------------------------------------
print("-- allocation across a long match")
--------------------------------------------------------------------------
do
    -- collectgarbage("count") also counts LuaJIT's compiled traces, which grow
    -- and get flushed in a sawtooth worth hundreds of KB. That swamps the few
    -- bytes we are actually looking for, so measure with the JIT off: what is
    -- left is Lua data and nothing else.
    local had_jit = jit ~= nil
    if had_jit then jit.off() end

    local G = require("bg/game")
    require("bg/dice").seed()
    math.randomseed(1234)
    local g = G.new()

    local function playGame()
        g:newGame()
        while g.phase == "opening" do g:openingRoll() end
        local turns = 0
        while g.phase ~= "over" and turns < 2000 do
            turns = turns + 1
            if g.phase == "roll" then
                if g:roll() == "pass" then g:passTurn() end
            elseif g.legal_n == 0 then
                g:passTurn()
            else
                g:select(g.legal_from[math.random(g.legal_n)])
                if g:move(g.dests[math.random(g.dests_n)]) == "turn_over" then
                    g:passTurn()
                end
            end
        end
    end

    local function heap()
        for _ = 1, 4 do collectgarbage("collect") end
        return collectgarbage("count")
    end

    for _ = 1, 40 do playGame() end     -- let the arrays reach their full size
    local base = heap()
    for _ = 1, 400 do playGame() end
    local after = heap()
    local drift = after - base

    if had_jit then jit.on() end

    ok(math.abs(drift) < 8,
       ("a 400 game match does not grow the heap: %.1f KB"):format(drift))
    print(("   heap after warm up %.0f KB, after 400 more games %.0f KB (%+.1f KB)")
        :format(base, after, drift))
end

print()
if failures == 0 then
    print(("ALL OK: %d checks passed"):format(checks))
    os.exit(0)
else
    print(("%d of %d checks FAILED"):format(failures, checks))
    os.exit(1)
end
