-- Board rendering and touch input.
--
-- The static part of the board (frame, points, trays) is painted once into an
-- offscreen buffer and blitted on every repaint. Only checkers, dice, the
-- highlights and the text change, which keeps a repaint down to a few dozen
-- draw calls instead of several thousand scanline rects.
--
-- Refresh regions are kept as tight as the change allows, because on e ink the
-- refresh is the expensive part, not the drawing.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local G = require("bg/game")
local R = require("bg/rules")

-- Blitbuffer.new allocates raw C memory (calloc) and registers no finalizer, so
-- a buffer that is never :free()d leaks off-heap memory the Lua GC cannot
-- reclaim. The offscreen board image is freed explicitly on close, and a GC
-- finalizer is attached as a backstop so it can never leak even if a close path
-- is ever missed.
local ok_ffi, ffi = pcall(require, "ffi")

local Screen = Device.screen
local WHITE, BLACK, BAR, OFF = G.WHITE, G.BLACK, G.BAR, G.OFF

local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE
local DARK = Blitbuffer.COLOR_GRAY_5
local LIGHT = Blitbuffer.COLOR_GRAY_B
local MID = Blitbuffer.COLOR_GRAY

local BoardView = InputContainer:extend{
    name = "backgammon",
    covers_fullscreen = true,
}

--------------------------------------------------------------------------
-- geometry
--------------------------------------------------------------------------

-- Screen column of a point, 0..11 left to right, and which row it sits on.
-- Points 1..12 run along the bottom right to left, 13..24 along the top left
-- to right. That puts white's home (1..6) bottom right and black's (19..24)
-- top right, so both bear off on the right hand side.
local function pointSlot(p)
    if p <= 12 then return "bottom", 12 - p else return "top", p - 13 end
end

local function rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function inRect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function BoardView:computeLayout()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local L = self.L
    L.screen_w, L.screen_h = W, H

    local pad = math.floor(math.min(W, H) * 0.012)
    local text_h = math.floor(math.min(W, H) * 0.045)
    if text_h < 16 then text_h = 16 end

    L.top_h = text_h * 2 + pad * 2
    L.bot_h = text_h * 2 + pad * 3

    local avail_w = W - pad * 2
    local avail_h = H - L.top_h - L.bot_h - pad * 2

    -- The board is 15 columns wide (12 points, a bar, a tray) and 11.2 checkers
    -- tall (five per point row plus the middle band). The checker size is
    -- whichever of those two limits binds.
    local pw_from_w = avail_w / 15
    local pw_from_h = avail_h / 11.2
    local checker_col = math.floor(math.min(pw_from_w, pw_from_h))
    if checker_col < 12 then checker_col = 12 end

    L.checker_r = math.floor((checker_col - 4) / 2)
    local cd = L.checker_r * 2

    -- When height is the binding limit (landscape), there is spare width: the
    -- board at checker size would be narrower than the screen and float with
    -- wide margins. Let each column grow to take up that slack, capped so the
    -- triangle never dwarfs its checker. Portrait is width-bound, so this is a
    -- no-op there and its layout is unchanged.
    local pt_w = math.floor(math.min(pw_from_w, cd * 1.35))
    if pt_w < checker_col then pt_w = checker_col end
    L.pt_w = pt_w

    L.point_h = cd * 5
    L.band_h = math.max(cd, math.floor(cd * 1.2))

    -- On a tall screen the board would otherwise float in the middle with a
    -- lot of dead space. Real boards have points longer than the five checker
    -- stack anyway, so spend the spare height on longer points and a wider
    -- middle band, up to a point where the triangles start to look silly.
    local spare = avail_h - (L.point_h * 2 + L.band_h)
    if spare > 0 then
        local band_extra = math.floor(spare * 0.3)
        L.band_h = L.band_h + band_extra
        local per_row = math.floor((spare - band_extra) / 2)
        local cap = cd * 7 - L.point_h
        if per_row > cap then per_row = cap end
        if per_row > 0 then L.point_h = L.point_h + per_row end
    end
    L.bar_w = math.floor(pt_w * 1.4)
    L.tray_w = math.floor(pt_w * 1.6)
    L.frame = math.max(2, math.floor(pt_w * 0.12))

    local inner_w = pt_w * 12 + L.bar_w + L.tray_w
    local inner_h = L.point_h * 2 + L.band_h
    L.board_w = inner_w + L.frame * 2
    L.board_h = inner_h + L.frame * 2
    L.board_x = math.floor((W - L.board_w) / 2)
    L.board_y = L.top_h + math.floor((H - L.top_h - L.bot_h - L.board_h) / 2)

    local ix = L.board_x + L.frame
    local iy = L.board_y + L.frame
    L.inner_x, L.inner_y = ix, iy
    L.inner_w, L.inner_h = inner_w, inner_h
    L.half_w = pt_w * 6
    L.bar_x = ix + L.half_w
    L.right_x = L.bar_x + L.bar_w
    L.tray_x = L.right_x + L.half_w
    L.band_y = iy + L.point_h

    -- one rect per point, covering the whole column so taps are forgiving
    for p = 1, 24 do
        local row, col = pointSlot(p)
        local x = ix + col * pt_w
        if col >= 6 then x = L.right_x + (col - 6) * pt_w end
        local y = (row == "top") and iy or (iy + L.point_h + L.band_h)
        L.point[p] = rect(x, y, pt_w, L.point_h)
    end

    -- bar: white's hit checkers sit below the middle, black's above
    L.bar_black = rect(L.bar_x, iy, L.bar_w, L.point_h + math.floor(L.band_h / 2))
    L.bar_white = rect(L.bar_x, iy + L.point_h + math.floor(L.band_h / 2),
                       L.bar_w, L.point_h + math.ceil(L.band_h / 2))

    -- trays: black bears off top right, white bottom right
    L.tray_black = rect(L.tray_x, iy, L.tray_w, L.point_h)
    L.tray_white = rect(L.tray_x, iy + L.point_h + L.band_h, L.tray_w, L.point_h)

    -- Just the patch the dice occupy, centred in the middle band and sized for
    -- the widest case (four dice on a double). Refreshing this rather than the
    -- whole strip keeps a move's refresh box small.
    local die_size = math.min(math.floor(L.band_h * 0.7), math.floor(pt_w * 1.1))
    if die_size < 12 then die_size = 12 end
    local four_w = die_size * 4 + math.floor(die_size * 0.35) * 3
    local dice_w = math.min(four_w + die_size, inner_w)
    -- The dice group is centred on the spine (the middle of the bar), so the
    -- gap between the two dice lands dead centre. The refresh box is centred the
    -- same way, then nudged inside the board if it would overhang an edge.
    L.spine_x = L.bar_x + math.floor(L.bar_w / 2)
    local da_x = L.spine_x - math.floor(dice_w / 2)
    if da_x < ix then da_x = ix end
    if da_x + dice_w > ix + inner_w then da_x = ix + inner_w - dice_w end
    L.dice_area = rect(da_x, L.band_y, dice_w, L.band_h)

    L.top_bar = rect(0, 0, W, L.top_h)
    L.msg = rect(0, H - L.bot_h, W, text_h + pad)

    -- orientation toggle, top-left of the header (the scoreboard is centred, so
    -- this corner is free and clear of the right-hand pip counts)
    local rot = math.min(math.floor(L.top_h * 0.6), math.floor(math.min(W, H) * 0.09))
    if rot < 24 then rot = 24 end
    L.rotate_btn = rect(pad * 2, math.floor((L.top_h - rot) / 2), rot, rot)

    -- "Menu" button, top-right of the header (mirrors the rotate toggle on the
    -- left; the scoreboard is centred, so this corner is free). It abandons the
    -- current game and returns to the opponent picker.
    local menu_w = math.min(math.floor(rot * 2.4), math.floor(W * 0.26))
    L.menu_btn = rect(W - menu_w - pad * 2, math.floor((L.top_h - rot) / 2), menu_w, rot)

    local btn_w = math.floor(W * 0.30)
    local side_w = math.floor(btn_w * 0.6)
    local btn_h = L.bot_h - text_h - pad * 2
    if btn_h < text_h + pad then btn_h = text_h + pad end
    local btn_y = H - btn_h - pad
    -- Roll centred; New game and Close the same distance from their corners.
    L.roll_btn = rect(math.floor(W / 2 - btn_w / 2), btn_y, btn_w, btn_h)
    L.new_btn = rect(pad, btn_y, side_w, btn_h)
    L.close_btn = rect(W - side_w - pad, btn_y, side_w, btn_h)

    -- Font:getFace runs the size through Screen:scaleBySize, so divide the
    -- pixel height we actually want by that factor or high dpi screens get
    -- text scaled twice.
    local dpi_scale = Screen:scaleBySize(1000) / 1000
    L.face_big = Font:getFace("cfont", math.floor(text_h * 0.8 / dpi_scale))
    L.face_small = Font:getFace("cfont", math.floor(text_h * 0.62 / dpi_scale))
