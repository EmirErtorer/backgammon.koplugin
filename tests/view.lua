-- Drives the board view through a mock KOReader. Run with:
--   luajit tests/view.lua
-- from the plugin directory.

package.path = "./?.lua;./tests/mock/?.lua;" .. package.path

local BB = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local BoardView = require("bg/boardview")
local R = require("bg/rules")

local WHITE, BLACK, BAR, OFF = R.WHITE, R.BLACK, R.BAR, R.OFF

local failures, checks = 0, 0
local function ok(cond, what)
    checks = checks + 1
    if not cond then failures = failures + 1 print("FAIL: " .. what) end
end
local function eq(got, want, what)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(("FAIL: %s (got %s, want %s)"):format(what, tostring(got), tostring(want)))
    end
end

local screen_bb = BB.new(1448, 1072)
local function paint(v)
    v:paintTo(screen_bb, 0, 0)
end
local function centre(r) return r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) end
local function tap(v, r)
    local x, y = centre(r)
    v:onTap(nil, { pos = { x = x, y = y } })
end

--------------------------------------------------------------------------
print("-- construction and layout")
--------------------------------------------------------------------------
local view = BoardView:new{}
ok(view.L.pt_w > 0, "layout produced a point width")
ok(view.game ~= nil, "a game was created")

do
    local L = view.L
    -- every point rect must sit inside the board
    local bad = 0
    for p = 1, 24 do
        local r = L.point[p]
        if r.x < L.board_x or r.y < L.board_y
            or r.x + r.w > L.board_x + L.board_w
            or r.y + r.h > L.board_y + L.board_h then
            bad = bad + 1
        end
    end
    eq(bad, 0, "all 24 point rects lie inside the board")

    -- no two point rects overlap
    local overlaps = 0
    for a = 1, 24 do
        for b = a + 1, 24 do
            local ra, rb = L.point[a], L.point[b]
            if ra.x < rb.x + rb.w and rb.x < ra.x + ra.w
                and ra.y < rb.y + rb.h and rb.y < ra.y + ra.h then
                overlaps = overlaps + 1
            end
        end
    end
    eq(overlaps, 0, "no two point rects overlap")

    -- tapping the centre of a point must resolve back to that point
    local wrong = 0
    for p = 1, 24 do
        local x, y = centre(L.point[p])
        if view:hitPoint(x, y) ~= p then wrong = wrong + 1 end
    end
    eq(wrong, 0, "every point rect hit tests back to its own point")

    -- home boards must be on the right hand side, both of them
    -- "right hand side" means right of the bar, not right of the board: the
    -- tray column pushes the board's geometric centre past the bar
    for p = 1, 6 do ok(L.point[p].x >= L.right_x, "white home point " .. p .. " is right of the bar") end
    for p = 19, 24 do ok(L.point[p].x >= L.right_x, "black home point " .. p .. " is right of the bar") end
    for p = 7, 18 do ok(L.point[p].x < L.bar_x, "outer point " .. p .. " is left of the bar") end
    ok(L.point[1].y > L.point[24].y, "white home is the bottom right, black the top right")
    ok(L.tray_white.x >= L.point[1].x, "the trays sit outboard of the home points")
end

--------------------------------------------------------------------------
print("-- painting")
--------------------------------------------------------------------------
do
    BB.out_of_bounds = 0
    paint(view)
    eq(BB.out_of_bounds, 0, "opening position paints entirely inside the buffers")

    -- a crowded position: checkers stacked past five, both bars loaded, both
    -- trays part full
    local g = view.game
    for i = 1, 24 do g.state.points[i] = 0 end
    g.state.points[6] = 8
    g.state.points[13] = -7
    g.state.bar[WHITE] = 5
    g.state.bar[BLACK] = 6
    g.state.off[WHITE] = 2
    g.state.off[BLACK] = 2
    g.phase = "move"
    g.message = "a message that is fairly long to test the layout"
    BB.out_of_bounds = 0
    paint(view)
    eq(BB.out_of_bounds, 0, "crowded position paints inside the buffers")
end

