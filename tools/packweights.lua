-- Offline: convert gnubg.weights (text) into the compact binary bg/gnu.weights
-- holding just the contact, race and crashed nets. Run with luajit.
--   luajit tools/packweights.lua <gnubg.weights> <out.weights>
package.path = "./?.lua;" .. package.path
local ffi = require("ffi")
local GNU = require("bg/gnu")
local src = arg[1]
local out = arg[2] or "bg/gnu.weights"
local nets = GNU.loadText(src)

local buf = {}
local function putI32(v) local a=ffi.new("int32_t[1]",v); buf[#buf+1]=ffi.string(a,4) end
local function putF32(v) local a=ffi.new("float[1]",v); buf[#buf+1]=ffi.string(a,4) end
local function putFloats(t) local a=ffi.new("float[?]",#t); for i=1,#t do a[i-1]=t[i] end; buf[#buf+1]=ffi.string(a,4*#t) end
buf[#buf+1] = "GNU1"
for _,name in ipairs({"contact","race","crashed"}) do
    local n = nets[name]
    putI32(n.cInput); putI32(n.cHidden); putI32(n.cOutput)
    putF32(n.betaHidden); putF32(n.betaOutput)
    putFloats(n.hiddenW); putFloats(n.outputW); putFloats(n.hiddenT); putFloats(n.outputT)
end
local f = assert(io.open(out, "wb")); f:write(table.concat(buf)); f:close()
print("wrote "..out)
