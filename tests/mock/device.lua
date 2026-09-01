local BB = require("ffi/blitbuffer")
local screen_bb = BB.new(1448, 1072)
local function setSize(w, h) screen_bb.w, screen_bb.h = w, h end
local rotation = 0
local Screen = {
    bb = screen_bb,
    getWidth = function() return screen_bb.w end,
    getHeight = function() return screen_bb.h end,
    scaleBySize = function(_, px) return math.floor(px * 1.4) end,
    setSize = setSize,
    -- rotation, mirroring koreader-base framebuffer: even modes portrait, odd landscape
    DEVICE_ROTATED_UPRIGHT = 0,
    DEVICE_ROTATED_CLOCKWISE = 1,
    DEVICE_ROTATED_COUNTER_CLOCKWISE = 3,
    getRotationMode = function() return rotation end,
    getScreenMode = function() return screen_bb.w > screen_bb.h and "landscape" or "portrait" end,
    setRotationMode = function(_, m)
        local want_landscape = (m % 2 == 1)
        local is_landscape = screen_bb.w > screen_bb.h
        if want_landscape ~= is_landscape then
            screen_bb.w, screen_bb.h = screen_bb.h, screen_bb.w
        end
        rotation = m
    end,
}
return {
    screen = Screen,
    isTouchDevice = function() return true end,
    hasKeys = function() return true end,
    input = { group = { Back = { "Back" } } },
}