end

--------------------------------------------------------------------------
-- static board buffer
--------------------------------------------------------------------------

local function fillTriangle(bb, x, y, w, h, pointing_down, color)
    for i = 0, h - 1 do
        local t = i / h
        local frac = pointing_down and (1 - t) or t
        local half = math.floor((w / 2) * frac)
        if half > 0 then
            bb:paintRect(x + math.floor(w / 2) - half, y + i, half * 2, 1, color)
        end
    end
end

function BoardView:buildBoardBuffer()
    local L = self.L
    if self.board_bb then
        self.board_bb:free()
        self.board_bb = nil
    end
    local bb = Blitbuffer.new(L.board_w, L.board_h, Screen.bb:getType())
    self.board_bb = bb
    if ok_ffi and type(bb) == "cdata" then
        -- free() clears the allocated flag and cancels this finalizer, so an
        -- explicit free followed by GC never double-frees.
        ffi.gc(bb, bb.free)
    end

    bb:fill(WHITE_C)
    bb:paintBorder(0, 0, L.board_w, L.board_h, L.frame, BLACK_C)

    local ox, oy = -L.board_x, -L.board_y   -- board rects are in screen space

    -- points, alternating dark and light so neighbours stay distinct at 1 bit
    for p = 1, 24 do
        local r = L.point[p]
        local row = pointSlot(p)
        local color = (p % 2 == 0) and DARK or LIGHT
        fillTriangle(bb, r.x + ox + 1, r.y + oy, r.w - 2, r.h,
                     row == "top", color)
    end

    -- the bar
    bb:paintRect(L.bar_x + ox, L.inner_y + oy, L.bar_w, L.inner_h, MID)
    bb:paintRect(L.bar_x + ox, L.inner_y + oy, 2, L.inner_h, BLACK_C)
    bb:paintRect(L.bar_x + ox + L.bar_w - 2, L.inner_y + oy, 2, L.inner_h, BLACK_C)

    -- tray column
    bb:paintRect(L.tray_x + ox, L.inner_y + oy, L.tray_w, L.inner_h, WHITE_C)
    bb:paintRect(L.tray_x + ox, L.inner_y + oy, 2, L.inner_h, BLACK_C)
    for _, tr in ipairs({ L.tray_black, L.tray_white }) do
        bb:paintBorder(tr.x + ox + 3, tr.y + oy + 2, tr.w - 6, tr.h - 4, 2, BLACK_C)
    end