--------------------------------------------------------------------------
print("-- a full game driven by taps")
--------------------------------------------------------------------------
do
    math.randomseed(99)
    local v = BoardView:new{}
    local L = v.L
    local g = v.game

    local function rectFor(p, player)
        if p == BAR then
            return (player == WHITE) and L.bar_white or L.bar_black
        elseif p == OFF then
            return (player == WHITE) and L.tray_white or L.tray_black
        end
        return L.point[p]
    end

    -- decide who starts
    local guard = 0
    while g.phase == "opening" do
        tap(v, L.roll_btn)
        guard = guard + 1
        ok(guard < 100, "the opening roll resolved")
        if guard >= 100 then break end
    end
    ok(g.phase == "roll", "a starting player was chosen")

    local moves, passes, turns = 0, 0, 0
    local big_refreshes = 0
    local screen_area = 1448 * 1072

    while g.phase ~= "over" and turns < 3000 do
        turns = turns + 1

        if g.phase == "roll" then
            tap(v, L.roll_btn)
        elseif g.phase == "move" then
            if g.legal_n == 0 then
                passes = passes + 1
                tap(v, L.roll_btn)      -- the Continue button
            else
                local pick = math.random(g.legal_n)
                local from = g.legal_from[pick]
                tap(v, rectFor(from, g.player))
                if g.selected ~= from then
                    failures = failures + 1
                    print("FAIL: tapping a legal source did not select it")
                    break
                end
                local d = g.dests[math.random(g.dests_n)]

                UIManager.reset()
                tap(v, rectFor(d, g.player))
                local last = UIManager.last()
                for _, rr in ipairs(UIManager.refreshes) do
                    if rr.region then
                        local area = rr.region.w * rr.region.h
                        if area > screen_area * 0.60 then big_refreshes = big_refreshes + 1 end
                    end
                end

                moves = moves + 1
                local good, why = R.check(g.state)
                if not good then
                    failures = failures + 1
                    print("FAIL: invariant broken: " .. tostring(why))
                    break
                end
            end
        end

        BB.out_of_bounds = 0
        paint(v)
        if BB.out_of_bounds > 0 then
            failures = failures + 1
            print("FAIL: painted out of bounds during play")
            break
        end
    end
    checks = checks + 1

    ok(g.phase == "over", "the game finished")
    ok(g.win_points >= 1 and g.win_points <= 3, "a sensible number of points was awarded")
    ok(g.score[WHITE] + g.score[BLACK] == g.win_points, "the scoreboard was updated")
    eq(big_refreshes, 0, "no ordinary move refreshed more than 60% of the screen")
    print(("   %d moves, %d dead rolls, %d turns; winner scored %d")
        :format(moves, passes, turns, g.win_points))
end

--------------------------------------------------------------------------
print("-- selection refreshes stay local")
--------------------------------------------------------------------------
do
    math.randomseed(7)
    local v = BoardView:new{}
    local g = v.game
    while g.phase == "opening" do tap(v, v.L.roll_btn) end
    tap(v, v.L.roll_btn)
    if g.legal_n > 0 then
        UIManager.reset()
        tap(v, v.L.point[g.legal_from[1]] or v.L.bar_white)
        local last = UIManager.last()
        ok(last ~= nil and last.region ~= nil, "selecting refreshes a region rather than the screen")
        if last and last.region then
            local frac = (last.region.w * last.region.h) / (1448 * 1072)
            ok(frac < 0.62, ("the selection region is a fraction of the screen (%.0f%%)"):format(frac * 100))
            print(("   selection refresh covered %.0f%% of the screen"):format(frac * 100))
        end
        eq(last and last.mode, "ui", "selection uses a non flashing ui refresh")
    end
end

--------------------------------------------------------------------------
print("-- buffers and heap")
--------------------------------------------------------------------------
do
    local before_alloc = BB.allocated or 0
    local v = BoardView:new{}
    paint(v)
    ok((BB.allocated or 0) > before_alloc, "the static board buffer was allocated")
    UIManager:close(v)
    eq(BB.allocated or 0, before_alloc, "the board buffer is freed when the widget closes")

    -- repainting must not keep allocating buffers or growing the heap
    local v2 = BoardView:new{}
    paint(v2)
    local alloc_after_first = BB.allocated
    for _ = 1, 200 do paint(v2) end
    eq(BB.allocated, alloc_after_first, "repainting does not allocate more buffers")

    collectgarbage("collect")
    local h0 = collectgarbage("count")
    for _ = 1, 500 do paint(v2) end
    collectgarbage("collect")
    local h1 = collectgarbage("count")
    local drift = h1 - h0
    ok(drift < 24, ("repainting does not grow the heap: %.1f KB over 500 repaints"):format(drift))
    print(("   heap drift over 500 repaints: %.1f KB"):format(drift))
    UIManager:close(v2)
