-- The "Board & colours" screen, reached from the opponent picker. Sets which
-- colour player 1 (the person seeing the device logo upright) plays, which
-- bottom corner they bear off to, whether the board flips to face the player on
-- move (two-player), and the UI language. Choices are saved immediately and
-- persist across sessions; they apply when the next game starts.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local Settings = require("bg/settings")
local T = require("bg/i18n")

local Screen = Device.screen
local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE

local SettingsView = InputContainer:extend{ name = "backgammon_settings", covers_fullscreen = true }

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end
local function inRect(r, x, y) return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

function SettingsView:init()
    require("bg/i18n").refresh()
    self.user_color = Settings.get("user_color")
    self.bear_off = Settings.get("bear_off")
    self.flip_turns = Settings.get("flip_turns")
    self.lang = Settings.get("language")
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
end

function SettingsView:computeLayout()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local unit = math.floor(math.min(W, H) * 0.045)
    if unit < 15 then unit = 15 end
    self.unit = unit
    self.col_w = math.min(math.floor(W * 0.86), unit * 26)
    self.col_x = math.floor((W - self.col_w) / 2)
    self.row_h = math.floor(unit * 2.1)
    self.gap = math.floor(unit * 0.7)
    local dpi = Screen:scaleBySize(1000) / 1000
    self.face_title = Font:getFace("cfont", math.floor(unit * 1.6 / dpi))
    self.face = Font:getFace("cfont", math.floor(unit * 0.9 / dpi))
    self.face_small = Font:getFace("cfont", math.floor(unit * 0.72 / dpi))
end

function SettingsView:textW(face, s, b) return RenderText:sizeUtf8Text(0, 100000, face, s, false, b or false).x end
function SettingsView:drawText(bb, x, base, face, s, b, color)
    RenderText:renderUtf8Text(bb, x, base, face, s, false, b or false, color or BLACK_C)
end
function SettingsView:drawCentered(bb, cx, base, face, s, b, color)
    self:drawText(bb, cx - math.floor(self:textW(face, s, b) / 2), base, face, s, b, color)
end

function SettingsView:drawChoice(bb, r, label, selected)
    local radius = math.floor(self.unit * 0.3)
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

-- a labelled section with N side-by-side choices; fills self.hit[keys[i]]
function SettingsView:section(bb, yy, header, options, current)
    local unit = self.unit
    self:drawText(bb, self.col_x, yy, self.face_small, header, true, BLACK_C)
    yy = yy + math.floor(unit * 0.55)
    local n = #options
    local w = math.floor((self.col_w - self.gap * (n - 1)) / n)
    for i, opt in ipairs(options) do
        local r = rect(self.col_x + (i - 1) * (w + self.gap), yy, w, self.row_h)
        self:drawChoice(bb, r, opt.label, current == opt.value)
        self.hit[opt.hit] = r
    end
    return yy + self.row_h + math.floor(unit * 0.95)
end

function SettingsView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W, H = Screen:getWidth(), Screen:getHeight()
    bb:fill(WHITE_C)
    self.hit = {}
    local cx = math.floor(W / 2)
    local unit = self.unit
    local yy = math.floor(unit * 1.5)

    self:drawCentered(bb, cx, yy + math.floor(self.face_title.size * 0.35),
                      self.face_title, T("settings_title"), true)
    yy = yy + math.floor(unit * 2.1)
    self:drawCentered(bb, cx, yy, self.face_small, T("player1_note"), false, BLACK_C)
    yy = yy + math.floor(unit * 1.3)

    yy = self:section(bb, yy, T("player1_plays"), {
        { label = T("white"), value = "white", hit = "white" },
        { label = T("black"), value = "black", hit = "black" },
    }, self.user_color)
    yy = self:section(bb, yy, T("bear_off_on"), {
        { label = T("left"), value = "left", hit = "left" },
        { label = T("right"), value = "right", hit = "right" },
    }, self.bear_off)
    yy = self:section(bb, yy, T("flip_each_turn"), {
        { label = T("on"), value = "on", hit = "flip_on" },
        { label = T("off"), value = "off", hit = "flip_off" },
    }, self.flip_turns)
    yy = self:section(bb, yy, T("language"), {
        { label = T("lang_auto"), value = "auto", hit = "lang_auto" },
        { label = T("lang_en"), value = "en", hit = "lang_en" },
        { label = T("lang_tr"), value = "tr", hit = "lang_tr" },
    }, self.lang)

    local done_h = math.floor(unit * 2.8)
    local done_r = rect(self.col_x, H - done_h - math.floor(unit * 1.3), self.col_w, done_h)
    bb:paintRoundedRect(done_r.x, done_r.y, done_r.w, done_r.h, BLACK_C, math.floor(unit * 0.4))
    self:drawCentered(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                      self.face, T("done"), true, WHITE_C)
    self.hit.done = done_r
end

function SettingsView:onShow() UIManager:setDirty(self, "flashui"); return true end

function SettingsView:onClose()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

function SettingsView:onTap(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    local hit = self.hit
    if inRect(hit.done, x, y) then return self:onClose() end

    local function set(field, key, val)
        if self[field] ~= val then
            self[field] = val
            Settings.set(key, val)
            if key == "language" then require("bg/i18n").refresh() end   -- re-render translated
            UIManager:setDirty(self, "ui")
        end
    end
    if inRect(hit.white, x, y) then set("user_color", "user_color", "white")
    elseif inRect(hit.black, x, y) then set("user_color", "user_color", "black")
    elseif inRect(hit.left, x, y) then set("bear_off", "bear_off", "left")
    elseif inRect(hit.right, x, y) then set("bear_off", "bear_off", "right")
    elseif inRect(hit.flip_on, x, y) then set("flip_turns", "flip_turns", "on")
    elseif inRect(hit.flip_off, x, y) then set("flip_turns", "flip_turns", "off")
    elseif inRect(hit.lang_auto, x, y) then set("lang", "language", "auto")
    elseif inRect(hit.lang_en, x, y) then set("lang", "language", "en")
    elseif inRect(hit.lang_tr, x, y) then set("lang", "language", "tr")
    end
    return true
end

return SettingsView