end

--------------------------------------------------------------------------
-- checkers and dice
--------------------------------------------------------------------------

function BoardView:drawChecker(bb, cx, cy, player, r)
    r = r or self.L.checker_r
    if player == WHITE then
        -- white: light disc inside a heavy dark ring
        bb:paintCircle(cx, cy, r, BLACK_C, r)
        bb:paintCircle(cx, cy, r - math.max(2, math.floor(r * 0.22)), WHITE_C)
    else
        -- black: solid disc with a light inner ring so it reads as a checker
        bb:paintCircle(cx, cy, r, BLACK_C)
        bb:paintCircle(cx, cy, math.max(2, math.floor(r * 0.45)), WHITE_C, 2)
    end
end

-- Where the nth checker on a point sits. Stacks inward from the board edge.
function BoardView:checkerCentre(p, n)
    local L = self.L
    local r = L.point[p]
    local row = pointSlot(p)
    local d = L.checker_r * 2
    local cx = r.x + math.floor(r.w / 2)
    local slot = math.min(n, 5) - 1
    local cy
    if row == "top" then
        cy = r.y + L.checker_r + slot * d
    else
        cy = r.y + r.h - L.checker_r - slot * d
    end
    return cx, cy
end

local PIPS = {
    [1] = { {0.5, 0.5} },
    [2] = { {0.28, 0.28}, {0.72, 0.72} },
    [3] = { {0.28, 0.28}, {0.5, 0.5}, {0.72, 0.72} },
    [4] = { {0.28, 0.28}, {0.72, 0.28}, {0.28, 0.72}, {0.72, 0.72} },
    [5] = { {0.28, 0.28}, {0.72, 0.28}, {0.5, 0.5}, {0.28, 0.72}, {0.72, 0.72} },
    [6] = { {0.28, 0.25}, {0.72, 0.25}, {0.28, 0.5}, {0.72, 0.5}, {0.28, 0.75}, {0.72, 0.75} },
}

function BoardView:drawDie(bb, x, y, size, value, spent)
    bb:paintRoundedRect(x, y, size, size, WHITE_C, math.floor(size * 0.15))
    bb:paintBorder(x, y, size, size, spent and 1 or 3, BLACK_C, math.floor(size * 0.15))
    if spent then
        -- a struck through die reads as used even without colour
        for i = 0, size - 1 do
            bb:paintRect(x + i, y + i, 2, 2, BLACK_C)
        end
        return
    end
    local pr = math.max(2, math.floor(size * 0.09))
    for _, pip in ipairs(PIPS[value] or PIPS[1]) do
        bb:paintCircle(x + math.floor(size * pip[1]), y + math.floor(size * pip[2]), pr, BLACK_C)
    end
end

function BoardView:text(bb, x, baseline, face, str, bold)
    RenderText:renderUtf8Text(bb, x, baseline, face, str, false, bold or false, BLACK_C)
end

function BoardView:textWidth(face, str, bold)
    return RenderText:sizeUtf8Text(0, 10000, face, str, false, bold or false).x
end

function BoardView:centreText(bb, r, face, str, bold)
    local w = self:textWidth(face, str, bold)
    local baseline = r.y + math.floor(r.h / 2) + math.floor(face.size * 0.35)
    self:text(bb, r.x + math.floor((r.w - w) / 2), baseline, face, str, bold)
end

--------------------------------------------------------------------------
-- painting
--------------------------------------------------------------------------

