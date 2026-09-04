-- The "Board & colours" screen, reached from the opponent picker. Sets which
-- colour player 1 (the person seeing the device logo upright) plays and which
-- bottom corner they bear off to. Choices are saved immediately and persist
-- across sessions; they are applied when the next game starts.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local Settings = require("bg/settings")

local Screen = Device.screen
local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE

local SettingsView = InputContainer:extend{
    name = "backgammon_settings",
    covers_fullscreen = true,
}

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end
local function inRect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function SettingsView:init()
    self.user_color = Settings.get("user_color")
    self.bear_off = Settings.get("bear_off")
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function SettingsView:computeLayout()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local unit = math.floor(math.min(W, H) * 0.045)
    if unit < 15 then unit = 15 end
    self.unit = unit
    self.col_w = math.min(math.floor(W * 0.86), unit * 26)
    self.col_x = math.floor((W - self.col_w) / 2)
    self.row_h = math.floor(unit * 2.6)
    self.gap = math.floor(unit * 0.7)
    local dpi = Screen:scaleBySize(1000) / 1000
    self.face_title = Font:getFace("cfont", math.floor(unit * 1.7 / dpi))
    self.face = Font:getFace("cfont", math.floor(unit * 0.95 / dpi))
    self.face_small = Font:getFace("cfont", math.floor(unit * 0.72 / dpi))
end

function SettingsView:textW(face, s, bold)
    return RenderText:sizeUtf8Text(0, 100000, face, s, false, bold or false).x
end
function SettingsView:drawText(bb, x, baseline, face, s, bold, color)
    RenderText:renderUtf8Text(bb, x, baseline, face, s, false, bold or false, color or BLACK_C)
end
function SettingsView:drawCentered(bb, cx, baseline, face, s, bold, color)
    self:drawText(bb, cx - math.floor(self:textW(face, s, bold) / 2), baseline, face, s, bold, color)
end

-- Two side-by-side choices; the selected one is filled dark with light text.
function SettingsView:drawChoice(bb, r, label, selected)
    local radius = math.floor(self.unit * 0.35)
    if selected then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, BLACK_C, radius)
    else
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, WHITE_C, radius)
        bb:paintBorder(r.x, r.y, r.w, r.h, 2, BLACK_C, radius)
    end
    self:drawCentered(bb, r.x + math.floor(r.w / 2),
                      r.y + math.floor(r.h / 2) + math.floor(self.face.size * 0.35),
                      self.face, label, true, selected and WHITE_C or BLACK_C)
end

function SettingsView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W = Screen:getWidth()
    bb:fill(WHITE_C)
    self.hit = {}
    local cx = math.floor(W / 2)
    local unit = self.unit
    local yy = math.floor(unit * 1.6)

    self:drawCentered(bb, cx, yy + math.floor(self.face_title.size * 0.35),
                      self.face_title, "Board & colours", true)
    yy = yy + math.floor(unit * 2.4)
    self:drawCentered(bb, cx, yy, self.face_small,
                      "Player 1 sees the device logo the right way up", false, BLACK_C)
    yy = yy + math.floor(unit * 1.6)

    local half = math.floor((self.col_w - self.gap) / 2)

    -- You play
    self:drawText(bb, self.col_x, yy, self.face_small, "PLAYER 1 PLAYS", true, BLACK_C)
    yy = yy + math.floor(unit * 0.6)
    local w1 = rect(self.col_x, yy, half, self.row_h)
    local w2 = rect(self.col_x + half + self.gap, yy, half, self.row_h)
    self:drawChoice(bb, w1, "White", self.user_color == "white")
    self:drawChoice(bb, w2, "Black", self.user_color == "black")
    self.hit.white, self.hit.black = w1, w2
    yy = yy + self.row_h + math.floor(unit * 1.2)

    -- Bear off side
    self:drawText(bb, self.col_x, yy, self.face_small, "BEAR OFF ON THE", true, BLACK_C)
    yy = yy + math.floor(unit * 0.6)
    local b1 = rect(self.col_x, yy, half, self.row_h)
    local b2 = rect(self.col_x + half + self.gap, yy, half, self.row_h)
    self:drawChoice(bb, b1, "Right", self.bear_off == "right")
    self:drawChoice(bb, b2, "Left", self.bear_off == "left")
    self.hit.right, self.hit.left = b1, b2

    -- Done, pinned near the bottom
    local H = Screen:getHeight()
    local done_h = math.floor(unit * 3)
    local done_r = rect(self.col_x, H - done_h - math.floor(unit * 1.6), self.col_w, done_h)
    bb:paintRoundedRect(done_r.x, done_r.y, done_r.w, done_r.h, BLACK_C, math.floor(unit * 0.4))
    self:drawCentered(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                      self.face, "Done", true, WHITE_C)
    self.hit.done = done_r
end

function SettingsView:onShow()
    UIManager:setDirty(self, "flashui")
    return true
end

function SettingsView:onClose()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

function SettingsView:onTap(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    local hit = self.hit
    if inRect(hit.done, x, y) then
        return self:onClose()
    end
    local function pick(key, val, field)
        if self[field] ~= val then
            self[field] = val
            Settings.set(key, val)
            UIManager:setDirty(self, "ui")
        end
    end
    if inRect(hit.white, x, y) then pick("user_color", "white", "user_color")
    elseif inRect(hit.black, x, y) then pick("user_color", "black", "user_color")
    elseif inRect(hit.right, x, y) then pick("bear_off", "right", "bear_off")
    elseif inRect(hit.left, x, y) then pick("bear_off", "left", "bear_off") end
    return true
end

return SettingsView
