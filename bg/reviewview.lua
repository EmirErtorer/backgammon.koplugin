-- Post-game review screen. Shows, in plain terms, how often you found the best
-- move and where you gave up the most winning chances -- with the reason where
-- one can be stated, and a takeaway tip. Opened from the board when a game ends.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local R = require("bg/rules")
local Review = require("bg/review")
local T = require("bg/i18n")
local U = require("bg/uiutil")

local Screen = Device.screen
local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE
local GRAY = Blitbuffer.COLOR_GRAY_5

local ReviewView = InputContainer:extend{ name = "backgammon_review", covers_fullscreen = true }

local rect, inRect = U.rect, U.inRect

function ReviewView:init()
    self.history = self.history or {}
    -- self.ai_side (optional): when set, only the human's play is reviewed
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}
    self.ready = false
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self._analyse = function()
        self.data = Review.analyse(self.history)
        self.ready = true
        UIManager:setDirty(self, "ui")
    end
end

function ReviewView:computeLayout()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local unit = math.floor(math.min(W, H) * 0.045)
    if unit < 15 then unit = 15 end
    self.unit = unit
    self.col_x = math.floor(W * 0.08)
    self.col_w = W - self.col_x * 2
    local dpi = Screen:scaleBySize(1000) / 1000
    self.face_title = Font:getFace("cfont", math.floor(unit * 1.5 / dpi))
    self.face = Font:getFace("cfont", math.floor(unit * 0.92 / dpi))
    self.face_small = Font:getFace("cfont", math.floor(unit * 0.74 / dpi))
end

function ReviewView:tw(face, s, b) return U.textW(face, s, b) end
function ReviewView:draw(bb, x, base, face, s, b, color)
    U.text(bb, x, base, face, s, b, color)
end
function ReviewView:centre(bb, cx, base, face, s, b, color)
    U.centered(bb, cx, base, face, s, b, color)
end

local function label(self, side)
    if self.ai_side then return T("you") end
    return (side == R.WHITE) and T("white") or T("black")
end

local function tipFor(p)
    if p.hits_missed >= 2 then return T("review_tip_hit") end
    if p.points_missed >= 2 then return T("review_tip_point") end
    local big = 0
    for _, m in ipairs(p.worst) do if m.drop >= 0.06 then big = big + 1 end end
    if big >= 2 then return T("review_tip_safe") end
    return nil
end

function ReviewView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W, H = Screen:getWidth(), Screen:getHeight()
    bb:fill(WHITE_C)
    self.hit = {}
    local unit = self.unit
    local cx = math.floor(W / 2)
    local yy = math.floor(unit * 1.5)
    self:centre(bb, cx, yy + math.floor(self.face_title.size * 0.35), self.face_title, T("review_title"), true)
    yy = yy + math.floor(unit * 2.0)

    local bottom_limit = H - unit * 5
    if not self.ready then
        self:centre(bb, cx, math.floor(H / 2), self.face, T("review_working"))
    else
        local sides = self.ai_side and { -self.ai_side } or { R.WHITE, R.BLACK }
        local per_side = (#sides > 1) and 2 or 3
        for _, side in ipairs(sides) do
            local p = self.data[side]
            local name = label(self, side)
            -- accuracy headline
            local head = (p.best == p.total and p.total > 0)
                and T("review_flawless", name) or T("review_accuracy", name, p.best, p.total)
            self:draw(bb, self.col_x, yy, self.face, head, true)
            yy = yy + math.floor(unit * 1.5)
            -- the biggest lessons
            local shown = 0
            for _, m in ipairs(p.worst) do
                if m.drop >= 0.02 and shown < per_side and yy < bottom_limit then
                    self:draw(bb, self.col_x + unit, yy, self.face_small,
                              T("review_turn_drop", m.n, math.floor(m.drop * 100 + 0.5)))
                    yy = yy + math.floor(unit * 1.0)
                    self:draw(bb, self.col_x + unit, yy, self.face_small,
                              T("review_you", m.actual) .. "      " .. T("review_better", m.best))
                    yy = yy + math.floor(unit * 1.0)
                    if m.reason then
                        self:draw(bb, self.col_x + unit, yy, self.face_small,
                                  "\u{2192} " .. T("reason_" .. m.reason), false, GRAY)
                        yy = yy + math.floor(unit * 1.0)
                    end
                    yy = yy + math.floor(unit * 0.3)
                    shown = shown + 1
                end
            end
            if shown == 0 and p.total > 0 and p.best < p.total then
                -- only tiny slips, nothing worth calling out
                self:draw(bb, self.col_x + unit, yy, self.face_small, T("review_none"))
                yy = yy + math.floor(unit * 1.2)
            end
            local tip = tipFor(p)
            if tip and yy < bottom_limit then
                self:draw(bb, self.col_x, yy, self.face_small, tip, false, GRAY)
                yy = yy + math.floor(unit * 1.3)
            end
            yy = yy + math.floor(unit * 0.5)
        end
    end

    local done_h = math.floor(unit * 2.8)
    local done_r = rect(self.col_x, H - done_h - math.floor(unit * 1.3), self.col_w, done_h)
    bb:paintRoundedRect(done_r.x, done_r.y, done_r.w, done_r.h, BLACK_C, math.floor(unit * 0.4))
    self:centre(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                self.face, T("done"), false, WHITE_C)
    self.hit.done = done_r
end

function ReviewView:onShow()
    UIManager:setDirty(self, "flashui")
    UIManager:scheduleIn(0.05, self._analyse)
    return true
end

function ReviewView:onClose()
    if self._analyse then UIManager:unschedule(self._analyse) end
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

function ReviewView:onTap(_, ges)
    if inRect(self.hit.done, ges.pos.x, ges.pos.y) then return self:onClose() end
    return true
end

return ReviewView