function BoardView:paintTo(bb, x, y)
    local L = self.L
    local g = self.game
    if not g then return end   -- closed while a repaint was still queued

    -- Rotating the device changes the screen under us. Catching it here covers
    -- every route that can do it, without intercepting the rotation event and
    -- stopping whatever is underneath from rotating too.
    if L.screen_w ~= Screen:getWidth() or L.screen_h ~= Screen:getHeight() then
        self:relayout()
    end

    self.dimen.x, self.dimen.y = x, y

    bb:fill(WHITE_C)
    if not self.board_bb then self:buildBoardBuffer() end
    bb:blitFrom(self.board_bb, L.board_x, L.board_y, 0, 0, L.board_w, L.board_h)

    -- checkers
    for p = 1, 24 do
        local v = g.state.points[p]
        if v ~= 0 then
            local player = v > 0 and WHITE or BLACK
            local n = v > 0 and v or -v
            for i = 1, math.min(n, 5) do
                local cx, cy = self:checkerCentre(p, i)
                self:drawChecker(bb, cx, cy, player)
            end
            if n > 5 then
                local cx, cy = self:checkerCentre(p, 5)
                local label = tostring(n)
                local w = self:textWidth(L.face_small, label, true)
                bb:paintCircle(cx, cy, L.checker_r - 2,
                               player == WHITE and WHITE_C or BLACK_C)
                RenderText:renderUtf8Text(bb, cx - math.floor(w / 2),
                    cy + math.floor(L.face_small.size * 0.35), L.face_small, label,
                    false, true, player == WHITE and BLACK_C or WHITE_C)
            end
        end
    end

    -- bar
    for _, side in ipairs({ WHITE, BLACK }) do
        local n = g.state.bar[side]
        if n > 0 then
            local r = (side == WHITE) and L.bar_white or L.bar_black
            local cx = r.x + math.floor(r.w / 2)
            for i = 1, math.min(n, 4) do
                local cy = (side == WHITE)
                    and (r.y + r.h - L.checker_r - (i - 1) * L.checker_r * 2)
                    or (r.y + L.checker_r + (i - 1) * L.checker_r * 2)
                self:drawChecker(bb, cx, cy, side)
            end
            if n > 4 then
                local cy = (side == WHITE) and (r.y + r.h - L.checker_r * 8) or (r.y + L.checker_r * 8)
                self:centreText(bb, rect(r.x, cy - 10, r.w, 20), L.face_small, "x" .. n, true)
            end
        end
    end

    -- trays: one bar per borne off checker, plus the count
    for _, side in ipairs({ WHITE, BLACK }) do
        local n = g.state.off[side]
        local tr = (side == WHITE) and L.tray_white or L.tray_black
        if n > 0 then
            local slot_h = math.max(4, math.floor((tr.h - 8) / 15))
            for i = 1, n do
                local yy = (side == WHITE)
                    and (tr.y + tr.h - 4 - i * slot_h)
                    or (tr.y + 4 + (i - 1) * slot_h)
                bb:paintRect(tr.x + 6, yy, tr.w - 12, slot_h - 1,
                             side == WHITE and LIGHT or BLACK_C)
                if side == WHITE then
                    bb:paintBorder(tr.x + 6, yy, tr.w - 12, slot_h - 1, 1, BLACK_C)
                end
            end
        end
    end

    -- highlights
    if g.selected then
        local r = (g.selected == BAR)
            and ((g.player == WHITE) and L.bar_white or L.bar_black)
            or L.point[g.selected]
        bb:paintBorder(r.x + 1, r.y + 1, r.w - 2, r.h - 2, 3, BLACK_C)
    end
    for i = 1, g.dests_n do
        local d = g.dests[i]
        local r = (d == OFF)
            and ((g.player == WHITE) and L.tray_white or L.tray_black)
            or L.point[d]
        bb:paintBorder(r.x + 1, r.y + 1, r.w - 2, r.h - 2, 3, BLACK_C)
        -- a filled marker as well, so the cue does not rely on the border alone
        -- sit the marker where the checker would land, which is the next
        -- free slot counting in from the board edge
        local mx = r.x + math.floor(r.w / 2)
        local my
        if d == OFF then
            my = r.y + math.floor(r.h / 2)
        else
            local n = math.min(R.countAt(g.state, d, g.player), 4)
            local _, cy = self:checkerCentre(d, n + 1)
            my = cy
        end
        bb:paintCircle(mx, my, math.max(4, math.floor(L.checker_r * 0.45)), BLACK_C)
    end

    -- dice
    self:paintDice(bb)

    -- chrome
    self:paintChrome(bb)
end

-- Dice are drawn once, centred in the middle band, for whichever player is on
-- move. No side, so there is no "wrong side", and no bounce: a roll shows its
-- result straight away.
function BoardView:paintDice(bb)
    local L, g = self.L, self.game
    local size = math.min(math.floor(L.band_h * 0.7), math.floor(L.pt_w * 1.1))
    if size < 12 then size = 12 end
    local cx = L.spine_x
    local y = L.band_y + math.floor((L.band_h - size) / 2)

    -- opening: one die per player until the starter rolls for real
    if g.opening_dice[1] > 0 then
        local gap = math.floor(size * 0.6)
        local total = size * 2 + gap
        local x = cx - math.floor(total / 2)
        self:drawDie(bb, x, y, size, g.opening_dice[1], false)
        self:drawDie(bb, x + size + gap, y, size, g.opening_dice[2], false)
        return
    end
    if g.phase == "opening" then return end

    local values = self.shown_dice
    local n = #values
    if n == 0 then return end
    local gap = math.floor(size * 0.35)
    local total = size * n + gap * (n - 1)
    local x = cx - math.floor(total / 2)
    for i = 1, n do
        self:drawDie(bb, x + (i - 1) * (size + gap), y, size, values[i], i > g.ndice)
    end
end

