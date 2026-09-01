local Device = require("device")
local IC = {}
function IC:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
function IC:new(o)
    o = self:extend(o)
    if o._init then o:_init() end
    if o.init then o:init() end
    return o
end
function IC:_init()
    if not self.key_events then self.key_events = {} end
    if Device:hasKeys() then self.key_events.Home = { { "Home" } } end
    if not self.ges_events then self.ges_events = {} end
end
return IC
