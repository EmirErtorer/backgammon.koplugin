-- Enough of a blitbuffer to let the view paint without a framebuffer.
-- Counts draw calls and checks bounds so out of range painting is caught.
local BB = {}
BB.__index = BB
local M = { calls = 0, out_of_bounds = 0 }

local function color(v) return { v = v } end
M.COLOR_BLACK = color(0)
M.COLOR_WHITE = color(255)
M.COLOR_GRAY_5 = color(0x55)
M.COLOR_GRAY_B = color(0xBB)
M.COLOR_GRAY = color(0xAA)
M.COLOR_GRAY_D = color(0xDD)

function M.new(w, h, t)
    M.allocated = (M.allocated or 0) + 1
    return setmetatable({ w = w, h = h, t = t or 1, freed = false, ops = {} }, BB)
end

-- Recording is off unless a preview asks for it, so the ordinary tests stay
-- allocation free.
local function record(self, op)
    if M.recording then self.ops[#self.ops + 1] = op end
end
function BB:getType() return self.t end
function BB:free() self.freed = true; M.allocated = M.allocated - 1 end

local function bounds(self, x, y, w, h)
    M.calls = M.calls + 1
    if x < -2 or y < -2 or x + (w or 1) > self.w + 2 or y + (h or 1) > self.h + 2 then
        M.out_of_bounds = M.out_of_bounds + 1
        if M.verbose then
            print(("  out of bounds paint: %s,%s %sx%s in %sx%s"):format(x, y, w, h, self.w, self.h))
        end
    end
end

function BB:fill(c)
    M.calls = M.calls + 1
    if M.recording then self.ops = {} end
    record(self, { k = "rect", x = 0, y = 0, w = self.w, h = self.h, c = c })
end
function BB:paintRect(x, y, w, h, c)
    bounds(self, x, y, w, h)
    record(self, { k = "rect", x = x, y = y, w = w, h = h, c = c })
end
function BB:paintCircle(cx, cy, r, c, w)
    bounds(self, cx - r, cy - r, r * 2, r * 2)
    record(self, { k = "circle", x = cx, y = cy, r = r, c = c, w = w })
end
function BB:paintBorder(x, y, w, h, bw, c)
    bounds(self, x, y, w, h)
    record(self, { k = "border", x = x, y = y, w = w, h = h, bw = bw, c = c })
end
function BB:paintRoundedRect(x, y, w, h, c)
    bounds(self, x, y, w, h)
    record(self, { k = "rect", x = x, y = y, w = w, h = h, c = c, round = true })
end
function BB:blitFrom(src, x, y, ox, oy, w, h)
    bounds(self, x, y, w, h)
    if not M.recording then return end
    local dx, dy = x - (ox or 0), y - (oy or 0)
    for _, o in ipairs(src.ops) do
        local n = {}
        for k, v in pairs(o) do n[k] = v end
        n.x, n.y = o.x + dx, o.y + dy
        self.ops[#self.ops + 1] = n
    end
end
function BB:addText(x, baseline, size, text, c)
    record(self, { k = "text", x = x, y = baseline, size = size, text = text, c = c })
end
return M