function BoardView:paintChrome(bb)
    local L, g = self.L, self.game
    local W = Screen:getWidth()
    local pad = math.floor(L.pt_w * 0.2)

    -- scoreboard
    local score = ("White %d  -  %d Black"):format(g.score[WHITE], g.score[BLACK])
    local baseline = math.floor(L.top_h * 0.42)
    local w = self:textWidth(L.face_big, score, true)
    self:text(bb, math.floor((W - w) / 2), baseline, L.face_big, score, true)

    local turn
    if g.phase == "over" then
        turn = g.message or "Game over"
    elseif g.phase == "opening" then
        turn = g.message or "Roll to see who starts"
    elseif self.ai_side then
        if g.player == self.ai_side then
            turn = self.ai_busy and "Computer is thinking…" or "Computer's turn"
        else
            turn = "Your turn"
        end
    else
        turn = ((g.player == WHITE) and "White" or "Black") .. " to play"
    end
    local sub = ("Game %d      %s"):format(g.games + 1, turn)
    w = self:textWidth(L.face_small, sub)
    self:text(bb, math.floor((W - w) / 2), math.floor(L.top_h * 0.82), L.face_small, sub)

    -- pip counts beside the trays
    local pw = self:textWidth(L.face_small, tostring(g:pipCount(BLACK)))
    self:text(bb, L.tray_x + math.floor((L.tray_w - pw) / 2),
              L.board_y - math.floor(pad * 0.5), L.face_small, tostring(g:pipCount(BLACK)))
    pw = self:textWidth(L.face_small, tostring(g:pipCount(WHITE)))
    self:text(bb, L.tray_x + math.floor((L.tray_w - pw) / 2),
              L.board_y + L.board_h + L.face_small.size, L.face_small, tostring(g:pipCount(WHITE)))

    -- message line
    if g.message and g.phase ~= "opening" then
        self:centreText(bb, L.msg, L.face_small, g.message, true)
    end

    -- buttons
    local label = self:rollButtonLabel()
    bb:paintRoundedRect(L.roll_btn.x, L.roll_btn.y, L.roll_btn.w, L.roll_btn.h, WHITE_C, 6)
    bb:paintBorder(L.roll_btn.x, L.roll_btn.y, L.roll_btn.w, L.roll_btn.h, 3, BLACK_C, 6)
    if label == "Roll" then
        -- a small die next to the word, matching the dice on the board
        local s = math.floor(L.roll_btn.h * 0.55)
        local tw = self:textWidth(L.face_small, label, true)
        local total = s + 8 + tw
        local bx = L.roll_btn.x + math.floor((L.roll_btn.w - total) / 2)
        self:drawDie(bb, bx, L.roll_btn.y + math.floor((L.roll_btn.h - s) / 2), s, 5, false)
        self:text(bb, bx + s + 8,
                  L.roll_btn.y + math.floor(L.roll_btn.h / 2) + math.floor(L.face_small.size * 0.35),
                  L.face_small, label, true)
    else
        self:centreText(bb, L.roll_btn, L.face_small, label, true)
    end

    bb:paintBorder(L.close_btn.x, L.close_btn.y, L.close_btn.w, L.close_btn.h, 2, BLACK_C, 6)
    self:centreText(bb, L.close_btn, L.face_small, "Close")
    bb:paintBorder(L.new_btn.x, L.new_btn.y, L.new_btn.w, L.new_btn.h, 2, BLACK_C, 6)
    self:centreText(bb, L.new_btn, L.face_small, "New game")

    self:drawRotateIcon(bb, L.rotate_btn)

    -- return-to-menu button, only when the caller gave us somewhere to go back to
    if self.on_menu and L.menu_btn then
        bb:paintBorder(L.menu_btn.x, L.menu_btn.y, L.menu_btn.w, L.menu_btn.h, 2, BLACK_C, 6)
        self:centreText(bb, L.menu_btn, L.face_small, "Menu")
    end
end

-- Two overlapping rectangles, one portrait and one landscape, which reads as an
-- orientation toggle without needing a font glyph.
function BoardView:drawRotateIcon(bb, r)
    bb:paintRoundedRect(r.x, r.y, r.w, r.h, WHITE_C, 4)
    bb:paintBorder(r.x, r.y, r.w, r.h, 2, BLACK_C, 4)
    local cx = r.x + math.floor(r.w / 2)
    local cy = r.y + math.floor(r.h / 2)
    local a = math.floor(r.w * 0.30)   -- short side
    local b = math.floor(r.w * 0.50)   -- long side
    bb:paintBorder(cx - math.floor(a / 2), cy - math.floor(b / 2), a, b, 2, BLACK_C, 2)
    bb:paintBorder(cx - math.floor(b / 2), cy - math.floor(a / 2), b, a, 2, BLACK_C, 2)
end

function BoardView:clearDice()
    for i = 1, 4 do self.shown_dice[i] = nil end
end

function BoardView:rollButtonLabel()
    local g = self.game
    if g.phase == "over" then return "Next game" end
    if g.phase == "opening" then return "Roll" end
    if g.phase == "move" and g.legal_n == 0 then return "Continue" end
    if g.phase == "roll" then return "Roll" end
    return "Roll"
end

--------------------------------------------------------------------------
-- refresh helpers
--------------------------------------------------------------------------

-- UIManager keeps the Geom we hand it in a queue and only reads it later, when
-- the refresh stack is flushed. Every setDirty therefore needs its own, or the
-- earlier ones all end up pointing at the last rect. A tap is nowhere near a
-- hot path, so allocating one here is the right trade.
function BoardView:refreshEach(mode, ...)
    local n = select("#", ...)
    for i = 1, n do
        local r = select(i, ...)
        if r then
            UIManager:setDirty(self, mode, Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h })
        end
    end
end

-- Refresh the bounding box of everything passed in, as a single request.
function BoardView:refreshRects(mode, ...)
    local n = select("#", ...)
    local minx, miny, maxx, maxy
    for i = 1, n do
        local r = select(i, ...)
        if r then
            local x2, y2 = r.x + r.w, r.y + r.h
            if not minx or r.x < minx then minx = r.x end
            if not miny or r.y < miny then miny = r.y end
            if not maxx or x2 > maxx then maxx = x2 end
            if not maxy or y2 > maxy then maxy = y2 end
        end
    end
    if not minx then
        UIManager:setDirty(self, mode)
        return
    end
    UIManager:setDirty(self, mode,
        Geom:new{ x = minx, y = miny, w = maxx - minx, h = maxy - miny })
