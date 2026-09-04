-- The screen shown before a game: pick the opponent (another person or the
-- computer) and, for the computer, a difficulty. On Start it hands the choice
-- back through a callback; it does not know about the board.
--
-- Levels are read from bg/ai.lua, so the difficulty list grows on its own as
-- levels are added there.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")

local AI = require("bg/ai")

local Screen = Device.screen
local BLACK_C = Blitbuffer.COLOR_BLACK
local WHITE_C = Blitbuffer.COLOR_WHITE
local GRAY_B = Blitbuffer.COLOR_GRAY_B

local SetupView = InputContainer:extend{
    name = "backgammon_setup",
    covers_fullscreen = true,
}

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end
local function inRect(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

function SetupView:init()
    self.opponent = self.opponent or "human"   -- "human" | "ai"
    self.level = self.level or 1
    -- on_start(opponent, level) is supplied by the caller
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.hit = {}                               -- tap targets, rebuilt each paint
    self:computeLayout()
    if Device:isTouchDevice() then
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function SetupView:computeLayout()
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

--------------------------------------------------------------------------
-- drawing helpers
--------------------------------------------------------------------------

function SetupView:textW(face, s, bold)
    return RenderText:sizeUtf8Text(0, 100000, face, s, false, bold or false).x
end

function SetupView:drawText(bb, x, baseline, face, s, bold, color)
    RenderText:renderUtf8Text(bb, x, baseline, face, s, false, bold or false,
                              color or BLACK_C)
end

function SetupView:drawCentered(bb, cx, baseline, face, s, bold, color)
    self:drawText(bb, cx - math.floor(self:textW(face, s, bold) / 2), baseline, face, s, bold, color)
end

-- A full-width selectable row. Selected rows are filled dark with light text,
-- which reads instantly on e-ink without relying on subtle shading.
function SetupView:drawRow(bb, r, title, subtitle, selected)
    local radius = math.floor(self.unit * 0.35)
    if selected then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, BLACK_C, radius)
    else
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, WHITE_C, radius)
        bb:paintBorder(r.x, r.y, r.w, r.h, 2, BLACK_C, radius)
    end
    local fg = selected and WHITE_C or BLACK_C
    local pad = math.floor(self.unit * 0.8)
    if subtitle then
        self:drawText(bb, r.x + pad, r.y + math.floor(r.h * 0.42) + math.floor(self.face.size * 0.35),
                      self.face, title, true, fg)
        self:drawText(bb, r.x + pad, r.y + math.floor(r.h * 0.72) + math.floor(self.face_small.size * 0.35),
                      self.face_small, subtitle, false, fg)
    else
        self:drawText(bb, r.x + pad, r.y + math.floor(r.h / 2) + math.floor(self.face.size * 0.35),
                      self.face, title, true, fg)
    end
    -- a filled check disc on the right of the selected row
    if selected then
        local cr = math.floor(self.unit * 0.5)
        local cx = r.x + r.w - pad - cr
        local cy = r.y + math.floor(r.h / 2)
        bb:paintCircle(cx, cy, cr, WHITE_C)
        bb:paintCircle(cx, cy, math.floor(cr * 0.5), BLACK_C)
    end
end

