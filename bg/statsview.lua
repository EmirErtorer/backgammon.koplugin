-- Lifetime statistics screen: total games, current/best win streak against the
-- computer, and a per-level won/played record. Opened from the start menu.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local AI = require("bg/ai")
local Settings = require("bg/settings")
local T = require("bg/i18n")

local Screen = Device.screen
local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE

local StatsView = InputContainer:extend{ name = "backgammon_stats", covers_fullscreen = true }

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end
local function inRect(r, x, y) return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

function StatsView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
end

function StatsView:computeLayout()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local unit = math.floor(math.min(W, H) * 0.045)
    if unit < 15 then unit = 15 end
    self.unit = unit
    self.col_x = math.floor(W * 0.09)
    self.col_w = W - self.col_x * 2
    local dpi = Screen:scaleBySize(1000) / 1000
    self.face_title = Font:getFace("cfont", math.floor(unit * 1.6 / dpi))
    self.face = Font:getFace("cfont", math.floor(unit * 0.95 / dpi))
    self.face_small = Font:getFace("cfont", math.floor(unit * 0.72 / dpi))
end

function StatsView:tw(face, s, b) return RenderText:sizeUtf8Text(0, 100000, face, s, false, b or false).x end
function StatsView:draw(bb, x, base, face, s, b, color)
    RenderText:renderUtf8Text(bb, x, base, face, s, false, b or false, color or BLACK_C)
end
function StatsView:centre(bb, cx, base, face, s, b, color)
    self:draw(bb, cx - math.floor(self:tw(face, s, b) / 2), base, face, s, b, color)
end

function StatsView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W, H = Screen:getWidth(), Screen:getHeight()
    bb:fill(WHITE_C)
    self.hit = {}
    local unit = self.unit
    local cx = math.floor(W / 2)
    local yy = math.floor(unit * 1.6)
    self:centre(bb, cx, yy + math.floor(self.face_title.size * 0.35), self.face_title, T("stats_title"), true)
    yy = yy + math.floor(unit * 2.4)

    local games = Settings.getStat("games")
    if games == 0 then
        self:centre(bb, cx, math.floor(H / 2), self.face, T("no_games_yet"))
    else
        self:draw(bb, self.col_x, yy, self.face, T("games_played") .. ":  " .. games)
        yy = yy + math.floor(unit * 1.6)
        self:draw(bb, self.col_x, yy, self.face,
            T("win_streak") .. ":  " .. Settings.getStat("streak")
            .. "  (" .. T("best_streak", Settings.getStat("best_streak")) .. ")")
        yy = yy + math.floor(unit * 2.0)
        self:draw(bb, self.col_x, yy, self.face_small, T("vs_computer"), true)
        yy = yy + math.floor(unit * 1.2)
        for _, lv in ipairs(AI.levels) do
            local played = Settings.getStat("ai_played_" .. lv.id)
            local won = Settings.getStat("ai_won_" .. lv.id)
            local name = T("lvl" .. lv.id .. "_name")
            self:draw(bb, self.col_x + unit, yy, self.face, name)
            local pct = played > 0 and math.floor(won / played * 100 + 0.5) or 0
            local rec = T("record_fmt", won, played, pct)
            self:draw(bb, self.col_x + self.col_w - self:tw(self.face, rec), yy, self.face, rec)
            yy = yy + math.floor(unit * 1.5)
        end
    end

    local done_h = math.floor(unit * 3)
    local done_r = rect(self.col_x, H - done_h - math.floor(unit * 1.4), self.col_w, done_h)
    bb:paintRoundedRect(done_r.x, done_r.y, done_r.w, done_r.h, BLACK_C, math.floor(unit * 0.4))
    self:centre(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                self.face, T("done"), false, WHITE_C)
    self.hit.done = done_r
end

function StatsView:onShow() UIManager:setDirty(self, "flashui"); return true end
function StatsView:onClose()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end
function StatsView:onTap(_, ges)
    if inRect(self.hit.done, ges.pos.x, ges.pos.y) then return self:onClose() end
    return true
end

return StatsView
