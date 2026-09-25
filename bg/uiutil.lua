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
