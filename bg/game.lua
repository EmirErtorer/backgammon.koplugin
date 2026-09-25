-- Turn and match state. Sits between the rules engine and the view, and knows
-- nothing about KOReader so it can be driven from a test.
--
-- Every array here is allocated once in new() and reused, so a long match does
-- not grow the heap.

local R = require("bg/rules")
local Dice = require("bg/dice")
local T = require("bg/i18n")

local WHITE, BLACK, BAR, OFF = R.WHITE, R.BLACK, R.BAR, R.OFF

local function colorName(c) return (c == WHITE) and T("white") or T("black") end

-- snapshot of a position, for the post-game review
local function snap(s)
    local p = {}
    for i = 1, 24 do p[i] = s.points[i] end
    return { points = p, bw = s.bar[WHITE], bb = s.bar[BLACK], ow = s.off[WHITE], ob = s.off[BLACK] }
end

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
    -- per-turn take-back stack: one slot per die that can be played (four on a
    -- double), reused across turns so undo allocates nothing. turn_n is how many
    -- of this turn's moves are still on the stack.
    g.turn_undo = {}
    for i = 1, 4 do g.turn_undo[i] = { from = 0, to = 0, die = 0, hit = false } end
    g.turn_n = 0
    g._undo_scratch = { from = 0, to = 0, hit = false }
    g.score = { [WHITE] = 0, [BLACK] = 0 }
    -- doubling cube: value 1..64 and who owns it (nil = centred, either side may
    -- double). pending_double holds an offer awaiting a take/drop.
    g.cube = { value = 1, owner = nil }
    g.pending_double = nil
    g.games = 0
    g.selected = nil
    g.message = nil
    g.last_hit = false
    -- per-game turn history, for the post-game review. Reset each game.
    g.history = {}
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
    self.message = T("roll_one_each")
    self.winner = nil
    self.win_points = 0
    self.history = {}
    self._turn = nil
    self.turn_n = 0
    self.cube.value = 1
    self.cube.owner = nil
    self.pending_double = nil
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
        self.message = T("both_rolled", a)
        return false
    end
    self.player = (a > b) and WHITE or BLACK
    self.phase = "roll"
    -- spell out what just happened: this is not a turn, it only picks who goes
    -- first, and the starter still has to roll
    self.message = T("opening_result", T("white"), a, T("black"), b, colorName(self.player))
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
    self.turn_n = 0            -- fresh turn: nothing to take back yet
    self:refreshLegal()
    -- start recording this turn for the review (a dead roll records nothing)
    self._turn = { player = self.player, ndice = self.ndice, dice = {},
                   before = snap(self.state), moves = {} }
    for i = 1, self.ndice do self._turn.dice[i] = self.dice[i] end
    if self.legal_n == 0 then
        self._turn = nil
        self.message = T("no_legal_move")
        self.phase = "move"      -- the view shows the dice, then passes
        return "pass"
    end
    self.phase = "move"
    self.message = nil
    return "move"
end

