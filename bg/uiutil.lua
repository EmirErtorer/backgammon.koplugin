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

-- Colour painting. KOReader's plain paintRect, paintRoundedRect, paintBorder,
-- fill and text all flatten the colour they are given to a grey, on every
-- buffer type; only their RGB32 variants keep it. A coloured theme is made of
-- ColorRGB32 values (see bg/theme.lua) and a grey theme of Color8, so the
-- colour tells which painter to use, and the grey path stays the original one.
local ok_ffi, ffi = pcall(require, "ffi")
local RGB32 = Blitbuffer.ColorRGB32

local function isRGB(c)
    return ok_ffi and RGB32 ~= nil and type(c) == "cdata" and ffi.istype(RGB32, c) or false
end
U.isRGB = isRGB

-- fill the whole buffer
function U.fill(bb, c)
    if isRGB(c) then
        bb:paintRectRGB32(0, 0, bb:getWidth(), bb:getHeight(), c)
    else
        bb:fill(c)
    end
end

function U.fillRect(bb, x, y, w, h, c)
    if isRGB(c) then bb:paintRectRGB32(x, y, w, h, c) else bb:paintRect(x, y, w, h, c) end
end

function U.fillRound(bb, x, y, w, h, c, r)
    if isRGB(c) then bb:paintRoundedRectRGB32(x, y, w, h, c, r) else bb:paintRoundedRect(x, y, w, h, c, r) end
end

function U.border(bb, x, y, w, h, bw, c, r)
    if isRGB(c) then bb:paintBorderRGB32(x, y, w, h, bw, c, r) else bb:paintBorder(x, y, w, h, bw, c, r) end
end

function U.rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function U.inRect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- width of `s` in `face`, optionally bold
function U.textW(face, s, bold)
    return RenderText:sizeUtf8Text(0, 100000, face, s, false, bold or false).x
end

-- What RenderText draws into when the text is coloured. It only ever asks its
-- destination for the width and to colour-blit each glyph, and the plain
-- colorblitFrom would flatten the colour to a grey, so this passes both on and
-- sends the glyphs through colorblitFromRGB32 instead.
local function colourTarget(bb)
    return {
        getWidth = function() return bb:getWidth() end,
        colorblitFrom = function(_, src, dx, dy, ox, oy, w, h, color)
            bb:colorblitFromRGB32(src, dx, dy, ox, oy, w, h, color)
        end,
    }
end

-- draw `s` at (x, baseline)
function U.text(bb, x, baseline, face, s, bold, color)
    color = color or BLACK_C
    if isRGB(color) then
        RenderText:renderUtf8Text(colourTarget(bb), x, baseline, face, s, false, bold or false, color)
    else
        RenderText:renderUtf8Text(bb, x, baseline, face, s, false, bold or false, color)
    end
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
    local paintRect = isRGB(c) and bb.paintRectRGB32 or bb.paintRect
    if w == nil or w > r then w = r end
    local r2 = r - w
    -- the four axis spokes
    local n = r - r2
    if n > 0 then
        paintRect(bb, cx, cy + r2 + 1, 1, n, c)
        paintRect(bb, cx, cy - r, 1, n, c)
        paintRect(bb, cx + r2 + 1, cy, n, 1, c)
        paintRect(bb, cx - r, cy, n, 1, c)
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
            paintRect(bb, cx + x, cy + y2 + 1, 1, n, c)
            paintRect(bb, cx + y2 + 1, cy + x, n, 1, c)
            paintRect(bb, cx + y2 + 1, cy - x, n, 1, c)
            paintRect(bb, cx + x, cy - y, 1, n, c)
            paintRect(bb, cx - x, cy - y, 1, n, c)
            paintRect(bb, cx - y, cy - x, n, 1, c)
            paintRect(bb, cx - y, cy + x, n, 1, c)
            paintRect(bb, cx - x, cy + y2 + 1, 1, n, c)
        end
    end
    if r == w then paintRect(bb, cx, cy, 1, 1, c) end
end

-- A comfortable corner radius for a button of height `h`, so the rounded-square
-- look scales with the control and stays consistent across screens.
function U.buttonRadius(h)
    return math.max(6, math.floor(h * 0.32))
end

-- A filled or outlined rounded button with a centred label. Used by the in-game
-- dialogs; the menu views keep their own row painters.
function U.button(bb, r, face, label, filled, P)
    local radius = U.buttonRadius(r.h)
    local ink, paper = P and P.ink or BLACK_C, P and P.btn or WHITE_C
    if filled then
        U.fillRound(bb, r.x, r.y, r.w, r.h, P and P.primary or BLACK_C, radius)
    else
        U.fillRound(bb, r.x, r.y, r.w, r.h, paper, radius)
        U.border(bb, r.x, r.y, r.w, r.h, 2, ink, radius)
    end
    local base = r.y + math.floor(r.h / 2) + math.floor(face.size * 0.35)
    U.centered(bb, r.x + math.floor(r.w / 2), base, face, label, true,
               filled and (P and P.primary_text or WHITE_C) or ink)
end

return U