end

-- The bottom strip: message line and the three buttons, which all sit at the
-- same height, so one bounding box covers them in a single refresh.
function BoardView:refreshBottom()
    self:refreshRects("ui", self.L.msg, self.L.roll_btn)
    self.last_message = self.game and self.game.message
end

-- The top strip: scoreboard, turn indicator, pip counts. Only changes when the
-- turn passes or the game ends, so it is refreshed on its own then.
function BoardView:refreshTop()
    self:refreshEach("ui", self.L.top_bar)
end

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

function BoardView:init()
    self.L = { point = {} }
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.game = G.new()
    self.shown_dice = {}
    self.closing = false
    self.last_message = nil
    self.orig_rotation = Screen.getRotationMode and Screen:getRotationMode() or nil

    -- opponent: "human" (two players) or "ai". When "ai", the human plays White
    -- (bottom) and the computer plays Black (top).
    self.opponent = self.opponent or "human"
    self.ai_side = (self.opponent == "ai") and BLACK or nil
    self.ai_level = self.ai_level or 1
    self.ai_busy = false
    self.ai_moves = nil
    self.ai_i = 0
    -- a level that already pauses to think (the 2-ply neural net) needs less
    -- of an added delay to keep its moves followable
    self.ai_slow = false
    if self.ai_side then
        local lv = require("bg/ai").level(self.ai_level)
        self.ai_slow = (lv and lv.eval == "gnu" and (lv.ply or 1) >= 2) or false
    end

    self:computeLayout()

    -- InputContainer:_init has already made these tables and may have put a
    -- Home binding in; add to them rather than replacing them.
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    -- bound once; the computer's turn advances through these scheduled steps
    self._ai_roll = function() self:aiRoll() end
    self._ai_step = function() self:aiStep() end
    self._ai_after_pass = function() self:aiAfterPass() end
end

-- Rebuild for a new screen size, keeping the game in progress. self.dimen is
-- mutated rather than replaced because the tap GestureRange holds it.
-- Flip the board between portrait and landscape from a button, rather than by
-- physically rotating the device. This goes straight through KOReader's screen
-- rotation and re-lays-out only this widget; the file manager underneath is left
-- alone and the original orientation is restored on close. The point is to skip
-- the accelerometer / auto-rotate path, which is what bogs the panel down when a
-- device is flipped back and forth.
function BoardView:toggleOrientation()
    if not (Screen.setRotationMode and Screen.getRotationMode) then return end
    local cur = Screen:getRotationMode()
    local target
    if cur % 2 == 1 then
        -- currently landscape -> upright portrait
        target = Screen.DEVICE_ROTATED_UPRIGHT or 0
    else
        -- currently portrait -> counter-clockwise landscape, so the device's
        -- bottom bezel (the logo) ends up on the right
        target = Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE or 3
    end
    Screen:setRotationMode(target)
    self:relayout()
    -- a full refresh draws the new orientation and clears the panel at the same
    -- time, which is exactly when a full refresh is worth its cost
    UIManager:setDirty(self, "full")
end

function BoardView:relayout()
    self.dimen.w, self.dimen.h = Screen:getWidth(), Screen:getHeight()
    self:computeLayout()
    self:free()     -- paintTo rebuilds the board image at the new size
end

function BoardView:onSetDimensions()
    self:relayout()
    UIManager:setDirty(self, "flashui")
    -- deliberately not returning true: anything below still needs the event
end

function BoardView:onShow()
    UIManager:setDirty(self, "flashui")
    return true
end

-- Release the one sizeable resource this widget owns. Safe to call more than
-- once, and called from onCloseWidget below.
function BoardView:free()
    if self.board_bb then
        self.board_bb:free()
        self.board_bb = nil
    end
end

function BoardView:onCloseWidget()
    self.closing = true
    if UIManager.unschedule then
        if self._ai_roll then UIManager:unschedule(self._ai_roll) end
        if self._ai_step then UIManager:unschedule(self._ai_step) end
        if self._ai_after_pass then UIManager:unschedule(self._ai_after_pass) end
    end
    -- put the device back the way it was before the game opened, and force a
    -- full-screen refresh so the panel is left clean (and, on devices where
    -- landscape uses software rotation, back on the native fast path)
    if self.orig_rotation ~= nil and Screen.setRotationMode
        and Screen:getRotationMode() ~= self.orig_rotation then
        Screen:setRotationMode(self.orig_rotation)
    end
    UIManager:setDirty(nil, "full")
    self:free()
    -- drop everything the widget holds so nothing lingers after it leaves the
    -- window stack; the session score is deliberately not saved anywhere
    self.game = nil
    self.L = nil
    self.shown_dice = nil
    collectgarbage("collect")
end

function BoardView:onClose()
    UIManager:close(self)
    return true
end

-- Abandon the current game and hand control back to the opponent picker.
-- Closing the board first runs onCloseWidget, which unschedules the computer's
-- pending moves, frees the board image, restores the screen orientation and
-- drops all game state -- so nothing from the abandoned game keeps running or
-- holds memory once we reopen the menu.
function BoardView:goToMenu()
    local on_menu = self.on_menu
    UIManager:close(self)
    if on_menu then on_menu() end
end

--------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------