-- finalise the current turn into the review history (turns with no move, e.g.
-- dead rolls, are dropped)
function Game:finalizeTurn()
    if self._turn and #self._turn.moves > 0 then
        self.history[#self.history + 1] = self._turn
    end
    self._turn = nil
end

function Game:passTurn()
    self.player = -self.player
    self.ndice = 0
    self.legal_n = 0
    self.selected = nil
    self.dests_n = 0
    self.turn_n = 0            -- the turn is committed; nothing left to take back
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
    if self._turn then self._turn.moves[#self._turn.moves + 1] = { from = from, to = to, die = die } end

    -- record the move so it can be taken back until the turn is committed
    self.turn_n = self.turn_n + 1
    local e = self.turn_undo[self.turn_n]
    e.from, e.to, e.die, e.hit = from, to, die, self.undo.hit

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
        self:finalizeTurn()
        self.winner = w
        -- gammon/backgammon multiplier times the doubling-cube stake
        self.win_points = R.scoreFor(self.state, w) * self.cube.value
        self.score[w] = self.score[w] + self.win_points
        self.games = self.games + 1
        self.phase = "over"
        self.legal_n = 0
        self.message = (self.win_points == 1) and T("win_1", colorName(w))
            or T("win_n", colorName(w), self.win_points)
        return "won"
    end

    if self.ndice > 0 then
        self:refreshLegal()
        if self.legal_n > 0 then
            return "moved"
        end
    end

    self:finalizeTurn()
    self.legal_n = 0
    return "turn_over"
end

-- Apply a specific (from, to) move, e.g. one the computer chose. Reuses the
-- same path as a tapped human move (die consumption, win/turn detection).
function Game:moveDirect(from, to)
    self.selected = from
    return self:move(to)
end

--- Can the current player take back a move? Only while the dice are still on the
--- table (phase "move") and at least one move has been made this turn.
function Game:canUndo()
    return self.phase == "move" and self.turn_n > 0
end

--- Take back the last move of this turn: reverse the checker (restoring any
--- checker it hit), hand the die back, and drop it from the review history.
--- Returns true if a move was undone.
function Game:undoLast()
    if not self:canUndo() then return false end
    local e = self.turn_undo[self.turn_n]
    self.turn_n = self.turn_n - 1

    local u = self._undo_scratch
    u.from, u.to, u.hit = e.from, e.to, e.hit
    R.undoMove(self.state, self.player, u)

    -- give the die back and refresh the legal moves for the restored position
    self.ndice = self.ndice + 1
    self.dice[self.ndice] = e.die
    if self._turn and #self._turn.moves > 0 then
        self._turn.moves[#self._turn.moves] = nil
    end
    self.selected = nil
    self.dests_n = 0
    self.last_hit = false
    self:refreshLegal()
    return true
end

--------------------------------------------------------------------------
-- doubling cube
--------------------------------------------------------------------------

local CUBE_MAX = 64

--- May `player` offer a double right now? Only at the start of their turn
--- (before rolling), when the cube is centred or theirs, and not maxed out.
function Game:canDouble(player)
    if self.phase ~= "roll" then return false end
    if self.winner or self.pending_double then return false end
    if self.cube.value >= CUBE_MAX then return false end
    return self.cube.owner == nil or self.cube.owner == player
end

--- Offer a double. The proposed value is recorded; the opponent then takes or
--- drops. Returns the proposed value, or nil if not allowed.
function Game:offerDouble(player)
    if not self:canDouble(player) then return nil end
    self.pending_double = { by = player, value = self.cube.value * 2 }
    return self.pending_double.value
end

--- Accept the pending double: the cube turns and passes to the taker (the
--- opponent of the doubler), who now owns it. The doubler stays on roll.
function Game:takeDouble()
    local pd = self.pending_double
    if not pd then return false end
    self.cube.value = pd.value
    self.cube.owner = -pd.by
    self.pending_double = nil
    return true
end

--- Decline the pending double: the doubler wins the current stake (the value
--- before the refused double), and the game is over.
function Game:dropDouble()
    local pd = self.pending_double
    if not pd then return false end
    self.pending_double = nil
    local w = pd.by
    self.winner = w
    self.win_points = self.cube.value
    self.score[w] = self.score[w] + self.win_points
    self.games = self.games + 1
    self.phase = "over"
    self.legal_n = 0
    self:finalizeTurn()
    self.message = (self.win_points == 1) and T("win_1", colorName(w))
        or T("win_n", colorName(w), self.win_points)
    return true
end

--------------------------------------------------------------------------
-- save / resume
--------------------------------------------------------------------------

-- A plain snapshot of the game (position, whose turn, dice still to play, the
-- session score and the cube) that survives being written to disk and read back.
-- Transient bits -- the current selection, the take-back stack and the review
-- history -- are deliberately left out.
function Game:serialize()
    local s = self.state
    local pts = {}
    for i = 1, 24 do pts[i] = s.points[i] end
    local dice = {}
    for i = 1, self.ndice do dice[i] = self.dice[i] end
    return {
        player = self.player, phase = self.phase, ndice = self.ndice, dice = dice,
        points = pts, barW = s.bar[WHITE], barB = s.bar[BLACK],
        offW = s.off[WHITE], offB = s.off[BLACK],
        scoreW = self.score[WHITE], scoreB = self.score[BLACK], games = self.games,
        cubeValue = self.cube.value, cubeOwner = self.cube.owner or 0,
    }
end

-- Rebuild the game from a serialize() snapshot. Returns self.
function Game:restore(t)
    local s = self.state
    for i = 1, 24 do s.points[i] = t.points[i] or 0 end
    s.bar[WHITE], s.bar[BLACK] = t.barW or 0, t.barB or 0
    s.off[WHITE], s.off[BLACK] = t.offW or 0, t.offB or 0
    self.player = t.player or WHITE
    self.phase = t.phase or "roll"
    self.ndice = t.ndice or 0
    for i = 1, 4 do self.dice[i] = 0 end
    for i = 1, self.ndice do self.dice[i] = t.dice[i] end
    self.rolled[1], self.rolled[2] = self.dice[1] or 0, self.dice[2] or 0
    self.score[WHITE], self.score[BLACK] = t.scoreW or 0, t.scoreB or 0
    self.games = t.games or 0
    self.cube.value = t.cubeValue or 1
    self.cube.owner = (t.cubeOwner and t.cubeOwner ~= 0) and t.cubeOwner or nil
    self.pending_double = nil
    self.selected = nil
    self.dests_n = 0
    self.turn_n = 0
    self.winner = nil
    self.win_points = 0
    self.message = nil
    self.history = {}
    self._turn = nil
    if self.phase == "move" and self.ndice > 0 then
        self:refreshLegal()
    else
        self.legal_n = 0
    end
    return self
end

function Game:pipCount(player)
    return R.pipCount(self.state, player)
end

M.Game = Game
return M
