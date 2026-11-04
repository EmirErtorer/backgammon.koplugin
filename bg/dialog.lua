-- A question with one or two buttons, painted in the active theme. It stands in
-- for KOReader's stock ConfirmBox, whose white box and black outline cannot take
-- the theme's colours, and takes the same fields:
--   text, ok_text, ok_callback, cancel_text (optional), cancel_callback (optional)
-- plus dismissable (default true): tapping outside the box or pressing Back then
-- counts as cancelling. The take-or-drop question turns it off, so a stray tap
-- cannot decide a double.

local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local Theme = require("bg/theme")
local U = require("bg/uiutil")

local Screen = Device.screen

local Dialog = InputContainer:extend{ name = "backgammon_dialog", dismissable = true }

-- Break `text` into lines no wider than `max_w`, at spaces.
local function wrap(face, text, max_w)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        local try = (line == "") and word or (line .. " " .. word)
        if line ~= "" and U.textW(face, try, false) > max_w then
            lines[#lines + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

function Dialog:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local unit = math.floor(math.min(W, H) * 0.045)
    if unit < 15 then unit = 15 end
    self.unit = unit
    local dpi = Screen:scaleBySize(1000) / 1000
    self.face = Font:getFace("cfont", math.floor(unit * 0.95 / dpi))
    self.face_btn = Font:getFace("cfont", math.floor(unit * 0.9 / dpi))

    local pad = math.floor(unit * 0.9)
    local card_w = math.min(math.floor(W * 0.86), unit * 20)
    self.lines = wrap(self.face, self.text or "", card_w - 2 * pad)
    local line_h = math.floor(unit * 1.4)
    local btn_h = math.floor(unit * 2.4)
    local card_h = pad * 2 + #self.lines * line_h + math.floor(unit * 0.6) + btn_h
    self.pad, self.line_h, self.btn_h = pad, line_h, btn_h
    -- a little above the middle, where the eye is on a board
    self.dimen = Geom:new{ x = math.floor((W - card_w) / 2), y = math.floor((H - card_h) * 0.4),
                           w = card_w, h = card_h }
    self.hit = {}
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = W, h = H } } }
    end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
end

function Dialog:paintTo(bb, x, y)
    local P = Theme.get(bb)
    local d, unit, pad = self.dimen, self.unit, self.pad
    local rad = math.floor(unit * 0.5)
    U.fillRound(bb, d.x, d.y, d.w, d.h, P.board, rad)
    U.border(bb, d.x, d.y, d.w, d.h, 3, P.ink, rad)

    local base = d.y + pad + math.floor(self.face.size * 0.8)
    for _, line in ipairs(self.lines) do
        U.centered(bb, d.x + math.floor(d.w / 2), base, self.face, line, false, P.ink)
        base = base + self.line_h
    end

    -- buttons: Cancel (outline) on the left, OK (filled) on the right
    local by = d.y + d.h - pad - self.btn_h
    local two = self.cancel_text ~= nil
    local gap = math.floor(unit * 0.6)
    local bw = two and math.floor((d.w - 2 * pad - gap) / 2) or (d.w - 2 * pad)
    local brad = math.floor(unit * 0.4)
    self.hit = {}
    local function button(r, label, filled)
        if filled then
            U.fillRound(bb, r.x, r.y, r.w, r.h, P.primary, brad)
        else
            U.fillRound(bb, r.x, r.y, r.w, r.h, P.btn, brad)
            U.border(bb, r.x, r.y, r.w, r.h, 2, P.ink, brad)
        end
        U.centered(bb, r.x + math.floor(r.w / 2),
                   r.y + math.floor(r.h / 2) + math.floor(self.face_btn.size * 0.35),
                   self.face_btn, label, true, filled and P.primary_text or P.ink)
    end
    if two then
        self.hit.cancel = U.rect(d.x + pad, by, bw, self.btn_h)
        button(self.hit.cancel, self.cancel_text, false)
    end
    self.hit.ok = U.rect(d.x + d.w - pad - bw, by, bw, self.btn_h)
    button(self.hit.ok, self.ok_text or "OK", true)
end

function Dialog:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

-- Close, then run the callback of the answer.
function Dialog:answer(which)
    UIManager:close(self)
    local cb = (which == "ok") and self.ok_callback or self.cancel_callback
    if cb then cb() end
end

function Dialog:onClose()
    if self.dismissable then self:answer("cancel") end
    return true
end

function Dialog:onTap(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    if U.inRect(self.hit.ok, x, y) then
        self:answer("ok")
    elseif U.inRect(self.hit.cancel, x, y) then
        self:answer("cancel")
    elseif not U.inRect(self.dimen, x, y) and self.dismissable then
        self:answer("cancel")
    end
    return true
end

return Dialog