function BoardView:onTap(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    local L, g = self.L, self.game

    -- while the computer is rolling/moving, only Close and Menu respond, so the
    -- game can still be closed or abandoned mid-turn
    if self.ai_busy then
        if inRect(L.close_btn, x, y) then
            UIManager:close(self)
        elseif self.on_menu and L.menu_btn and inRect(L.menu_btn, x, y) then
            self:goToMenu()
        end
        return true
    end

    if inRect(L.close_btn, x, y) then
        UIManager:close(self)
        return true
    end
    if inRect(L.new_btn, x, y) then
        g:newGame()
        self:clearDice()
        UIManager:setDirty(self, "flashui")
        return true
    end
    if inRect(L.roll_btn, x, y) then
        self:onRollButton()
        return true
    end
    if L.rotate_btn and inRect(L.rotate_btn, x, y) then
        self:toggleOrientation()
        return true
    end
    if self.on_menu and L.menu_btn and inRect(L.menu_btn, x, y) then
        self:goToMenu()
        return true
    end

    if g.phase ~= "move" or g.legal_n == 0 then return true end

    -- tapping a highlighted destination plays the move
    if g.selected then
        local target = self:hitDestination(x, y)
        if target then
            self:playMove(target)
            return true
        end
    end

    -- otherwise try to select a checker
    local p = self:hitPoint(x, y)
    if p then
        if g.selected == p then
            local old = self:selectionRegion()
            g:deselect()
            self:refreshRects("ui", old)
        elseif g:canSelect(p) then
            local old = self:selectionRegion()
            g:select(p)
            self:refreshRects("ui", old, self:selectionRegion())
        end
        return true
    end

    if g.selected then
        local old = self:selectionRegion()
        g:deselect()
        self:refreshRects("ui", old)
    end
    return true
end

-- The union of the selected point and everything it can reach, so a selection
-- change refreshes exactly the area that shows it.
function BoardView:selectionRegion()
    local L, g = self.L, self.game
    if not g.selected then return nil end
    local minx, miny, maxx, maxy
    local function add(r)
        if not r then return end
        if not minx or r.x < minx then minx = r.x end
        if not miny or r.y < miny then miny = r.y end
        if not maxx or r.x + r.w > maxx then maxx = r.x + r.w end
        if not maxy or r.y + r.h > maxy then maxy = r.y + r.h end
    end
    add((g.selected == BAR)
        and ((g.player == WHITE) and L.bar_white or L.bar_black)
        or L.point[g.selected])
    for i = 1, g.dests_n do
        local d = g.dests[i]
        add((d == OFF)
            and ((g.player == WHITE) and L.tray_white or L.tray_black)
            or L.point[d])
    end
    if not minx then return nil end
    self.sel_region = self.sel_region or { x = 0, y = 0, w = 0, h = 0 }
    self.sel_region.x, self.sel_region.y = minx, miny
    self.sel_region.w, self.sel_region.h = maxx - minx, maxy - miny
    return self.sel_region
end

function BoardView:hitPoint(x, y)
    local L, g = self.L, self.game
    local barr = (g.player == WHITE) and L.bar_white or L.bar_black
    if g.state.bar[g.player] > 0 and inRect(barr, x, y) then return BAR end
    for p = 1, 24 do
        if inRect(L.point[p], x, y) then return p end
    end
    return nil
end

function BoardView:hitDestination(x, y)
    local L, g = self.L, self.game
    for i = 1, g.dests_n do
        local d = g.dests[i]
        local r = (d == OFF)
            and ((g.player == WHITE) and L.tray_white or L.tray_black)
            or L.point[d]
        if inRect(r, x, y) then return d end
    end
    return nil
end

--------------------------------------------------------------------------
-- turn flow
--------------------------------------------------------------------------

function BoardView:onRollButton()
    local g = self.game

    if g.phase == "over" then
        g:newGame()
        self:clearDice()
        UIManager:setDirty(self, "flashui")
        return
    end

    if g.phase == "move" and g.legal_n == 0 then
        -- the Continue button after a dead roll
        g:passTurn()
        self:clearDice()
        self:refreshEach("fast", self.L.dice_area)
        self:refreshTop()
        self:refreshBottom()
        self:maybeStartAI()
        return
    end

    if g.phase == "opening" then
        g:openingRoll()
        self:clearDice()
        -- dice first, with the quick waveform, so they appear without lag
        self:refreshEach("fast", self.L.dice_area)
        self:refreshBottom()
        self:maybeStartAI()
        return
    end

    if g.phase == "roll" then
        g:roll()
        self:clearDice()
        for i = 1, g.ndice do self.shown_dice[i] = g.dice[i] end
        self:refreshEach("fast", self.L.dice_area)
        -- the message clears and the button label may change to Continue
        self:refreshBottom()
    end
end

function BoardView:playMove(to)
    local g = self.game
    local L = self.L

    -- The highlight area already covers the checker and every square it could
    -- reach, so it is exactly what has to be redrawn. selectionRegion hands back
    -- a shared table and the move is about to clear the selection, so snapshot
    -- the four numbers now.
    local sel = self:selectionRegion()
    local region
    if sel then
        region = { x = sel.x, y = sel.y, w = sel.w, h = sel.h }
    end

    local player = g.player
    local res = g:move(to)
    if not res then return end

    -- rebuild the visible dice from what is left
    self:clearDice()
    for i = 1, g.ndice do self.shown_dice[i] = g.dice[i] end

    if res == "won" then
        UIManager:setDirty(self, "flashui")
        return
    end

    -- a hit puts a checker on the other player's bar
    local hit_r = g.last_hit
        and ((player == WHITE) and L.bar_black or L.bar_white)
        or nil

    -- Everything that changed on the board (the checker's old and new squares,
    -- the cleared highlights, the consumed die, a hit on the bar) sits inside
    -- one bounding box, so a move is a single refresh rather than several
    -- sequential e ink updates.
    self:refreshRects("ui", region, hit_r, L.dice_area)

    if res == "turn_over" then
        g:passTurn()
        self:refreshTop()
        self:refreshBottom()
        self:maybeStartAI()
    elseif self.last_message ~= g.message then
        self:refreshBottom()
    end
end

--------------------------------------------------------------------------
-- computer opponent
--------------------------------------------------------------------------

-- Screen rect for a point / the bar / the tray, from `player`'s side.
function BoardView:rectFor(point, player)
    local L = self.L
    if point == BAR then return (player == WHITE) and L.bar_white or L.bar_black end
    if point == OFF then return (player == WHITE) and L.tray_white or L.tray_black end
    return L.point[point]
end

-- Pacing for the computer's turn, in seconds. The moves are deliberately
-- unhurried so a human can see which checker moved and follow the play; tune
-- them here.
local AI_DELAY_ROLL   = 0.6   -- handover -> the computer rolls
local AI_DELAY_FIRST  = 2.0   -- dice shown -> the computer's first move
local AI_DELAY_BETWEEN = 1.6  -- between the computer's moves within a turn
local AI_DELAY_PASS   = 2.0   -- a dead roll is shown before the turn passes back
-- shorter delays for levels that already spend a second or two thinking
local AI_DELAY_FIRST_SLOW   = 0.4
local AI_DELAY_BETWEEN_SLOW = 1.0

-- If it is the computer's turn to roll, start its turn after a short beat so
-- the human sees the handover. A no-op in two-player games.
function BoardView:maybeStartAI()
    if self.closing or not self.ai_side or self.ai_busy then return end
    local g = self.game
    if g.phase == "roll" and g.player == self.ai_side then
        self.ai_busy = true
        self:refreshTop()
        UIManager:scheduleIn(AI_DELAY_ROLL, self._ai_roll)
    end
end

function BoardView:aiRoll()
    if self.closing then return end
    local g = self.game
    if g.phase ~= "roll" or g.player ~= self.ai_side then
        self.ai_busy = false
        return
    end
    local what = g:roll()
    self:clearDice()
    for i = 1, g.ndice do self.shown_dice[i] = g.dice[i] end
    self:refreshEach("fast", self.L.dice_area)
    self:refreshTop()
    if what == "pass" then
        -- make it clear it is the computer that is stuck, and hold the dead dice
        -- on screen long enough to read before the turn hands back
        g.message = "Computer can't move"
        self:refreshTop()
        self:refreshBottom()
        UIManager:scheduleIn(AI_DELAY_PASS, self._ai_after_pass)
        return
    end
    -- the move is chosen lazily, in the first step, so that a heavier level's
    -- thinking does not hold up painting the dice that were just rolled
    self.ai_moves = nil
    self.ai_i = 0
    UIManager:scheduleIn(self.ai_slow and AI_DELAY_FIRST_SLOW or AI_DELAY_FIRST, self._ai_step)
end

function BoardView:aiAfterPass()
    if self.closing then return end
    self.game:passTurn()
    self.game.message = nil
    self.ai_busy = false
    self:refreshTop()
    self:refreshBottom()
    self:maybeStartAI()
end

function BoardView:aiStep()
    if self.closing then return end
    local g = self.game
    -- choose the whole turn on the first step (see aiRoll)
    if not self.ai_moves then
        local AI = require("bg/ai")
        self.ai_moves = AI.chooseTurn(g.state, g.player, g.dice, g.ndice, self.ai_level)
        if #self.ai_moves == 0 then
            -- defensive: a real dead roll is already handled at roll time
            g.message = "Computer can't move"
            self:refreshTop()
            self:refreshBottom()
            UIManager:scheduleIn(AI_DELAY_PASS, self._ai_after_pass)
            return
        end
    end
    self.ai_i = self.ai_i + 1
    local mv = self.ai_moves[self.ai_i]
    if not mv then
        self.ai_busy = false
        return
    end
    local res = self:applyAIMove(mv.from, mv.to)
    if res == "won" then
        self.ai_busy = false
        return
    end
    if res == nil or res == "turn_over" then
        g:passTurn()
        self.ai_busy = false
        self:refreshTop()
        self:refreshBottom()
        self:maybeStartAI()
        return
    end
    -- more of the computer's moves to play, one at a time so they are followable
    UIManager:scheduleIn(self.ai_slow and AI_DELAY_BETWEEN_SLOW or AI_DELAY_BETWEEN, self._ai_step)
end

-- Apply one computer move and refresh it the same way a human move is refreshed.
function BoardView:applyAIMove(from, to)
    local g, L = self.game, self.L
    local player = g.player
    local from_r = self:rectFor(from, player)
    local to_r = self:rectFor(to, player)
    local res = g:moveDirect(from, to)
    self:clearDice()
    for i = 1, g.ndice do self.shown_dice[i] = g.dice[i] end
    if res == "won" then
        UIManager:setDirty(self, "flashui")
        return res
    end
    local hit_r = g.last_hit
        and ((player == WHITE) and L.bar_black or L.bar_white)
        or nil
    self:refreshRects("ui", from_r, to_r, hit_r, L.dice_area)
    return res
end

return BoardView
