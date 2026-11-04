-- The colour themes, as plain data: a name and one "#RRGGBB" per role. No
-- code runs here, so settings can read the list of ids without pulling in the
-- drawing side. bg/theme.lua turns a palette into the colours a screen can show.
--
-- Roles (a theme may leave out pip, die_edge and edge; they follow ink):
--   paper      the screen behind everything
--   board      the board's own bed, between the points
--   ink        text, button outlines, the board frame
--   muted      secondary text and a spent die's strike
--   pt_a/pt_b  the two alternating point colours
--   bar        the bar down the middle
--   tray       the borne-off column
--   wfill/wring/bfill/bring   white and black checkers: disc and outline/inner ring
--   select     the picked checker's point
--   dest       where it may go
--   die/pip/die_edge/one      dice; the single pip of a one is painted in `one`
--   btn        ordinary button face
--   primary/primary_text      the filled call to action (Start, Done, Roll)
--   cube/cube_ink             the doubling cube's face and its number (ink by default)
--   off_w/off_b               borne-off checker bars

local P = {}

-- The order they are offered in; the first is the default.
P.ORDER = { "pearl", "forest", "ocean", "rosewood", "midnight", "classic" }

P.themes = {
    -- the README's palette: mother of pearl and brown
    pearl = {
        name = "Classic",
        paper = "#EFE9DF", board = "#F7F3EC", ink = "#5B3420", muted = "#8C6A52",
        pt_a = "#7B4A2D", pt_b = "#D8C4A8", bar = "#CDB89C", tray = "#F7F3EC",
        wfill = "#FDFBF7", wring = "#5B3420", bfill = "#4B2A19", bring = "#E8DCCB",
        select = "#B5651D", dest = "#2E7D6B",
        die = "#FDFBF7", one = "#B3261E",
        btn = "#F7F3EC", primary = "#5B3420", primary_text = "#EFE9DF",
        cube = "#E6CF9E", off_w = "#FDFBF7", off_b = "#4B2A19",
    },
    forest = {
        name = "Forest",
        paper = "#E8EDE3", board = "#F4F7EF", ink = "#1F3D2B", muted = "#5F7A68",
        pt_a = "#2F6B47", pt_b = "#C9D8B8", bar = "#B8C9A8", tray = "#F4F7EF",
        wfill = "#FAFCF6", wring = "#1F3D2B", bfill = "#173523", bring = "#D9E6CC",
        select = "#B4531A", dest = "#1D6FA5",
        die = "#FAFCF6", one = "#B3261E",
        btn = "#F4F7EF", primary = "#1F3D2B", primary_text = "#E8EDE3",
        cube = "#E3D79A", off_w = "#FAFCF6", off_b = "#173523",
    },
    ocean = {
        name = "Ocean",
        paper = "#E6EEF3", board = "#F2F7FA", ink = "#16324A", muted = "#5B7488",
        pt_a = "#2D5F85", pt_b = "#BFD4E2", bar = "#A9C2D3", tray = "#F2F7FA",
        wfill = "#FBFDFF", wring = "#16324A", bfill = "#10263A", bring = "#D5E6F2",
        select = "#C26A1B", dest = "#1B7F6B",
        die = "#FBFDFF", one = "#C0392B",
        btn = "#F2F7FA", primary = "#16324A", primary_text = "#E6EEF3",
        cube = "#EBD9A0", off_w = "#FBFDFF", off_b = "#10263A",
    },
    rosewood = {
        name = "Rosewood",
        paper = "#F1E6E4", board = "#FAF3F1", ink = "#5A1F2B", muted = "#8E5C66",
        pt_a = "#8A3040", pt_b = "#E3C6C4", bar = "#D2AFAD", tray = "#FAF3F1",
        wfill = "#FFFBFA", wring = "#5A1F2B", bfill = "#3F1520", bring = "#EBD3D1",
        select = "#B7791F", dest = "#2F7A5B",
        die = "#FFFBFA", one = "#C0392B",
        btn = "#FAF3F1", primary = "#5A1F2B", primary_text = "#F1E6E4",
        cube = "#EBD6A0", off_w = "#FFFBFA", off_b = "#3F1520",
    },
    -- a dark board; the checkers swap roles so white still reads as the light side
    midnight = {
        name = "Midnight",
        paper = "#14181F", board = "#1C222B", ink = "#E6E1D5", muted = "#9AA3AF",
        edge = "#8A93A0",
        pt_a = "#5B7FA3", pt_b = "#3A4757", bar = "#2A323D", tray = "#1C222B",
        wfill = "#F3EFE6", wring = "#0C0F13", bfill = "#0B0E12", bring = "#8A93A0",
        select = "#E0A23B", dest = "#4CB58F",
        die = "#F3EFE6", pip = "#14181F", die_edge = "#8A93A0", one = "#D63A3F",
        btn = "#1C222B", primary = "#E6E1D5", primary_text = "#14181F",
        cube = "#D9B96A", cube_ink = "#14181F", off_w = "#F3EFE6", off_b = "#0B0E12",
    },
    -- black and white, exactly the look before colour existed
    classic = { name = "Black & white", mono = true },
}

return P