end

--------------------------------------------------------------------------
print("-- layout across real screen sizes")
--------------------------------------------------------------------------
do
    local Device = require("device")
    local sizes = {
        { 1448, 1072, "Kobo Libra landscape" },
        { 1072, 1448, "Kobo Libra portrait" },
        { 1264, 1680, "Kobo Sage portrait" },
        { 1680, 1264, "Kobo Sage landscape" },
        {  758, 1024, "Kindle Basic portrait" },
        { 1024,  758, "Kindle Basic landscape" },
        {  600,  800, "small portrait" },
    }
    for _, sz in ipairs(sizes) do
        local W, H, label = sz[1], sz[2], sz[3]
        Device.screen.setSize(W, H)
        local v = BoardView:new{}
        local L = v.L
        local problems = {}

        if L.board_x < 0 or L.board_y < 0
            or L.board_x + L.board_w > W or L.board_y + L.board_h > H then
            problems[#problems + 1] = "board off screen"
        end
        if L.board_y < L.top_h then problems[#problems + 1] = "board overlaps the top bar" end
        if L.board_y + L.board_h > H - L.bot_h then
            problems[#problems + 1] = "board overlaps the bottom bar"
        end
        for p = 1, 24 do
            if v:hitPoint(centre(L.point[p])) ~= p then
                problems[#problems + 1] = "hit test wrong for point " .. p
                break
            end
        end
        if L.checker_r < 4 then problems[#problems + 1] = "checkers too small to tap" end

        local sbb = BB.new(W, H)
        BB.out_of_bounds = 0
        v:paintTo(sbb, 0, 0)
        if BB.out_of_bounds > 0 then problems[#problems + 1] = "painted out of bounds" end

        ok(#problems == 0, label .. " layout: " .. (problems[1] or "fine"))
        print(("   %-24s %4dx%-4d  point %3dpx  checker r=%2d  board %dx%d")
            :format(label, W, H, L.pt_w, L.checker_r, L.board_w, L.board_h))
        UIManager:close(v)
    end
    Device.screen.setSize(1448, 1072)
end

--------------------------------------------------------------------------
print("-- refresh area over a whole game")
--------------------------------------------------------------------------
do
    math.randomseed(2026)
    local v = BoardView:new{}
    local L, g = v.L, v.game
    local W, H = 1448, 1072
    local area = W * H

    local function rectFor(p, player)
        if p == BAR then return (player == WHITE) and L.bar_white or L.bar_black end
        if p == OFF then return (player == WHITE) and L.tray_white or L.tray_black end
        return L.point[p]
    end

    while g.phase == "opening" do tap(v, L.roll_btn) end

    local sum, count, worst, fulls = 0, 0, 0, 0
    local refresh_moves, refresh_total = 0, 0
    local turns = 0
    while g.phase ~= "over" and turns < 3000 do
        turns = turns + 1
        if g.phase == "roll" then
            tap(v, L.roll_btn)
        elseif g.legal_n == 0 then
            tap(v, L.roll_btn)
        else
            local pick = math.random(g.legal_n)
            tap(v, rectFor(g.legal_from[pick], g.player))
            local d = g.dests[math.random(g.dests_n)]
            UIManager.reset()
            tap(v, rectFor(d, g.player))
            refresh_moves = refresh_moves + 1
            refresh_total = refresh_total + #UIManager.refreshes
            for _, r in ipairs(UIManager.refreshes) do
                if r.region then
                    local frac = (r.region.w * r.region.h) / area
                    sum = sum + frac
                    count = count + 1
                    if frac > worst then worst = frac end
                else
                    fulls = fulls + 1
                end
            end
        end
    end
    local refreshes_per_move = refresh_total / math.max(1, refresh_moves)
    ok(count > 0, "refreshes were recorded")
    print(("   %d refreshes during play: mean %.1f%% of screen, worst %.1f%%, %d full screen")
        :format(count, sum / count * 100, worst * 100, fulls))
    print(("   %.2f refreshes per move on average"):format(refreshes_per_move))
    -- For e ink latency the number of separate refreshes per action matters
    -- more than their area: each refresh is a controller round trip, so one
    -- larger refresh beats several small ones. Keep a move to a couple.
    ok(refreshes_per_move <= 2.2,
       ("a move issues few refreshes: %.2f on average"):format(refreshes_per_move))
    ok(worst < 0.62, "no single refresh covers most of the screen")
    -- the only unbounded refresh should be the deliberate flash when the game
    -- ends, which is where clearing ghosting is worth the cost
    ok(fulls <= 1, "only the end of game flash refreshes the whole screen")
    UIManager:close(v)
end

--------------------------------------------------------------------------
print("-- plugin entry point")
--------------------------------------------------------------------------
do
    local Plugin = dofile("./main.lua")
    local registered
    local p = Plugin:new{ ui = { menu = { registerToMainMenu = function(_, x) registered = x end } } }
    ok(registered == p, "the plugin registers itself with the main menu")

    local items = {}
    p:addToMainMenu(items)
    ok(items.backgammon ~= nil, "a Backgammon menu entry was added")
    ok(type(items.backgammon.text) == "string", "the entry has a label")
    ok(items.backgammon.sorting_hint == "more_tools", "it is filed under more tools")

    -- the callback must actually build and show a board
    UIManager.shown = nil
    items.backgammon.callback()
    ok(UIManager.shown ~= nil, "the menu entry opens the board")
    ok(UIManager.shown.game ~= nil, "the board it opens has a game")
    UIManager:close(UIManager.shown)
end

--------------------------------------------------------------------------
print("-- screen rotation mid game")
--------------------------------------------------------------------------
do
    local Device = require("device")
    Device.screen.setSize(1448, 1072)
    local v = BoardView:new{}
    local g = v.game
    while g.phase == "opening" do tap(v, v.L.roll_btn) end
    tap(v, v.L.roll_btn)
    local pips_before = g:pipCount(WHITE)
    local w_before = v.L.board_w

    -- rotate under the widget and repaint without telling it anything
    Device.screen.setSize(1072, 1448)
    local sbb = BB.new(1072, 1448)
    BB.out_of_bounds = 0
    v:paintTo(sbb, 0, 0)
    eq(BB.out_of_bounds, 0, "repaint after a rotation stays inside the new screen")
    ok(v.L.board_w ~= w_before, "the layout was rebuilt for the new size")
    eq(v.L.screen_w, 1072, "the layout knows the new width")
    eq(g:pipCount(WHITE), pips_before, "the game in progress survived the rotation")
    eq(v.dimen.w, 1072, "the tap range followed the new width")

    local wrong = 0
    for p = 1, 24 do
        if v:hitPoint(centre(v.L.point[p])) ~= p then wrong = wrong + 1 end
    end
    eq(wrong, 0, "hit testing still works after the rotation")
    UIManager:close(v)
    Device.screen.setSize(1448, 1072)
end

--------------------------------------------------------------------------
print("-- every changed area is actually refreshed")
--------------------------------------------------------------------------
do
    -- The regression this guards: UIManager keeps the Geom it is handed and
    -- reads it only when the refresh stack is flushed, so reusing one table
    -- across several setDirty calls silently drops all but the last region.
    -- The queue is therefore read after the action, not during it.
    math.randomseed(31337)
    local v = BoardView:new{}
    local L, g = v.L, v.game

    local function rectFor(p, player)
        if p == BAR then return (player == WHITE) and L.bar_white or L.bar_black end
        if p == OFF then return (player == WHITE) and L.tray_white or L.tray_black end
        return L.point[p]
    end
    local function covered(regions, r)
        -- the rect must be inside at least one refreshed region; a refresh
        -- with no region means the whole screen, which covers everything
        for _, q in ipairs(regions) do
            if not q.region then return true end
            if r.x >= q.region.x and r.y >= q.region.y
                and r.x + r.w <= q.region.x + q.region.w
                and r.y + r.h <= q.region.y + q.region.h then
                return true
            end
        end
        return false
    end

    while g.phase == "opening" do tap(v, L.roll_btn) end

    local checked_moves, missed_src, missed_dst, missed_dice = 0, 0, 0, 0
    local turns = 0
    while g.phase ~= "over" and turns < 3000 do
        turns = turns + 1
        if g.phase == "roll" then
            UIManager.flush()
            tap(v, L.roll_btn)
            local regions = UIManager.flush()
            -- a fresh roll has to repaint the dice strip, or the player is
            -- looking at the previous roll
            if not covered(regions, L.dice_area) then missed_dice = missed_dice + 1 end
        elseif g.legal_n == 0 then
            tap(v, L.roll_btn)
        else
            local pick = math.random(g.legal_n)
            local from = g.legal_from[pick]
            tap(v, rectFor(from, g.player))
            local d = g.dests[math.random(g.dests_n)]
            local src_r = rectFor(from, g.player)
            local dst_r = rectFor(d, g.player)

            UIManager.flush()
            tap(v, dst_r)
            local regions = UIManager.flush()
            checked_moves = checked_moves + 1
            if not covered(regions, src_r) then missed_src = missed_src + 1 end
            if not covered(regions, dst_r) then missed_dst = missed_dst + 1 end
        end
    end

    eq(missed_src, 0, "the point a checker left is always refreshed")
    eq(missed_dst, 0, "the point a checker arrived at is always refreshed")
    eq(missed_dice, 0, "the dice strip is always refreshed after a roll")
    print(("   %d moves checked, all source, destination and dice areas refreshed")
        :format(checked_moves))
    UIManager:close(v)
end

--------------------------------------------------------------------------
print("-- in-plugin orientation toggle")
--------------------------------------------------------------------------
do
    local Device = require("device")
    Device.screen.setSize(1072, 1448)          -- start in portrait
    ok(Device.screen.getScreenMode() == "portrait", "starts in portrait")
    local v = BoardView:new{}
    ok(v.L.rotate_btn ~= nil, "the layout has a rotate button")
    local port_board_w = v.L.board_w

    -- get a game going so we can confirm state survives a toggle
    while v.game.phase == "opening" do tap(v, v.L.roll_btn) end
    tap(v, v.L.roll_btn)
    local pip = v.game:pipCount(WHITE)
    local phase = v.game.phase

    -- toggle to landscape via the button
    tap(v, v.L.rotate_btn)
    eq(Device.screen.getScreenMode(), "landscape", "the button switches to landscape")
    ok(Device.screen.getWidth() > Device.screen.getHeight(), "the screen is landscape now")
    ok(v.L.board_w ~= port_board_w, "the board re-laid-out for the new orientation")
    eq(v.game:pipCount(WHITE), pip, "the game in progress survived the toggle")
    eq(v.game.phase, phase, "the phase is unchanged by the toggle")

    -- and it paints cleanly at the new orientation
    local sbb = BB.new(Device.screen.getWidth(), Device.screen.getHeight())
    BB.out_of_bounds = 0
    v:paintTo(sbb, 0, 0)
    eq(BB.out_of_bounds, 0, "paints inside bounds after the toggle")

    -- taps still land on the right points after the toggle
    local wrong = 0
    for p = 1, 24 do
        if v:hitPoint(centre(v.L.point[p])) ~= p then wrong = wrong + 1 end
    end
    eq(wrong, 0, "hit testing is correct in the toggled orientation")

    -- toggle back
    tap(v, v.L.rotate_btn)
    eq(Device.screen.getScreenMode(), "portrait", "toggling again returns to portrait")
    UIManager:close(v)
    Device.screen.setSize(1448, 1072)
end

--------------------------------------------------------------------------
print("-- closing restores the original orientation")
--------------------------------------------------------------------------
do
    local Device = require("device")
    Device.screen.setSize(1072, 1448)          -- portrait
    local v = BoardView:new{}
    tap(v, v.L.rotate_btn)                      -- switch to landscape
    ok(Device.screen.getScreenMode() == "landscape", "switched to landscape for the game")
    UIManager:close(v)
    eq(Device.screen.getScreenMode(), "portrait", "close puts the device back to portrait")
    Device.screen.setSize(1448, 1072)
end

print()
if failures == 0 then
    print(("ALL OK: %d checks passed"):format(checks))
    os.exit(0)
else
    print(("%d of %d checks FAILED"):format(failures, checks))
    os.exit(1)
end
