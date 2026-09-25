-- Small drawing helpers shared by the full-screen menu views (setup, settings,
-- stats, review) and the in-game dialogs. These were copy-pasted into every
-- view; keeping one copy here means the text metrics and the rounded-button look
-- stay consistent, and there is a single place to adjust them.
--
-- Everything is a plain function taking explicit arguments (no `self`), so a
-- view can alias them to whatever local or method names it already uses without
-- changing a single call site.

local Blitbuffer = require("ffi/blitbuffer")
local RenderText = require("ui/rendertext")

local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE

local U = {}

function U.rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function U.inRect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- width of `s` in `face`, optionally bold
function U.textW(face, s, bold)
    return RenderText:sizeUtf8Text(0, 100000, face, s, false, bold or false).x
end

-- draw `s` at (x, baseline)
function U.text(bb, x, baseline, face, s, bold, color)
    RenderText:renderUtf8Text(bb, x, baseline, face, s, false, bold or false,
                              color or BLACK_C)
end

-- draw `s` centred horizontally on cx, sitting on `baseline`
function U.centered(bb, cx, baseline, face, s, bold, color)
    U.text(bb, cx - math.floor(U.textW(face, s, bold) / 2), baseline, face, s, bold, color)
end

-- Exactly the pixels of bb:paintCircle(cx, cy, r, c, w), but painted as short
-- horizontal and vertical runs through bb:paintRect, which the C blitter fills,
-- instead of one Lua setPixel per pixel. (Only the walk around the edge is Lua,
-- a few dozen steps per circle.)
--
-- This matters for speed, not looks. paintCircle's pixel loops never get
-- compiled under KOReader's JIT settings, and the little that does compile is
-- tied to the screen rotation it first ran in. Whichever orientation came
-- second (normally landscape) then drew every circle through the interpreter,
-- many times slower. The runs below follow paintCircle's own midpoint walk
-- step for step, so the result is byte-identical; clipping is paintRect's.
function U.paintCircle(bb, cx, cy, r, c, w)
    if r == 0 then return end
    if w == nil or w > r then w = r end
    local r2 = r - w
    -- the four axis spokes
    local n = r - r2
    if n > 0 then
        bb:paintRect(cx, cy + r2 + 1, 1, n, c)
        bb:paintRect(cx, cy - r, 1, n, c)
        bb:paintRect(cx + r2 + 1, cy, n, 1, c)
        bb:paintRect(cx - r, cy, n, 1, c)
    end
    -- outer and inner circle, stepped together as paintCircle does; each step
    -- fills the band between them in all eight octants
    local x, y, delta = 0, r, 5/4 - r
    local x2, y2, delta2 = 0, r2, 5/4 - r2
    while x < y do
        x = x + 1
        if delta > 0 then
            y = y - 1
            delta = delta + 2*x - 2*y + 2
        else
            delta = delta + 2*x + 1
        end
        if x2 > y2 then
            y2 = y2 + 1
            x2 = x2 + 1
        else
            x2 = x2 + 1
            if delta2 > 0 then
                y2 = y2 - 1
                delta2 = delta2 + 2*x2 - 2*y2 + 2
            else
                delta2 = delta2 + 2*x2 + 1
            end
        end
        n = y - y2
        if n > 0 then
            bb:paintRect(cx + x, cy + y2 + 1, 1, n, c)
            bb:paintRect(cx + y2 + 1, cy + x, n, 1, c)
            bb:paintRect(cx + y2 + 1, cy - x, n, 1, c)
            bb:paintRect(cx + x, cy - y, 1, n, c)
            bb:paintRect(cx - x, cy - y, 1, n, c)
            bb:paintRect(cx - y, cy - x, n, 1, c)
            bb:paintRect(cx - y, cy + x, n, 1, c)
            bb:paintRect(cx - x, cy + y2 + 1, 1, n, c)
        end
    end
    if r == w then bb:paintRect(cx, cy, 1, 1, c) end
end

-- A comfortable corner radius for a button of height `h`, so the rounded-square
-- look scales with the control and stays consistent across screens.
function U.buttonRadius(h)
    return math.max(6, math.floor(h * 0.32))
end

-- A filled or outlined rounded button with a centred label. Used by the in-game
-- dialogs; the menu views keep their own row painters.
function U.button(bb, r, face, label, filled)
    local radius = U.buttonRadius(r.h)
    if filled then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, BLACK_C, radius)
    else
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, WHITE_C, radius)
        bb:paintBorder(r.x, r.y, r.w, r.h, 2, BLACK_C, radius)
    end
    local base = r.y + math.floor(r.h / 2) + math.floor(face.size * 0.35)
    U.centered(bb, r.x + math.floor(r.w / 2), base, face, label, true,
               filled and WHITE_C or BLACK_C)
end

return U
