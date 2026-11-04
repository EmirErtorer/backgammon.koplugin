-- The "Board & colours" screen, reached from the opponent picker. Sets which
-- colour player 1 (the person seeing the device logo upright) plays, which
-- bottom corner they bear off to, whether the board flips to face the player on
-- move (two-player), and the UI language. Choices are saved immediately and
-- persist across sessions; they apply when the next game starts.

local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local Settings = require("bg/settings")
local T = require("bg/i18n")
local Theme = require("bg/theme")
local U = require("bg/uiutil")

local Screen = Device.screen

local SettingsView = InputContainer:extend{ name = "backgammon_settings", covers_fullscreen = true }

local rect, inRect = U.rect, U.inRect

function SettingsView:init()
    require("bg/i18n").refresh()
    self.user_color = Settings.get("user_color")
    self.bear_off = Settings.get("bear_off")
    self.flip_turns = Settings.get("flip_turns")
    self.cube = Settings.get("cube")
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

function SettingsView:textW(face, s, b) return U.textW(face, s, b) end
function SettingsView:drawText(bb, x, base, face, s, b, color)
    U.text(bb, x, base, face, s, b, color or self.P.ink)
end
function SettingsView:drawCentered(bb, cx, base, face, s, b, color)
    U.centered(bb, cx, base, face, s, b, color or self.P.ink)
end

function SettingsView:drawChoice(bb, r, label, selected)
    local P = self.P
    local radius = math.floor(self.unit * 0.3)
    if selected then
        U.fillRound(bb, r.x, r.y, r.w, r.h, P.primary, radius)
    else
        U.fillRound(bb, r.x, r.y, r.w, r.h, P.btn, radius)
        U.border(bb, r.x, r.y, r.w, r.h, 2, P.ink, radius)
    end
    self:drawCentered(bb, r.x + math.floor(r.w / 2),
                      r.y + math.floor(r.h / 2) + math.floor(self.face.size * 0.35),
                      self.face, label, true, selected and P.primary_text or P.ink)
end

-- a labelled section with N side-by-side choices; fills self.hit[keys[i]]
function SettingsView:section(bb, yy, header, options, current)
    local unit = self.unit
    self:drawText(bb, self.col_x, yy, self.face_small, header, true)
    yy = yy + math.floor(unit * 0.55)
    local n = #options
    local w = math.floor((self.col_w - self.gap * (n - 1)) / n)
    for i, opt in ipairs(options) do
        local r = rect(self.col_x + (i - 1) * (w + self.gap), yy, w, self.row_h)
        self:drawChoice(bb, r, opt.label, current == opt.value)
        self.hit[opt.hit] = r
    end
    return yy + self.row_h + self.sec_gap
end

-- The theme row: the current theme's name between a strip of its colours and an
-- arrow. Tapping it opens the picker. Only colour screens have themes.
function SettingsView:themeRow(bb, yy, header)
    local P, unit = self.P, self.unit
    self:drawText(bb, self.col_x, yy, self.face_small, header, true)
    yy = yy + math.floor(unit * 0.55)
    local r = rect(self.col_x, yy, self.col_w, self.row_h)
    local radius = math.floor(unit * 0.3)
    U.fillRound(bb, r.x, r.y, r.w, r.h, P.btn, radius)
    U.border(bb, r.x, r.y, r.w, r.h, 2, P.ink, radius)
    local pad = math.floor(unit * 0.6)
    local id = Theme.id()
    local sw = Theme.swatch(id)
    -- five chips: board, the two points, a white and a black checker
    local chip = math.floor(self.row_h * 0.42)
    local x = r.x + pad
    local cy = r.y + math.floor(r.h / 2)
    for _, role in ipairs({ "board", "pt_a", "pt_b", "wfill", "bfill" }) do
        local c = Theme.chip(bb, sw[role])
        U.fillRound(bb, x, cy - math.floor(chip / 2), chip, chip, c, math.floor(chip * 0.3))
        U.border(bb, x, cy - math.floor(chip / 2), chip, chip, 1, P.ink, math.floor(chip * 0.3))
        x = x + chip + math.floor(chip * 0.25)
    end
    self:drawText(bb, x + math.floor(unit * 0.5), cy + math.floor(self.face.size * 0.35),
                  self.face, Theme.name(id), true)
    local arrow = "\u{203A}"
    self:drawText(bb, r.x + r.w - pad - self:textW(self.face, arrow, true),
                  cy + math.floor(self.face.size * 0.35), self.face, arrow, true)
    self.hit.theme = r
    return yy + self.row_h + self.sec_gap
