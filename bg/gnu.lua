-- GNU Backgammon neural-net evaluator, ported from gnubg 1.08.003.
--
-- Pure Lua, no KOReader dependency, so it can be validated headlessly against
-- a C oracle built from gnubg's own source. This file owns three trained nets
-- (contact / race / crashed), the input encoding, and the forward pass. The
-- weights are gnubg's, redistributed under the GPL (see NOTICE).
--
-- Board convention here matches gnubg: anBoard[side][0..23] are that side's
-- checkers on its own points (0 = ace point), [24] = bar; side 1 is on roll,
-- side 0 is the opponent. Each side counts 15 chequers; any not on the board
-- are borne off.

local GNU = {}

--------------------------------------------------------------------------
-- forward pass
--------------------------------------------------------------------------

local exp = math.exp
-- gnubg calls sigmoid(-beta*x); its sigmoid(x) ~= 1/(1+e^x), so this is the
-- logistic 1/(1+e^(-beta*x)). gnubg uses a lookup-table approximation; the
-- exact form here differs by ~1e-4, well below what changes a move choice.
local function activate(beta, x)
    return 1.0 / (1.0 + exp(-beta * x))
end

-- Evaluate one net. `input` is a 0-based array of length net.cInput (0-based to
-- mirror gnubg's input arrays exactly). Returns a 1-based array of outputs.
function GNU.evaluate(net, input)
    local cHidden, cInput = net.cHidden, net.cInput
    local hw, ht = net.hiddenW, net.hiddenT
    local ar = net.scratch
    for j = 1, cHidden do ar[j] = ht[j] end
    -- hidden accumulation: hw is laid out [input][hidden]
    local w = 0
    for i = 0, cInput - 1 do
        local ai = input[i]
        if ai ~= 0 then
            if ai == 1 then
                for j = 1, cHidden do ar[j] = ar[j] + hw[w + j] end
            else
                for j = 1, cHidden do ar[j] = ar[j] + hw[w + j] * ai end
            end
        end
        w = w + cHidden
    end
    local betaH = net.betaHidden
    for j = 1, cHidden do ar[j] = activate(betaH, ar[j]) end

    local ow, ot = net.outputW, net.outputT
    local out, betaO = net.out, net.betaOutput
    local o = 0
    for i = 1, net.cOutput do
        local r = ot[i]
        for j = 1, cHidden do r = r + ar[j] * ow[o + j] end
        out[i] = activate(betaO, r)
        o = o + cHidden
    end
    return out
end

--------------------------------------------------------------------------
-- weight loading (text format; one float per line)
--------------------------------------------------------------------------

-- Read the next non-empty token stream: gnubg.weights has a title line, then
-- for each net a header line "cIn cHid cOut dummy betaH betaO" followed by the
-- weights (hiddenW [cIn*cHid], outputW [cHid*cOut], hiddenT [cHid],
-- outputT [cOut]), one float per line.
local function loadNet(lines, pos)
    local header = lines[pos]; pos = pos + 1
    local cIn, cHid, cOut, _dummy, betaH, betaO =
        header:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    cIn, cHid, cOut = tonumber(cIn), tonumber(cHid), tonumber(cOut)
    betaH, betaO = tonumber(betaH), tonumber(betaO)
    local net = {
        cInput = cIn, cHidden = cHid, cOutput = cOut,
        betaHidden = betaH, betaOutput = betaO,
        hiddenW = {}, outputW = {}, hiddenT = {}, outputT = {},
        scratch = {}, out = {},
    }
    local function readInto(t, n)
        for i = 1, n do t[i] = tonumber(lines[pos]); pos = pos + 1 end
    end
    readInto(net.hiddenW, cIn * cHid)
    readInto(net.outputW, cHid * cOut)
    readInto(net.hiddenT, cHid)
    readInto(net.outputT, cOut)
    return net, pos
end

-- Load the three nets from a packed binary (see tools/packweights.lua): a
-- 4-byte magic then, per net, int32 cIn/cHid/cOut, float32 betaH/betaO, and
-- the weights as float32 (hiddenW, outputW, hiddenT, outputT). Little-endian,
-- 4-byte aligned. Uses LuaJIT's ffi, which KOReader provides.
function GNU.loadBinary(path)
    local ffi = require("ffi")
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a")
    f:close()
    local base = ffi.cast("const char*", data)
    local off = 4                       -- skip magic
    local function i32() local v = ffi.cast("const int32_t*", base + off)[0]; off = off + 4; return v end
    local function f32() local v = ffi.cast("const float*", base + off)[0]; off = off + 4; return v end
    local function floats(n)
        local p = ffi.cast("const float*", base + off)
        local t = {}
        for i = 1, n do t[i] = p[i - 1] end
        off = off + 4 * n
        return t
    end
    local function net()
        local cIn, cHid, cOut = i32(), i32(), i32()
        local betaH, betaO = f32(), f32()
        return {
            cInput = cIn, cHidden = cHid, cOutput = cOut,
            betaHidden = betaH, betaOutput = betaO,
            hiddenW = floats(cIn * cHid), outputW = floats(cHid * cOut),
            hiddenT = floats(cHid), outputT = floats(cOut),
            scratch = {}, out = {},
        }
    end
    return { contact = net(), race = net(), crashed = net() }
end

-- Load the packed binary that ships next to this module (bg/gnu.weights).
function GNU.load()
    local src = debug.getinfo(1, "S").source     -- "@.../bg/gnu.lua"
    local dir = src:match("^@(.*)[/\\][^/\\]*$") or "."
    return GNU.loadBinary(dir .. "/gnu.weights")
end

-- Load the contact, race and crashed nets from a gnubg.weights text file.
function GNU.loadText(path)
    local f = assert(io.open(path, "r"))
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    local pos = 2                       -- skip "GNU Backgammon x.xx"
    local nets = {}
    nets.contact, pos = loadNet(lines, pos)
    nets.race, pos = loadNet(lines, pos)
    nets.crashed, pos = loadNet(lines, pos)
    return nets
end

--------------------------------------------------------------------------
-- input encoding, ported line-for-line from gnubg eval.c / lib/inputs.c.
-- Boards are anBoard = { [0]=side0, [1]=side1 }, each a 0..24 array (0 = ace
-- point, 24 = bar), 15 chequers per side (any missing are borne off). The
-- input array `ar` is 0-based to match gnubg's afInput indexing exactly.
--------------------------------------------------------------------------

-- read a board point, 0 outside 0..24 (matches gnubg's in-range accesses)
local function B(board, i) return board[i] or 0 end

-- base representation: 4 floats per point (unary for 1/2/3 then (n-3)/2), bar
-- uses a cumulative variant.
local inpvec, inpvecb = {}, {}
for n = 0, 15 do
    if n == 0 then inpvec[n] = {0, 0, 0, 0}
    elseif n == 1 then inpvec[n] = {1, 0, 0, 0}
    elseif n == 2 then inpvec[n] = {0, 1, 0, 0}
    else inpvec[n] = {0, 0, 1, (n - 3) / 2} end
    if n == 0 then inpvecb[n] = {0, 0, 0, 0}
    elseif n == 1 then inpvecb[n] = {1, 0, 0, 0}
    elseif n == 2 then inpvecb[n] = {1, 1, 0, 0}
    else inpvecb[n] = {1, 1, 1, (n - 3) / 2} end
end

local function baseInputs(anBoard, ar)
    for j = 0, 1 do
        local off = j * 25 * 4
        local board = anBoard[j]
        for i = 0, 23 do
            local v = inpvec[board[i]]
            ar[off + i * 4 + 0] = v[1]
            ar[off + i * 4 + 1] = v[2]
            ar[off + i * 4 + 2] = v[3]
            ar[off + i * 4 + 3] = v[4]
        end
        local v = inpvecb[board[24]]
        ar[off + 96] = v[1]; ar[off + 97] = v[2]; ar[off + 98] = v[3]; ar[off + 99] = v[4]
    end
end

-- escape tables (indexed by a 12-bit occupancy pattern)
local anPoint = {}
for i = 0, 15 do anPoint[i] = (i >= 2) and 1 or 0 end
local anEscapes, anEscapes1 = {}, {}
local function computeTables()
    for i = 0, 0xFFF do
        local c = 0
        for n0 = 0, 5 do
            for n1 = 0, n0 do
                local bit = 2 ^ (n0 + n1 + 1)
                if (i % (bit * 2)) < bit                    -- bit (n0+n1+1) clear
                   and not ((i % (2 ^ (n0 + 1))) >= 2 ^ n0     -- bit n0 set
                            and (i % (2 ^ (n1 + 1))) >= 2 ^ n1) then -- and bit n1 set
                    c = c + ((n0 == n1) and 1 or 2)
                end
            end
        end
        anEscapes[i] = c
    end
    anEscapes1[0] = 0
    for i = 1, 0xFFF do
        local c, low = 0, 0
        while (math.floor(i / 2 ^ low) % 2) == 0 do low = low + 1 end
        for n0 = 0, 5 do
            for n1 = 0, n0 do
                local s = n0 + n1 + 1
                local bit = 2 ^ s
                if s > low and (i % (bit * 2)) < bit
                   and not ((i % (2 ^ (n0 + 1))) >= 2 ^ n0
                            and (i % (2 ^ (n1 + 1))) >= 2 ^ n1) then
                    c = c + ((n0 == n1) and 1 or 2)
                end
            end
        end
        anEscapes1[i] = c
    end
end
computeTables()

-- LuaJIT bit ops (KOReader ships LuaJIT). These run on every net evaluation.
local bitlib = require("bit")
local bor, band, lshift, rshift = bitlib.bor, bitlib.band, bitlib.lshift, bitlib.rshift

local function Escapes(board, n)
    local m = (n < 12) and n or 12
    local af = 0
    for i = 0, m - 1 do
        if anPoint[B(board, 24 + i - n)] == 1 then af = bor(af, lshift(1, i)) end
    end
    return anEscapes[af]
end
local function Escapes1(board, n)
    local m = (n < 12) and n or 12
    local af = 0
    for i = 0, m - 1 do
        if anPoint[B(board, 24 + i - n)] == 1 then af = bor(af, lshift(1, i)) end
    end
    return anEscapes1[af]
end

-- men-off features (three floats at the start of a side's extra block)
local function menOffAll(board, ar, base)
    local menOff = 15
    for i = 0, 24 do menOff = menOff - board[i] end
    if menOff <= 5 then
        ar[base + 0] = (menOff ~= 0) and menOff / 5.0 or 0.0
        ar[base + 1] = 0.0; ar[base + 2] = 0.0
    elseif menOff <= 10 then
        ar[base + 0] = 1.0; ar[base + 1] = (menOff - 5) / 5.0; ar[base + 2] = 0.0
    else
        ar[base + 0] = 1.0; ar[base + 1] = 1.0; ar[base + 2] = (menOff - 10) / 5.0
    end
end
local function menOffNonCrashed(board, ar, base)
    local menOff = 15
    for i = 0, 24 do menOff = menOff - board[i] end
    if menOff <= 2 then
        ar[base + 0] = (menOff ~= 0) and menOff / 3.0 or 0.0
        ar[base + 1] = 0.0; ar[base + 2] = 0.0
    elseif menOff <= 5 then
        ar[base + 0] = 1.0; ar[base + 1] = (menOff - 3) / 3.0; ar[base + 2] = 0.0
    else
        ar[base + 0] = 1.0; ar[base + 1] = 1.0; ar[base + 2] = (menOff - 6) / 3.0
    end
end

-- extra-feature indices within a side's 25-wide block
local I_OFF1, I_BREAK_CONTACT, I_BACK_CHEQUER, I_BACK_ANCHOR, I_FORWARD_ANCHOR,
      I_PIPLOSS, I_P1, I_P2, I_BACKESCAPES, I_ACONTAIN, I_ACONTAIN2, I_CONTAIN,
      I_CONTAIN2, I_MOBILITY, I_MOMENT2, I_ENTER, I_ENTER2, I_TIMING, I_BACKBONE,
      I_BACKG, I_BACKG1, I_FREEPIP, I_BACKRESCAPES =
      0, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24

-- hit-combination tables (0-based to match gnubg)
local aanCombination = {
    [0]={0,-1,-1,-1,-1},[1]={1,2,-1,-1,-1},[2]={3,4,5,-1,-1},[3]={6,7,8,9,-1},
    [4]={10,11,12,-1,-1},[5]={13,14,15,16,17},[6]={18,19,20,-1,-1},[7]={21,22,23,24,-1},
    [8]={25,26,27,-1,-1},[9]={28,29,-1,-1,-1},[10]={30,-1,-1,-1,-1},[11]={31,32,33,-1,-1},
    [12]={-1,-1,-1,-1,-1},[13]={-1,-1,-1,-1,-1},[14]={34,-1,-1,-1,-1},[15]={35,-1,-1,-1,-1},
    [16]={-1,-1,-1,-1,-1},[17]={36,-1,-1,-1,-1},[18]={-1,-1,-1,-1,-1},[19]={37,-1,-1,-1,-1},
    [20]={-1,-1,-1,-1,-1},[21]={-1,-1,-1,-1,-1},[22]={-1,-1,-1,-1,-1},[23]={38,-1,-1,-1,-1},
}
-- aIntermediate[c] = { fAll, {im0,im1,im2}, nFaces, nPips }
local aIntermediate = {
    [0]={1,{0,0,0},1,1},[1]={1,{0,0,0},1,2},[2]={1,{1,0,0},2,2},[3]={1,{0,0,0},1,3},
    [4]={0,{1,2,0},2,3},[5]={1,{1,2,0},3,3},[6]={1,{0,0,0},1,4},[7]={0,{1,3,0},2,4},
    [8]={1,{2,0,0},2,4},[9]={1,{1,2,3},4,4},[10]={1,{0,0,0},1,5},[11]={0,{1,4,0},2,5},
    [12]={0,{2,3,0},2,5},[13]={1,{0,0,0},1,6},[14]={0,{1,5,0},2,6},[15]={0,{2,4,0},2,6},
    [16]={1,{3,0,0},2,6},[17]={1,{2,4,0},3,6},[18]={0,{1,6,0},2,7},[19]={0,{2,5,0},2,7},
    [20]={0,{3,4,0},2,7},[21]={0,{2,6,0},2,8},[22]={0,{3,5,0},2,8},[23]={1,{4,0,0},2,8},
    [24]={1,{2,4,6},4,8},[25]={0,{3,6,0},2,9},[26]={0,{4,5,0},2,9},[27]={1,{3,6,0},3,9},
    [28]={0,{4,6,0},2,10},[29]={1,{5,0,0},2,10},[30]={0,{5,6,0},2,11},[31]={1,{6,0,0},2,12},
    [32]={1,{4,8,0},3,12},[33]={1,{3,6,9},4,12},[34]={1,{5,10,0},3,15},[35]={1,{4,8,12},4,16},
    [36]={1,{6,12,0},3,18},[37]={1,{5,10,15},4,20},[38]={1,{6,12,18},4,24},
}
local aaRoll = {
    [0]={0,2,5,9},[1]={1,8,17,24},[2]={3,16,27,33},[3]={6,23,32,35},[4]={10,29,34,37},
    [5]={13,31,36,38},[6]={0,1,4,-1},[7]={0,3,7,-1},[8]={1,3,12,-1},[9]={0,6,11,-1},
    [10]={1,6,15,-1},[11]={3,6,20,-1},[12]={0,10,14,-1},[13]={1,10,19,-1},[14]={3,10,22,-1},
    [15]={6,10,26,-1},[16]={0,13,18,-1},[17]={1,13,21,-1},[18]={3,13,25,-1},[19]={6,13,28,-1},
    [20]={10,13,30,-1},
}

local function msb32(n)
    local r = 0
    n = math.floor(n)
    while n > 1 do n = math.floor(n / 2); r = r + 1 end
    return r
end
local function bitset(mask, k) return band(rshift(mask, k), 1) == 1 end

-- one side's 25 extra contact/crashed features (I_OFF* filled separately by
-- menOff). player = the side these tactical features describe, opp = the other.
local function CalculateHalfInputs(anBoard, anBoardOpp, ar, base)
    local nOppBack
    for i = 24, 0, -1 do
        if anBoardOpp[i] ~= 0 then nOppBack = i break end
    end
    if nOppBack == nil then nOppBack = -1 end
    nOppBack = 23 - nOppBack

    do  -- I_BREAK_CONTACT
        local np = 0
        for i = nOppBack + 1, 24 do
            if B(anBoard, i) ~= 0 then np = np + (i + 1 - nOppBack) * anBoard[i] end
        end
        ar[base + I_BREAK_CONTACT] = np / (15 + 152.0)
    end
    do  -- I_FREEPIP
        local p = 0
        for i = 0, nOppBack - 1 do
            if B(anBoard, i) ~= 0 then p = p + (i + 1) * anBoard[i] end
        end
        ar[base + I_FREEPIP] = p / 100.0
    end
    do  -- I_TIMING
        local t, no = 0, 0
        local m = (nOppBack >= 11) and nOppBack or 11
        t = t + 24 * anBoard[24]; no = no + anBoard[24]
        local i = 23
        while i > m do
            if anBoard[i] ~= 0 and anBoard[i] ~= 2 then
                local ns = (anBoard[i] > 2) and (anBoard[i] - 2) or 1
                no = no + ns; t = t + i * ns
            end
            i = i - 1
        end
        while i >= 6 do
            if anBoard[i] ~= 0 then no = no + anBoard[i]; t = t + i * anBoard[i] end
            i = i - 1
        end
        for k = 5, 0, -1 do
            if anBoard[k] > 2 then
                t = t + k * (anBoard[k] - 2); no = no + (anBoard[k] - 2)
            elseif anBoard[k] < 2 then
                local nm = 2 - anBoard[k]
                if no >= nm then t = t - k * nm; no = no - nm end
            end
        end
        ar[base + I_TIMING] = t / 100.0
    end
    local ii   -- shared: the back-anchor index, reused by forward-anchor
    do  -- I_BACK_CHEQUER, I_BACK_ANCHOR, I_FORWARD_ANCHOR
        local nBack
        for k = 24, 0, -1 do if anBoard[k] ~= 0 then nBack = k break end end
        if nBack == nil then nBack = -1 end
        ar[base + I_BACK_CHEQUER] = nBack / 24.0
        local start = (nBack == 24) and 23 or nBack
        ii = -1
        for i = start, 0, -1 do
            if B(anBoard, i) >= 2 then ii = i break end
        end
        ar[base + I_BACK_ANCHOR] = ii / 24.0
        local n = 0
        for j = 18, ii do
            if anBoard[j] >= 2 then n = 24 - j break end
        end
        if n == 0 then
            for j = 17, 12, -1 do
                if anBoard[j] >= 2 then n = 24 - j break end
            end
        end
        ar[base + I_FORWARD_ANCHOR] = (n == 0) and 2.0 or (n / 6.0)
    end

    -- I_PIPLOSS / I_P1 / I_P2: shot counting
    local nBoard = 0
    for i = 0, 5 do if anBoard[i] >= 2 then nBoard = nBoard + 1 end end
    local aHit = {}
    for i = 0, 38 do aHit[i] = 0 end
    local istart = (nBoard > 2) and 23 or 21
    for i = istart, 0, -1 do
        if anBoardOpp[i] == 1 then
            for j = 24 - i, 24 do
                if B(anBoard, j) ~= 0 and not (j < 6 and anBoard[j] == 2) then
                    for n = 0, 4 do
                        local comb = aanCombination[j - 24 + i][n + 1]
                        if comb == -1 then break end
                        local pi = aIntermediate[comb]
                        local blocked = false
                        if pi[1] == 1 then          -- fAll
                            if pi[3] > 1 then       -- nFaces > 1
                                for k = 0, 2 do
                                    local im = pi[2][k + 1]
                                    if im <= 0 then break end
                                    if B(anBoardOpp, i - im) > 1 then blocked = true break end
                                end
                            end
                        else
                            if B(anBoardOpp, i - pi[2][1]) > 1 and B(anBoardOpp, i - pi[2][2]) > 1 then
                                blocked = true
                            end
                        end
                        if not blocked then
                            aHit[comb] = bor(aHit[comb], lshift(1, j))
                        end
                    end
                end
            end
        end
    end

    local aRollC, aRollP = {}, {}
    for i = 0, 20 do aRollC[i] = 0; aRollP[i] = 0 end
    if anBoard[24] == 0 then
        for i = 0, 20 do
            local n = -1
            for j = 0, 3 do
                local r = aaRoll[i][j + 1]
                if r < 0 then break end
                if aHit[r] ~= 0 then
                    local pi = aIntermediate[r]
                    if pi[3] == 1 then
                        local k = msb32(aHit[r])
                        if n ~= k or anBoard[k] > 1 then aRollC[i] = aRollC[i] + 1 end
                        n = k
                        if k - pi[4] + 1 > aRollP[i] then aRollP[i] = k - pi[4] + 1 end
                        -- doubles: another direct shot besides the top blot?
                        -- gnubg's (aHit[r] & ~(1<<k)) is nonzero iff aHit[r] != 2^k
                        if aaRoll[i][4] >= 0 and aHit[r] ~= lshift(1, k) then
                            aRollC[i] = aRollC[i] + 1
                        end
                    else
                        if aRollC[i] == 0 then aRollC[i] = 1 end
                        local k = msb32(aHit[r])
                        if k - pi[4] + 1 > aRollP[i] then aRollP[i] = k - pi[4] + 1 end
                        for l = 0, 2 do
                            local im = pi[2][l + 1]
                            if im <= 0 then break end
                            if B(anBoardOpp, 23 - k + im) == 1 then aRollC[i] = aRollC[i] + 1 break end
                        end
                    end
                end
            end
        end
    elseif anBoard[24] == 1 then
        for i = 0, 20 do
            local n = 0
            for j = 0, 3 do
                local r = aaRoll[i][j + 1]
                if r < 0 then break end
                if aHit[r] ~= 0 then
                    local pi = aIntermediate[r]
                    if pi[3] == 1 then
                        for k = 24, 1, -1 do
                            if bitset(aHit[r], k) then
                                if n ~= 0 and k ~= 24 then break end
                                if k ~= 24 then
                                    local npip = aIntermediate[aaRoll[i][(1 - j) + 1]][4]
                                    if B(anBoardOpp, npip - 1) > 1 then break end
                                    n = 1
                                end
                                aRollC[i] = aRollC[i] + 1
                                if k - pi[4] + 1 > aRollP[i] then aRollP[i] = k - pi[4] + 1 end
                            end
                        end
                    else
                        if not bitset(aHit[r], 24) then
                            -- continue
                        else
                            if aRollC[i] == 0 then aRollC[i] = 1 end
                            if 25 - pi[4] > aRollP[i] then aRollP[i] = 25 - pi[4] end
                            for k = 0, 2 do
                                local im = pi[2][k + 1]
                                if im <= 0 then break end
                                if B(anBoardOpp, im + 1) == 1 then aRollC[i] = aRollC[i] + 1 break end
                            end
                        end
                    end
                end
            end
        end
    else
        for i = 0, 20 do
            for j = 0, 1 do
                local r = aaRoll[i][j + 1]
                if bitset(aHit[r], 24) then
                    local pi = aIntermediate[r]
                    if pi[3] == 1 then
                        aRollC[i] = aRollC[i] + 1
                        if 25 - pi[4] > aRollP[i] then aRollP[i] = 25 - pi[4] end
                    end
                end
            end
        end
    end
    do
        local np, n1, n2 = 0, 0, 0
        for i = 0, 5 do
            np = np + aRollP[i]
            if aRollC[i] > 0 then n1 = n1 + 1; if aRollC[i] > 1 then n2 = n2 + 1 end end
        end
        for i = 6, 20 do
            np = np + aRollP[i] * 2
            if aRollC[i] > 0 then n1 = n1 + 2; if aRollC[i] > 1 then n2 = n2 + 2 end end
        end
        ar[base + I_PIPLOSS] = np / (12.0 * 36.0)
        ar[base + I_P1] = n1 / 36.0
        ar[base + I_P2] = n2 / 36.0
    end

    ar[base + I_BACKESCAPES] = Escapes(anBoard, 23 - nOppBack) / 36.0
    ar[base + I_BACKRESCAPES] = Escapes1(anBoard, 23 - nOppBack) / 36.0

    local n, i = 36, 15
    while i < 24 - nOppBack do
        local j = Escapes(anBoard, i); if j < n then n = j end
        i = i + 1
    end
    ar[base + I_ACONTAIN] = (36 - n) / 36.0
    ar[base + I_ACONTAIN2] = ar[base + I_ACONTAIN] * ar[base + I_ACONTAIN]
    if nOppBack < 0 then i = 15; n = 36 end
    while i < 24 do
        local j = Escapes(anBoard, i); if j < n then n = j end
        i = i + 1
    end
    ar[base + I_CONTAIN] = (36 - n) / 36.0
    ar[base + I_CONTAIN2] = ar[base + I_CONTAIN] * ar[base + I_CONTAIN]

    do  -- I_MOBILITY
        local nn = 0
        for k = 6, 24 do
            if anBoard[k] ~= 0 then nn = nn + (k - 5) * anBoard[k] * Escapes(anBoardOpp, k) end
        end
        ar[base + I_MOBILITY] = nn / 3600.0
    end
    do  -- I_MOMENT2
        local j, nn = 0, 0
        for i2 = 0, 24 do
            local ni = anBoard[i2]
            if ni ~= 0 then j = j + ni; nn = nn + i2 * ni end
        end
        nn = math.floor((nn + j - 1) / j)
        j = 0; local k = 0
        for i2 = nn + 1, 24 do
            local ni = anBoard[i2]
            if ni ~= 0 then j = j + ni; k = k + ni * (i2 - nn) * (i2 - nn) end
        end
        if j ~= 0 then k = math.floor((k + j - 1) / j) end
        ar[base + I_MOMENT2] = k / 400.0
    end
    do  -- I_ENTER
        if anBoard[24] > 0 then
            local loss = 0
            local two = anBoard[24] > 1
            for i2 = 0, 5 do
                if anBoardOpp[i2] > 1 then
                    loss = loss + 4 * (i2 + 1)
                    for j = i2 + 1, 5 do
                        if anBoardOpp[j] > 1 then loss = loss + 2 * (i2 + j + 2)
                        elseif two then loss = loss + 2 * (i2 + 1) end
                    end
                elseif two then
                    for j = i2 + 1, 5 do
                        if anBoardOpp[j] > 1 then loss = loss + 2 * (j + 1) end
                    end
                end
            end
            ar[base + I_ENTER] = loss / (36.0 * (49.0 / 6.0))
        else
            ar[base + I_ENTER] = 0.0
        end
    end
    do  -- I_ENTER2
        local nn = 0
        for i2 = 0, 5 do if anBoardOpp[i2] > 1 then nn = nn + 1 end end
        ar[base + I_ENTER2] = (36 - (nn - 6) * (nn - 6)) / 36.0
    end
    do  -- I_BACKBONE
        local pa, w, tot = -1, 0, 0
        local ac = {[0]=11,11,11,11,11,11,11,6,5,4,3,2,0,0,0,0,0,0,0,0,0,0,0}
        for np = 23, 1, -1 do
            if anBoard[np] >= 2 then
                if pa == -1 then pa = np
                else
                    local d = pa - np
                    w = w + ac[d] * anBoard[pa]; tot = tot + anBoard[pa]
                end
            end
        end
        ar[base + I_BACKBONE] = (tot ~= 0) and (1.0 - (w / (tot * 11.0))) or 0.0
    end
    do  -- I_BACKG / I_BACKG1
        local nAc = 0
        for i2 = 18, 23 do if anBoard[i2] > 1 then nAc = nAc + 1 end end
        ar[base + I_BACKG] = 0.0
        ar[base + I_BACKG1] = 0.0
        if nAc >= 1 then
            local tot = 0
            for i2 = 18, 24 do tot = tot + anBoard[i2] end
            if nAc > 1 then ar[base + I_BACKG] = (tot - 3) / 4.0
            else ar[base + I_BACKG1] = tot / 8.0 end
        end
    end
end

local function CalculateContactInputs(anBoard, ar)
    baseInputs(anBoard, ar)
    local b = 25 * 4 * 2                 -- 200
    menOffNonCrashed(anBoard[0], ar, b + I_OFF1)     -- gnubg's switched-sides quirk
    CalculateHalfInputs(anBoard[1], anBoard[0], ar, b)
    b = 25 * 4 * 2 + 25                 -- 225
    menOffNonCrashed(anBoard[1], ar, b + I_OFF1)
    CalculateHalfInputs(anBoard[0], anBoard[1], ar, b)
end

local function CalculateCrashedInputs(anBoard, ar)
    baseInputs(anBoard, ar)
    local b = 25 * 4 * 2
    menOffAll(anBoard[1], ar, b + I_OFF1)
    CalculateHalfInputs(anBoard[1], anBoard[0], ar, b)
    b = 25 * 4 * 2 + 25
    menOffAll(anBoard[0], ar, b + I_OFF1)
    CalculateHalfInputs(anBoard[0], anBoard[1], ar, b)
end

local HALF_RACE_INPUTS = 107
local function CalculateRaceInputs(anBoard, ar)
    for side = 0, 1 do
        local board = anBoard[side]
        local off = side * HALF_RACE_INPUTS
        local menOff = 15
        for i = 0, 22 do
            local nc = board[i]
            local k = i * 4
            menOff = menOff - nc
            ar[off + k + 0] = (nc == 1) and 1.0 or 0.0
            ar[off + k + 1] = (nc == 2) and 1.0 or 0.0
            ar[off + k + 2] = (nc >= 3) and 1.0 or 0.0
            ar[off + k + 3] = (nc > 3) and ((nc - 3) / 2.0) or 0.0
        end
        for k = 0, 13 do
            ar[off + 92 + k] = (menOff == (k + 1)) and 1.0 or 0.0
        end
        local nCross = 0
        for k = 1, 3 do
            for i = 6 * k, 6 * k + 5 do
                if board[i] ~= 0 then nCross = nCross + board[i] * k end
            end
        end
        ar[off + 106] = nCross / 10.0
    end
end

-- position class: CONTACT / CRASHED / RACE / OVER (bearoff DBs -> RACE net)
function GNU.classify(anBoard)
    local nOppBack, nBack
    for i = 24, 0, -1 do if anBoard[0][i] ~= 0 then nOppBack = i break end end
    for i = 24, 0, -1 do if anBoard[1][i] ~= 0 then nBack = i break end end
    if nOppBack == nil or nBack == nil then return "over" end
    if nBack + nOppBack > 22 then
        for side = 0, 1 do
            local board, tot = anBoard[side], 0
            for i = 0, 24 do tot = tot + board[i] end
            if tot <= 6 then return "crashed"
            elseif board[0] > 1 then
                if tot <= 6 + board[0] then return "crashed"
                elseif (1 + tot - (board[0] + board[1])) <= 6 and board[1] > 1 then return "crashed" end
            elseif tot <= 6 + (board[1] - 1) then return "crashed" end
        end
        return "contact"
    end
    return "race"
end

-- Build the input vector for `anBoard`. Returns class, input array (0-based), n.
-- The array is a shared buffer, valid until the next call -- fine for the
-- evaluate-immediately pattern here, and keeps the search allocation-free.
local ar_buf = {}
function GNU.inputs(anBoard)
    local cls = GNU.classify(anBoard)
    local ar = ar_buf
    if cls == "race" then
        for i = 0, 213 do ar[i] = 0 end
        CalculateRaceInputs(anBoard, ar)
        return cls, ar, 214
    elseif cls == "crashed" then
        for i = 0, 249 do ar[i] = 0 end
        CalculateCrashedInputs(anBoard, ar)
        return cls, ar, 250
    elseif cls == "contact" then
        for i = 0, 249 do ar[i] = 0 end
        CalculateContactInputs(anBoard, ar)
        return cls, ar, 250
    end
    return cls, nil, 0
end

-- Cubeless money equity to the side on roll (anBoard[1]), in [-3, 3].
-- Returns nil for a finished position (caller should score it directly).
function GNU.equity(anBoard, nets)
    local cls, ar = GNU.inputs(anBoard)
    if cls == "over" then return nil end
    local net = (cls == "race") and nets.race
        or (cls == "crashed") and nets.crashed
        or nets.contact
    local out = GNU.evaluate(net, ar)
    -- OUTPUT order: WIN, WINGAMMON, WINBACKGAMMON, LOSEGAMMON, LOSEBACKGAMMON
    return out[1] * 2.0 - 1.0 + (out[2] - out[4]) + (out[3] - out[5]), out, cls
end

return GNU
