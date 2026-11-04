-- The theme picker, opened from "Board & colours". One card per theme, each a
-- small picture of the board, a pair of dice and a button in that theme's own
-- colours. Tapping a card applies it at once (this screen repaints in it) and
-- saves it; the next board, menu and dialog open in the same look.

local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local T = require("bg/i18n")
local Theme = require("bg/theme")
local U = require("bg/uiutil")

local Screen = Device.screen

local ThemeView = InputContainer:extend{ name = "backgammon_theme", covers_fullscreen = true }

local rect, inRect = U.rect, U.inRect

function ThemeView:init()
    require("bg/i18n").refresh()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
end

function ThemeView:computeLayout()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local unit = math.floor(math.min(W, H) * 0.045)
    if unit < 15 then unit = 15 end
    self.unit = unit
    self.col_w = math.min(math.floor(W * 0.86), unit * 26)
    self.col_x = math.floor((W - self.col_w) / 2)
    self.gap = math.floor(unit * 0.7)
    local dpi = Screen:scaleBySize(1000) / 1000
    self.face_title = Font:getFace("cfont", math.floor(unit * 1.6 / dpi))
    self.face = Font:getFace("cfont", math.floor(unit * 0.9 / dpi))
    self.face_small = Font:getFace("cfont", math.floor(unit * 0.72 / dpi))
end

function ThemeView:text(bb, x, base, face, s, bold, color)
    U.text(bb, x, base, face, s, bold, color or self.P.ink)
end
function ThemeView:centred(bb, cx, base, face, s, bold, color)
    U.centered(bb, cx, base, face, s, bold, color or self.P.ink)
end

-- A die of side `size` at (x, y) showing `value`, in a theme's colours.
local function miniDie(bb, c, x, y, size, value)
    local rad = math.floor(size * 0.18)
    U.fillRound(bb, x, y, size, size, c.die, rad)
    U.border(bb, x, y, size, size, 2, c.die_edge, rad)
    local pips = { [1] = { { 0.5, 0.5 } }, [5] = { { 0.28, 0.28 }, { 0.72, 0.28 }, { 0.5, 0.5 }, { 0.28, 0.72 }, { 0.72, 0.72 } } }
    local pr = math.max(2, math.floor(size * 0.1))
    for _, p in ipairs(pips[value]) do
        U.paintCircle(bb, x + math.floor(size * p[1]), y + math.floor(size * p[2]), pr,
                      value == 1 and c.one or c.pip)
    end
end