end

function SettingsView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Theme.get(bb)
    self.P = P
    U.fill(bb, P.paper)
    self.hit = {}
    local cx = math.floor(W / 2)
    local unit = self.unit
    local yy = math.floor(unit * 1.5)

    self:drawCentered(bb, cx, yy + math.floor(self.face_title.size * 0.35),
                      self.face_title, T("settings_title"), true)
    yy = yy + math.floor(unit * 2.1)
    self:drawCentered(bb, cx, yy, self.face_small, T("player1_note"), false)
    yy = yy + math.floor(unit * 1.3)

    -- Rows are spaced to fit above Done: the sixth section (themes, colour
    -- screens only) and a short screen squeeze the gap between them, then the
    -- rows themselves, rather than running into the button.
    local sections = #Theme.list() > 0 and 6 or 5
    local done_h = math.floor(unit * 2.8)
    local done_top = H - done_h - math.floor(unit * 1.3)
    local per = (done_top - yy - math.floor(unit * 0.3)) / sections
    local head = math.floor(unit * 0.55)
    self.row_h = math.floor(unit * 2.1)
    self.sec_gap = math.floor(unit * 0.95)
    if head + self.row_h + self.sec_gap > per then
        self.sec_gap = math.max(math.floor(unit * 0.2), math.floor(per - head - self.row_h))
        if head + self.row_h + self.sec_gap > per then
            self.row_h = math.max(math.floor(unit * 1.25), math.floor(per - head - self.sec_gap))
        end
    end

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
    yy = self:section(bb, yy, T("doubling_cube"), {
        { label = T("on"), value = "on", hit = "cube_on" },
        { label = T("off"), value = "off", hit = "cube_off" },
    }, self.cube)
    yy = self:section(bb, yy, T("language"), {
        { label = T("lang_auto"), value = "auto", hit = "lang_auto" },
        { label = T("lang_en"), value = "en", hit = "lang_en" },
        { label = T("lang_tr"), value = "tr", hit = "lang_tr" },
    }, self.lang)
    if sections == 6 then yy = self:themeRow(bb, yy, T("theme")) end

    local done_r = rect(self.col_x, done_top, self.col_w, done_h)
    U.fillRound(bb, done_r.x, done_r.y, done_r.w, done_r.h, P.primary, math.floor(unit * 0.4))
    self:drawCentered(bb, cx, done_r.y + math.floor(done_r.h / 2) + math.floor(self.face.size * 0.4),
                      self.face, T("done"), true, P.primary_text)
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
    if inRect(hit.theme, x, y) then
        local ThemeView = require("bg/themeview")
        UIManager:show(ThemeView:new{
            on_close = function() UIManager:setDirty(self, "flashui") end,
        })
        return true
    end

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
    elseif inRect(hit.cube_on, x, y) then set("cube", "cube", "on")
    elseif inRect(hit.cube_off, x, y) then set("cube", "cube", "off")
    elseif inRect(hit.lang_auto, x, y) then set("lang", "language", "auto")
    elseif inRect(hit.lang_en, x, y) then set("lang", "language", "en")
    elseif inRect(hit.lang_tr, x, y) then set("lang", "language", "tr")
    end
    return true
end

return SettingsView