function SetupView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local W = Screen:getWidth()
    bb:fill(WHITE_C)
    self.hit = {}

    local cx = math.floor(W / 2)
    local unit = self.unit
    local yy = math.floor(unit * 1.6)

    self:drawCentered(bb, cx, yy + math.floor(self.face_title.size * 0.35),
                      self.face_title, "Backgammon", true)
    yy = yy + math.floor(unit * 2.2)
    self:drawCentered(bb, cx, yy, self.face_small, "Choose your game", false, BLACK_C)
    yy = yy + math.floor(unit * 1.2)

    -- Board & colours (opens the settings screen; persists across sessions)
    local set_lbl = "Board & colours  \u{25B8}"
    local set_w = self:textW(self.face_small, set_lbl, false) + math.floor(unit * 1.6)
    local set_h = math.floor(unit * 1.5)
    local set_r = rect(cx - math.floor(set_w / 2), yy, set_w, set_h)
    bb:paintRoundedRect(set_r.x, set_r.y, set_r.w, set_r.h, WHITE_C, math.floor(unit * 0.3))
    bb:paintBorder(set_r.x, set_r.y, set_r.w, set_r.h, 2, BLACK_C, math.floor(unit * 0.3))
    self:drawCentered(bb, cx, set_r.y + math.floor(set_r.h / 2) + math.floor(self.face_small.size * 0.35),
                      self.face_small, set_lbl, false, BLACK_C)
    self.hit.settings = set_r
    yy = yy + set_h + math.floor(unit * 0.7)

    -- Opponent
    self:drawText(bb, self.col_x, yy, self.face_small, "OPPONENT", true, BLACK_C)
    yy = yy + math.floor(unit * 0.6)

    local r1 = rect(self.col_x, yy, self.col_w, self.row_h)
    self:drawRow(bb, r1, "Two players", "Share the device, take turns",
                 self.opponent == "human")
    self.hit.human = r1
    yy = yy + self.row_h + self.gap

    local r2 = rect(self.col_x, yy, self.col_w, self.row_h)
    self:drawRow(bb, r2, "Play the computer", "One player against the machine",
                 self.opponent == "ai")
    self.hit.ai = r2
    yy = yy + self.row_h + self.gap

    -- footer position is fixed; difficulty rows fit into the space above it
    local H = Screen:getHeight()
    local start_h = math.floor(unit * 3)
    local footer_top = H - start_h - math.floor(unit * 1.6)

    -- Difficulty (only when playing the computer)
    if self.opponent == "ai" then
        yy = yy + math.floor(unit * 0.4)
        self:drawText(bb, self.col_x, yy, self.face_small, "DIFFICULTY", true, BLACK_C)
        yy = yy + math.floor(unit * 0.6)
        self.hit.levels = {}
        local nlv = #AI.levels
        local rgap = math.floor(self.gap * 0.5)
        -- shrink rows if needed so all levels fit above the Start button
        local avail = footer_top - yy - math.floor(unit * 0.4)
        local dh = math.floor((avail - rgap * (nlv - 1)) / nlv)
        if dh > self.row_h then dh = self.row_h end
        for _, lv in ipairs(AI.levels) do
            local r = rect(self.col_x, yy, self.col_w, dh)
            self:drawRow(bb, r, lv.id .. ".  " .. lv.name, lv.desc, self.level == lv.id)
            self.hit.levels[lv.id] = r
            yy = yy + dh + rgap
        end
    end

    -- Start / Close pinned near the bottom
    local start_r = rect(self.col_x, footer_top, self.col_w, start_h)
    bb:paintRoundedRect(start_r.x, start_r.y, start_r.w, start_r.h, BLACK_C, math.floor(unit * 0.4))
    self:drawCentered(bb, cx, start_r.y + math.floor(start_r.h / 2) + math.floor(self.face.size * 0.4),
                      self.face, "Start game", true, WHITE_C)
    self.hit.start = start_r

    local close_w = math.floor(self.col_w * 0.35)
    local close_r = rect(math.floor(W / 2 - close_w / 2), H - math.floor(unit * 1.1), close_w, math.floor(unit * 1.4))
    self:drawCentered(bb, cx, close_r.y + math.floor(close_r.h / 2) + math.floor(self.face_small.size * 0.35),
                      self.face_small, "Close", false, BLACK_C)
    self.hit.close = close_r
end

--------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------

function SetupView:onShow()
    UIManager:setDirty(self, "flashui")
    return true
end

function SetupView:onClose()
    UIManager:close(self)
    return true
end

function SetupView:onTap(_, ges)
    local x, y = ges.pos.x, ges.pos.y
    local hit = self.hit

    if inRect(hit.close, x, y) then
        UIManager:close(self)
        return true
    end
    if inRect(hit.settings, x, y) then
        local SettingsView = require("bg/settingsview")
        UIManager:show(SettingsView:new{
            on_close = function() UIManager:setDirty(self, "flashui") end,
        })
        return true
    end
    if inRect(hit.start, x, y) then
        local opponent, level = self.opponent, self.level
        UIManager:close(self)
        if self.on_start then self.on_start(opponent, level) end
        return true
    end
    if inRect(hit.human, x, y) then
        if self.opponent ~= "human" then
            self.opponent = "human"
            UIManager:setDirty(self, "ui")
        end
        return true
    end
    if inRect(hit.ai, x, y) then
        if self.opponent ~= "ai" then
            self.opponent = "ai"
            UIManager:setDirty(self, "ui")
        end
        return true
    end
    if hit.levels then
        for id, r in pairs(hit.levels) do
            if inRect(r, x, y) then
                self.level = id
                UIManager:setDirty(self, "ui")
                return true
            end
        end
    end
    return true
end

return SetupView
