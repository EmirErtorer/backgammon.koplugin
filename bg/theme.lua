-- The active look: which colours the board, dice and buttons are painted in.
--
-- bg/palettes.lua holds the themes as hex data. This turns the chosen one into
-- Blitbuffer colours for the screen at hand, once, and hands every view the same
-- table of roles (P.ink, P.pt_a ...), so no view names a colour of its own.
--
-- What the screen can show decides what is built:
--   * a black and white screen, or the Classic theme: the original greys, as
--     Color8, through the plain paint calls. Nothing about this path changed.
--   * a colour screen: ColorRGB32 for every role (greys too, so one painter
--     handles a whole palette). The plain paint calls would flatten these to
--     grey, so uiutil paints them with KOReader's RGB32 variants.
--
-- The framebuffer's depth matters as much as the panel. Colour is only used
-- when the buffer being painted is RGB16, RGB24 or RGB32; a Kaleido screen that
-- KOReader runs in greyscale hands over an 8 bit buffer and gets the greys.
-- Sprites are alpha blitted, and the C blitter refuses (and aborts the whole
-- reader) for some pairs of buffer types, so P.sprite says which kind is safe.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")

local Palettes = require("bg/palettes")
local Settings = require("bg/settings")
local T = require("bg/i18n")

local Theme = {}

local TYPE_RGB16, TYPE_RGB24, TYPE_RGB32 =
    Blitbuffer.TYPE_BBRGB16, Blitbuffer.TYPE_BBRGB24, Blitbuffer.TYPE_BBRGB32

-- Bumped whenever the look changes, so views drop anything they cached.
Theme.version = 0

local cache = {}

-- Does the panel show colour? BACKGAMMON_FORCE_MONO previews the grey look in
-- the desktop emulator, which always says yes; a real device never reads it.
function Theme.colourScreen()
    if os.getenv("BACKGAMMON_FORCE_MONO") and Device.isEmulator and Device:isEmulator() then
        return false
    end
    local screen = Device.screen
    if screen and screen.isColorEnabled then
        local ok, on = pcall(screen.isColorEnabled, screen)
        return ok and on == true
    end
    return false
end

-- Is this buffer one that holds colour?
local function colourBuffer(bb)
    local t = bb and bb.getType and bb:getType()
    return t ~= nil and (t == TYPE_RGB16 or t == TYPE_RGB24 or t == TYPE_RGB32)
end

-- "#RRGGBB" to r, g, b.
local function parse(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end
Theme.parse = parse

-- The id of the theme in use. Anything unknown (a setting from a newer version)
-- falls back to the first.
function Theme.id()
    local id = Settings.get("theme")
    if id and Palettes.themes[id] then return id end
    return Palettes.ORDER[1]
end

-- The theme's name in the reader's language.
function Theme.name(id)
    local key = "theme_" .. id
    local name = T(key)
    return name ~= key and name or Palettes.themes[id].name
end

-- The themes this screen can offer, in menu order. A black and white screen
-- only has the one look, so it offers none.
function Theme.list()
    if not Theme.colourScreen() then return {} end
    return Palettes.ORDER
end

-- Classic as grey levels, the constants the views used before themes existed
-- (0x55 is COLOR_GRAY_5, 0xBB COLOR_GRAY_B, 0xAA COLOR_GRAY).
local CLASSIC = {
    paper = 255, board = 255, ink = 0, muted = 0x55, edge = 0,
    pt_a = 0x55, pt_b = 0xBB, bar = 0xAA, tray = 255,
    wfill = 255, wring = 0, bfill = 0, bring = 255,
    select = 0, dest = 0,
    die = 255, pip = 0, spent = 0, die_edge = 0, one = 0,
    btn = 255, primary = 0, primary_text = 255,
    cube = 255, cube_ink = 0,
    off_w = 0xBB, off_b = 0,
}

local function classic()
    local P = {}
    for role, v in pairs(CLASSIC) do P[role] = Blitbuffer.Color8(v) end
    return P
end

-- The roles of a coloured theme as ColorRGB32.
local function coloured(def)
    local P = {}
    for role, hex in pairs(def) do
        if role ~= "name" and role ~= "mono" then
            local r, g, b = parse(hex)
            P[role] = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
        end
    end
    P.edge = P.edge or P.ink
    P.pip = P.pip or P.ink
    P.die_edge = P.die_edge or P.ink
    P.cube_ink = P.cube_ink or P.ink
    P.spent = P.spent or P.muted
    return P
end

-- Which sprite type may be alpha blitted onto this buffer without the C blitter
-- refusing: "bb8a" (grey, the original), "rgb32" (colour) or "direct" (draw each
-- piece onto the board instead of stamping it).
local function spriteKind(bb, is_colour)
    local t = bb and bb.getType and bb:getType()
    if t == TYPE_RGB24 then return "direct" end
    return is_colour and "rgb32" or "bb8a"
end

-- The palette for painting into `bb`: { <role> = colour, ..., colour = bool,
-- sprite = kind, id = theme id }. One table per (theme, buffer type), reused
-- until the theme changes.
function Theme.get(bb)
    local id = Theme.id()
    local t = bb and bb.getType and bb:getType() or 0
    local key = id .. ":" .. tostring(t)
    local P = cache[key]
    if P then return P end
    local def = Palettes.themes[id]
    local is_colour = not def.mono and Theme.colourScreen() and colourBuffer(bb)
    P = is_colour and coloured(def) or classic()
    P.colour = is_colour and true or false
    P.sprite = spriteKind(bb, P.colour)
    P.id = P.colour and id or "classic"
    P.version = Theme.version
    cache[key] = P
    return P
end

-- Choose a theme and save it.
function Theme.set(id)
    if not Palettes.themes[id] or id == Theme.id() then return end
    Settings.set("theme", id)
    Theme.version = Theme.version + 1
    cache = {}
end

-- A theme's colours as plain { r, g, b } tables, whatever the screen: what the
-- picker draws its previews from.
function Theme.swatch(id)
    local def = Palettes.themes[id]
    local out = {}
    if def.mono then
        for role, v in pairs(CLASSIC) do out[role] = { v, v, v } end
        return out
    end
    for role, hex in pairs(def) do
        if role ~= "name" and role ~= "mono" then out[role] = { parse(hex) } end
    end
    out.edge = out.edge or out.ink
    out.pip = out.pip or out.ink
    out.die_edge = out.die_edge or out.ink
    out.cube_ink = out.cube_ink or out.ink
    out.spent = out.spent or out.muted
    return out
end

-- A swatch colour as the buffer being painted can take it: ColorRGB32 for a
-- colour buffer, its grey otherwise.
function Theme.chip(bb, rgb)
    if colourBuffer(bb) then return Blitbuffer.ColorRGB32(rgb[1], rgb[2], rgb[3], 0xFF) end
    return Blitbuffer.Color8(math.floor(Theme.luminance(rgb) ^ (1 / 2.2) * 255 + 0.5))
end

-- WCAG relative luminance and contrast of two { r, g, b }, for the tests that
-- keep every theme legible.
local function lin(c)
    c = c / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
function Theme.luminance(rgb)
    return 0.2126 * lin(rgb[1]) + 0.7152 * lin(rgb[2]) + 0.0722 * lin(rgb[3])
end
function Theme.contrast(a, b)
    local la, lb = Theme.luminance(a), Theme.luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

-- Forget the cache (a test changing the screen under us).
function Theme.reset()
    cache = {}
    Theme.version = Theme.version + 1
end

return Theme
