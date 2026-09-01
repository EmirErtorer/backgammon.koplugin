local W = {}
function W:extend(o) o = o or {}; setmetatable(o, self); self.__index = self; return o end
function W:new(o)
    o = self:extend(o)
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end
return W
