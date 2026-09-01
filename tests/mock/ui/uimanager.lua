-- Records refresh requests and runs scheduled callbacks straight away so a
-- test can drive the dice animation without a real event loop.
local M = { refreshes = {}, closed = false, run_scheduled = true }
-- The real UIManager stores the Geom by reference and only reads it later when
-- the refresh stack is flushed. Copying it here would hide callers that reuse
-- one table across several setDirty calls, which is a real bug.
function M:setDirty(widget, mode, region)
    M.refreshes[#M.refreshes + 1] = { mode = type(mode) == "string" and mode or "fn", region = region }
end

-- Read the queue the way a repaint would: after the fact.
function M.flush()
    local out = {}
    for _, r in ipairs(M.refreshes) do
        out[#out + 1] = { mode = r.mode,
                          region = r.region and { x = r.region.x, y = r.region.y,
                                                  w = r.region.w, h = r.region.h } or nil }
    end
    M.refreshes = {}
    return out
end
function M:show(w) M.shown = w; if w.onShow then w:onShow() end end
function M:close(w) M.closed = true; if w.onCloseWidget then w:onCloseWidget() end end
function M:scheduleIn(_, fn) if M.run_scheduled then fn() end end
function M:unschedule() end
function M:forceRePaint() end
function M.reset() M.refreshes = {} end
function M.last() return M.refreshes[#M.refreshes] end
return M
