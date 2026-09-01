local BB = require("ffi/blitbuffer")
local screen_bb = BB.new(1448, 1072)
local function setSize(w, h) screen_bb.w, screen_bb.h = w, h end
local Screen = {
    bb = screen_bb,
    getWidth = function() return screen_bb.w end,
    getHeight = function() return screen_bb.h end,
    scaleBySize = function(_, px) return math.floor(px * 1.4) end,
    setSize = setSize,
}
return {
    screen = Screen,
    isTouchDevice = function() return true end,
    hasKeys = function() return true end,
    input = { group = { Back = { "Back" } } },
}
