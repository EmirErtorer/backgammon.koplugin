-- Backgammon (tavla) for KOReader. Two players or vs the computer, one device.

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
            -- open the setup screen; it starts the board once an opponent and
            -- difficulty are chosen. openSetup is reused by the board's "Menu"
            -- button so abandoning a game returns to a fresh picker.
            local SetupView = require("bg/setupview")
            local BoardView = require("bg/boardview")
            local openSetup
            openSetup = function()
                UIManager:show(SetupView:new{
                    on_start = function(opponent, level)
                        UIManager:show(BoardView:new{
                            opponent = opponent,
                            ai_level = level,
                            on_menu = openSetup,
                        })
                    end,
                })
            end
            openSetup()
        end,
    }
end

return Backgammon
