-- Turn and match state. Sits between the rules engine and the view, and knows
-- nothing about KOReader so it can be driven from a test.
--
-- Every array here is allocated once in new() and reused, so a long match does
-- not grow the heap.

local R = require("bg/rules")
local Dice = require("bg/dice")

local WHITE, BLACK, BAR, OFF = R.WHITE, R.BLACK, R.BAR, R.OFF

local Game = {}
Game.__index = Game

-- phase:
--   "opening"  waiting for the roll that decides who starts
--   "roll"     current player has to roll
--   "move"     dice are on the table, moves to make
--   "over"     someone has borne off fifteen
local M = {}

function M.new()
    local g = setmetatable({}, Game)
    g.state = R.newState()
    g.dice = { 0, 0, 0, 0 }
    g.ndice = 0
    g.rolled = { 0, 0 }       -- the two raw dice, for display
    g.opening_dice = { 0, 0 }  -- kept on screen until the starter rolls
    g.spent = { false, false, false, false }
    g.legal_from = {}
    g.legal_to = {}
    g.legal_die = {}
    g.legal_n = 0
    g.dests = {}              -- destinations for the currently selected point
    g.dests_n = 0
    g.undo = { from = 0, to = 0, hit = false }
    g.score = { [WHITE] = 0, [BLACK] = 0 }
    g.games = 0
    g.selected = nil
    g.message = nil
    g.last_hit = false
    g:newGame()
    return g
end

M.WHITE, M.BLACK, M.BAR, M.OFF = WHITE, BLACK, BAR, OFF

function Game:newGame()
    R.setupStart(self.state)
    self.player = WHITE
    self.phase = "opening"
    self.ndice = 0
    self.legal_n = 0
    self.selected = nil
    self.dests_n = 0
    self.rolled[1], self.rolled[2] = 0, 0
    self.opening_dice[1], self.opening_dice[2] = 0, 0
    self.message = "Roll one die each to see who starts"
    self.winner = nil
    self.win_points = 0
end

-- Copy the shared analyse() result into our own arrays, since the engine hands
-- back a table it will overwrite on the next call.
function Game:refreshLegal()
    local r = R.analyse(self.state, self.player, self.dice, self.ndice)
    self.legal_n = r.n
    for i = 1, r.n do
        self.legal_from[i] = r.from[i]
        self.legal_to[i] = r.to[i]
        self.legal_die[i] = r.die[i]
    end
end

--- Roll for the opening. Returns true once a starting player is decided.
function Game:openingRoll()
    local a, b = Dice.rollOne(), Dice.rollOne()
    self.rolled[1], self.rolled[2] = a, b
    self.opening_dice[1], self.opening_dice[2] = a, b
    if a == b then
        self.message = ("Both rolled %d. Roll again"):format(a)
        return false
    end
    self.player = (a > b) and WHITE or BLACK
    self.phase = "roll"
    -- spell out what just happened: this is not a turn, it only picks who goes
    -- first, and the starter still has to roll
    self.message = ("White %d, Black %d. %s starts, roll again"):format(
        a, b, self.player == WHITE and "White" or "Black")
    return true
end

--- Roll for the current turn. Returns "move" if there is something to play, or
--- "pass" when the roll is dead.
function Game:roll()
    self.opening_dice[1], self.opening_dice[2] = 0, 0
    self.ndice = Dice.roll(self.dice)
    self.rolled[1], self.rolled[2] = self.dice[1], self.dice[2]
    self.selected = nil
    self.dests_n = 0
    self:refreshLegal()
    if self.legal_n == 0 then
        self.message = "No legal move"
        self.phase = "move"      -- the view shows the dice, then passes
        return "pass"
    end
    self.phase = "move"
    self.message = nil
    return "move"
end

function Game:passTurn()
    self.player = -self.player
    self.ndice = 0
    self.legal_n = 0
    self.selected = nil
    self.dests_n = 0
    self.phase = "roll"
end

--- Is there any legal move starting from this point?
function Game:canSelect(point)
    for i = 1, self.legal_n do
        if self.legal_from[i] == point then return true end
    end
    return false
end

--- Fill self.dests with every point this checker may move to.
function Game:select(point)
    if not self:canSelect(point) then
        self.selected = nil
        self.dests_n = 0
        return false
    end
    self.selected = point
    local n = 0
    for i = 1, self.legal_n do
        if self.legal_from[i] == point then
            n = n + 1
            self.dests[n] = self.legal_to[i]
        end
    end
    self.dests_n = n
    return true
end

function Game:deselect()
    self.selected = nil
    self.dests_n = 0
end

function Game:isDestination(point)
    for i = 1, self.dests_n do
        if self.dests[i] == point then return true end
    end
    return false
end

-- Which die does this move consume? The engine already picked one when it
-- generated the move.
local function dieFor(self, from, to)
    for i = 1, self.legal_n do
        if self.legal_from[i] == from and self.legal_to[i] == to then
            return self.legal_die[i]
        end
    end
    return nil
end

--- Play the selected checker to `to`.
--- Returns "moved", "turn_over" or "won", or nil if the move was not legal.
function Game:move(to)
    local from = self.selected
    if from == nil then return nil end
    local die = dieFor(self, from, to)
    if not die then return nil end

    R.applyMove(self.state, self.player, from, to, self.undo)
    self.last_hit = self.undo.hit

    -- consume one die of that value
    for i = 1, self.ndice do
        if self.dice[i] == die then
            self.dice[i] = self.dice[self.ndice]
            self.ndice = self.ndice - 1
            break
        end
    end

    self.selected = nil
    self.dests_n = 0

    local w = R.winner(self.state)
    if w then
        self.winner = w
        self.win_points = R.scoreFor(self.state, w)
        self.score[w] = self.score[w] + self.win_points
        self.games = self.games + 1
        self.phase = "over"
        self.legal_n = 0
        self.message = (w == WHITE and "White" or "Black") .. " wins "
            .. self.win_points .. (self.win_points == 1 and " point" or " points")
        return "won"
    end

    if self.ndice > 0 then
        self:refreshLegal()
        if self.legal_n > 0 then
            return "moved"
        end
    end

    self.legal_n = 0
    return "turn_over"
end

function Game:pipCount(player)
    return R.pipCount(self.state, player)
end

M.Game = Game
return M
