-- Post-game review screen: runs the analysis and lists the turns where each
-- side lost the most ground against the GNU net's choice. Opened from the board
-- when a game ends.

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

local Screen = Device.screen
local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE

local ReviewView = InputContainer:extend{ name = "backgammon_review", covers_fullscreen = true }

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end
local function inRect(r, x, y) return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

function ReviewView:init()
    self.history = self.history or {}
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}
    self.ready = false
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
    self._analyse = function()
        self.turns, self.counts = Review.analyse(self.history)
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
    self.face_title = Font:getFace("cfont", math.floor(unit * 1.6 / dpi))
    self.face = Font:getFace("cfont", math.floor(unit * 0.9 / dpi))
    self.face_small = Font:getFace("cfont", math.floor(unit * 0.72 / dpi))
end

function ReviewView:tw(face, s) return RenderText:sizeUtf8Text(0, 100000, face, s, false, false).x end
function ReviewView:draw(bb, x, base, face, s, color)
    RenderText:renderUtf8Text(bb, x, base, face, s, false, false, color or BLACK_C)
end
function ReviewView:centre(bb, cx, base, face, s, color)
    self:draw(bb, cx - math.floor(self:tw(face, s) / 2), base, face, s, color)
end

function ReviewView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W, H = Screen:getWidth(), Screen:getHeight()
    bb:fill(WHITE_C)
    self.hit = {}
    local unit = self.unit
    local cx = math.floor(W / 2)
    local yy = math.floor(unit * 1.6)
    self:centre(bb, cx, yy + math.floor(self.face_title.size * 0.35), self.face_title, T("review_title"))
    yy = yy + math.floor(unit * 2.2)

    if not self.ready then
        self:centre(bb, cx, math.floor(H / 2), self.face, T("review_working"))
    else
        local function label(color) return (color == R.WHITE) and T("white") or T("black") end
        for _, color in ipairs({ R.WHITE, R.BLACK }) do
            local c = self.counts[color]
            self:draw(bb, self.col_x, yy, self.face, T("review_summary", label(color), c.blunder, c.slip))
            yy = yy + math.floor(unit * 1.5)
        end
        yy = yy + math.floor(unit * 0.4)
        -- worst turns (only those that actually lost ground)
        local shown = 0
        for _, t in ipairs(self.turns) do
            if t.loss >= 0.02 and shown < 7 and yy < H - unit * 5 then
                local line = T("review_line", t.n, label(t.player), t.actual, t.loss)
                self:draw(bb, self.col_x, yy, self.face_small, line)
                yy = yy + math.floor(unit * 1.05)
                self:draw(bb, self.col_x + unit, yy, self.face_small, T("review_best", t.best))
                yy = yy + math.floor(unit * 1.3)
                shown = shown + 1
            end
        end
        if shown == 0 then
            self:centre(bb, cx, yy + unit, self.face, T("review_none"))
        end
    end

    local done_h = math.floor(unit * 3)
    local done_r = rect(self.col_x, H - done_h - math.floor(unit * 1.4), self.col_w, done_h)
    bb:paintRoundedRect(done_r.x, done_r.y, done_r.w, done_r.h, BLACK_C, math.floor(unit * 0.4))
    self:centre(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                self.face, T("done"), WHITE_C)
    self.hit.done = done_r
end

function ReviewView:onShow()
    UIManager:setDirty(self, "flashui")
    UIManager:scheduleIn(0.05, self._analyse)   -- compute after "Analysing…" paints
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