-- One card: a mini board with six points, a white and a black checker and two
-- dice, then the theme's name beside a pill in its button colour.
function ThemeView:card(bb, r, id, selected)
    local P, unit = self.P, self.unit
    local s = Theme.swatch(id)
    local function col(role) return Theme.chip(bb, s[role]) end
    local c = setmetatable({}, { __index = function(t, role) local v = col(role); t[role] = v; return v end })

    local rad = math.floor(unit * 0.4)
    U.fillRound(bb, r.x, r.y, r.w, r.h, c.paper, rad)
    U.border(bb, r.x, r.y, r.w, r.h, selected and 5 or 2, selected and P.select or P.ink, rad)

    -- the board picture
    local pad = math.floor(unit * 0.5)
    local label_h = math.floor(unit * 1.6)
    local bx, by = r.x + pad, r.y + pad
    local bw, bh = r.w - 2 * pad, r.h - 2 * pad - label_h
    U.fillRect(bb, bx, by, bw, bh, c.board)
    U.border(bb, bx, by, bw, bh, 2, c.edge)
    local n = 6
    local pw = math.floor((bw - 4) / n)
    local ph = math.floor(bh * 0.62)
    for i = 0, n - 1 do
        local x = bx + 2 + i * pw
        local color = (i % 2 == 0) and c.pt_a or c.pt_b
        for k = 0, ph - 1 do
            local half = math.floor((pw - 2) / 2 * (1 - k / ph))
            if half > 0 then
                U.fillRect(bb, x + math.floor(pw / 2) - half, by + bh - 2 - k, half * 2, 1, color)
            end
        end
    end
    -- two checkers standing on the points, one of each side
    local cr = math.max(5, math.floor(pw * 0.36))
    local cy = by + bh - 2 - cr
    local x1 = bx + 2 + math.floor(pw / 2)
    U.paintCircle(bb, x1, cy, cr, c.wring)
    U.paintCircle(bb, x1, cy, cr - math.max(2, math.floor(cr * 0.22)), c.wfill)
    local x2 = bx + 2 + 3 * pw + math.floor(pw / 2)
    U.paintCircle(bb, x2, cy, cr, c.bfill)
    U.paintCircle(bb, x2, cy, math.max(2, math.floor(cr * 0.45)), c.bring, 2)
    -- the dice sit above the points, on the open board
    local ds = math.max(10, math.floor(bh * 0.26))
    local dx = bx + bw - 2 * ds - math.floor(ds * 0.5) - 4
    miniDie(bb, c, dx, by + 5, ds, 1)
    miniDie(bb, c, dx + ds + math.floor(ds * 0.3), by + 5, ds, 5)

    -- the name, with a pill in the theme's button colour beside it when there
    -- is room (the long names drop to the smaller face first, then the pill)
    local pill_w, pill_h = math.floor(unit * 1.4), math.floor(unit * 1.0)
    local name = Theme.name(id)
    local room = r.w - 2 * pad
    local face = self.face
    if U.textW(face, name, true) > room - pill_w - pad then face = self.face_small end
    local with_pill = U.textW(face, name, true) <= room - pill_w - pad
    local mid = r.y + r.h - pad - math.floor(label_h / 2)
    self:text(bb, r.x + pad, mid + math.floor(face.size * 0.35), face, name, true, c.ink)
    if with_pill then
        U.fillRound(bb, r.x + r.w - pad - pill_w, mid - math.floor(pill_h / 2), pill_w, pill_h, c.primary,
                    math.floor(pill_h * 0.4))
    end

    if selected then
        -- a check disc on the card's corner, the mark the opponent rows use
        local ccr = math.floor(unit * 0.55)
        local ccx, ccy = r.x + r.w - 4, r.y + 4
        U.paintCircle(bb, ccx, ccy, ccr, P.paper)
        U.paintCircle(bb, ccx, ccy, ccr - 3, P.primary)
        U.paintCircle(bb, ccx, ccy, math.floor(ccr * 0.4), P.primary_text)
    end
end

function ThemeView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Theme.get(bb)
    self.P = P
    U.fill(bb, P.paper)
    self.hit = {}
    local unit, cx = self.unit, math.floor(W / 2)
    local yy = math.floor(unit * 1.5)

    self:centred(bb, cx, yy + math.floor(self.face_title.size * 0.35), self.face_title, T("theme_title"), true)
    yy = yy + math.floor(unit * 2.1)
    self:centred(bb, cx, yy, self.face_small, T("theme_note"), false)
    yy = yy + math.floor(unit * 1.2)

    local ids = Theme.list()
    local done_h = math.floor(unit * 2.8)
    local done_top = H - done_h - math.floor(unit * 1.3)
    local cols = (W > H * 1.2) and 3 or 2
    local rows = math.ceil(#ids / cols)
    local avail = done_top - yy - math.floor(unit * 0.6)
    local card_w = math.floor((self.col_w - self.gap * (cols - 1)) / cols)
    local card_h = math.min(math.floor((avail - self.gap * (rows - 1)) / rows), math.floor(card_w * 0.9))
    local cur = Theme.id()
    for i, id in ipairs(ids) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local r = rect(self.col_x + col * (card_w + self.gap), yy + row * (card_h + self.gap), card_w, card_h)
        self:card(bb, r, id, id == cur)
        self.hit[id] = r
    end

    local done_r = rect(self.col_x, done_top, self.col_w, done_h)
    U.fillRound(bb, done_r.x, done_r.y, done_r.w, done_r.h, P.primary, math.floor(unit * 0.4))
    self:centred(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                 self.face, T("done"), true, P.primary_text)
    self.hit.done = done_r
end

function ThemeView:onShow() UIManager:setDirty(self, "flashui"); return true end

function ThemeView:onClose()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

function ThemeView:onTap(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    if inRect(self.hit.done, x, y) then return self:onClose() end
    for _, id in ipairs(Theme.list()) do
        if inRect(self.hit[id], x, y) then
            if id ~= Theme.id() then
                Theme.set(id)
                -- the whole screen changes colour, so a full flashing refresh
                UIManager:setDirty(self, "flashui")
            end
            return true
        end
    end
    return true
end

return ThemeView
