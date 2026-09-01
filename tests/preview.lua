-- Replays the draw calls that paintTo actually makes and writes them out as
-- SVG, so the board can be looked at without a device.
--   luajit tests/preview.lua [out.svg] [width] [height]

package.path = "./?.lua;./tests/mock/?.lua;" .. package.path

local BB = require("ffi/blitbuffer")
local Device = require("device")
local BoardView = require("bg/boardview")
local R = require("bg/rules")

local out_path = arg[1] or "board.svg"
local W = tonumber(arg[2]) or 1448
local H = tonumber(arg[3]) or 1072
Device.screen.setSize(W, H)

local function grey(c)
    if not c then return "#000000" end
    local v = c.v or 0
    return string.format("#%02x%02x%02x", v, v, v)
end

local v = BoardView:new{}
local g = v.game

-- a position worth looking at: mid game, a checker on the bar, some borne off,
-- dice rolled and a checker selected so the highlights show
g.phase = "move"
g.player = R.WHITE
for i = 1, 24 do g.state.points[i] = 0 end
g.state.points[24] = 2
g.state.points[13] = 3
g.state.points[8] = 3
g.state.points[6] = 5
g.state.points[1] = -2
g.state.points[12] = -5
g.state.points[17] = -3
g.state.points[19] = -3
g.state.points[20] = -1
g.state.bar[R.BLACK] = 1
g.state.off[R.WHITE] = 2
g.dice[1], g.dice[2] = 6, 3
g.ndice = 2
v.shown_dice[1], v.shown_dice[2] = 6, 3
g:refreshLegal()
g:select(13)

BB.recording = true
local screen = BB.new(W, H)
v:paintTo(screen, 0, 0)
BB.recording = false

local parts = {}
parts[#parts + 1] = ([[<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">]])
    :format(W, H, W, H)
parts[#parts + 1] = ([[<rect width="%d" height="%d" fill="#ffffff"/>]]):format(W, H)

for _, o in ipairs(screen.ops) do
    if o.k == "rect" then
        parts[#parts + 1] = ([[<rect x="%d" y="%d" width="%d" height="%d" fill="%s"/>]])
            :format(o.x, o.y, o.w, o.h, grey(o.c))
    elseif o.k == "border" then
        local bw = o.bw or 1
        parts[#parts + 1] = ([[<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="%s" stroke-width="%d"/>]])
            :format(o.x + bw / 2, o.y + bw / 2, o.w - bw, o.h - bw, grey(o.c), bw)
    elseif o.k == "circle" then
        if o.w and o.w < o.r then
            parts[#parts + 1] = ([[<circle cx="%d" cy="%d" r="%.1f" fill="none" stroke="%s" stroke-width="%d"/>]])
                :format(o.x, o.y, o.r - o.w / 2, grey(o.c), o.w)
        else
            parts[#parts + 1] = ([[<circle cx="%d" cy="%d" r="%d" fill="%s"/>]])
                :format(o.x, o.y, o.r, grey(o.c))
        end
    elseif o.k == "text" then
        local esc = o.text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        parts[#parts + 1] = ([[<text x="%d" y="%d" font-family="DejaVu Sans,Helvetica,sans-serif" font-size="%d" fill="%s">%s</text>]])
            :format(o.x, o.y, o.size, grey(o.c), esc)
    end
end
parts[#parts + 1] = "</svg>"

local f = assert(io.open(out_path, "w"))
f:write(table.concat(parts, "\n"))
f:close()
print(("wrote %s (%dx%d, %d draw calls)"):format(out_path, W, H, #screen.ops))
