-- Backgammon (tavla) for KOReader. Two players, one device.

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Backgammon = WidgetContainer:extend{
    name = "backgammon",
    is_doc_only = false,
}

function Backgammon:init()
    self.ui.menu:registerToMainMenu(self)
end

function Backgammon:addToMainMenu(menu_items)
    menu_items.backgammon = {
        text = _("Backgammon"),
        sorting_hint = "more_tools",
        keep_menu_open = false,
        callback = function()
            local BoardView = require("bg/boardview")
            UIManager:show(BoardView:new{})
        end,
    }
end

return Backgammon
