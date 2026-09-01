# Backgammon for KOReader

A two-player backgammon (tavla) board for [KOReader](https://github.com/koreader/koreader).
Both players share one device and take turns on the same screen.

It is built for e-ink: flat greys instead of textures, checkers told apart by
shape as well as shade, and small screen refreshes so play stays responsive on
slow panels.

- Two human players, hot-seat on one device
- Full standard rules: hitting, the bar, bearing off, forced moves, doubles
- Tap to select a checker, tap a highlighted point to move — no dragging
- Session scoreboard with 1 / 2 / 3 point scoring (mars and backgammon)
- Works in portrait and landscape, and adapts to any screen size
- Pure Lua, no external dependencies, nothing written to disk

Not included: an AI opponent, online play, and the doubling cube. Every game is
two humans.

## Requirements

KOReader on any supported device (Kobo, Kindle, PocketBook, Android, or the
desktop build). It uses only long-standing parts of KOReader, so any reasonably
recent version works.

## Installation

1. Download or clone this repository.
2. Copy the `backgammon.koplugin` folder into KOReader's `plugins` folder.
   - Kobo: `.adds/koreader/plugins/`
   - Kindle: `koreader/plugins/`
   - Android: `koreader/plugins/` inside the app's storage
   - Desktop: the `plugins` folder next to the KOReader binary
3. Restart KOReader.

It then appears in the file browser under the **Tools** menu as **Backgammon**.

## How to play

**Starting.** Press **Roll**. The first roll is not a turn: each side gets one
die and the higher one starts, rerolling on a tie. The message line states the
result, for example *"White 5, Black 3. White starts, roll again"*. The
starting player then presses Roll for their first turn.

**Moving.** Press Roll to throw the dice, then tap one of your checkers. Every
point it can legally reach lights up with a heavy border and a marker. Tap one
of those to move the checker there; the die that move used is removed from the
dice on the bar. Tap the same checker again, or an empty area, to deselect.

**Turn end.** When all the dice have been played the turn passes automatically.
If a throw has no legal move at all, the message line says so and the button
changes to **Continue** to hand over.

**Scoreboard.** The score across the top counts points for the current session
only. It resets to zero each time the plugin is opened and is never saved.
**New game** deals a fresh board and keeps the running score; **Close** exits.

## Rules

The starting position is the standard one: two checkers on the 24 point, five
on the 13, three on the 8 and five on the 6, counted from each player's own
side. Both players bear off on the right — white at the bottom right, black at
the top right.

- A point holding two or more enemy checkers is blocked. A point holding a
  single enemy checker is a blot; landing on it sends that checker to the bar.
- Doubles are played as four moves of the same number.
- Both dice must be played whenever there is a legal way to do so. If only one
  die can be played, it must be the higher one when that is legal.
- A checker on the bar must re-enter before anything else moves. It enters into
  the opponent's home board using one die, and the rest of the throw is then
  played normally. If it cannot enter with either die, the turn passes.
- Bearing off requires all fifteen checkers in the home board and none on the
  bar. An exact roll bears a checker off its point; a roll higher than the
  highest occupied point bears off from that point; a roll higher than a point
  that still has checkers behind it must be played as an ordinary move instead.

### Scoring

- **1 point** for a normal win (the loser has borne off at least one checker).
- **2 points** for a mars (the loser has borne off none).
- **3 points** when the loser has borne off none and still has a checker inside
  the winner's home board.

A checker sitting on the bar counts as being in the winner's home board for the
3-point case, since that is where it would have to re-enter. This is controlled
by a single line in `bg/rules.lua` for anyone who prefers a different house
rule.

### A note on legal moves

Whether a move is legal can depend on the rest of the turn, not just one die.
The "both dice must be played if possible" rule means a move that looks fine on
its own can be illegal if playing it would strand the other die when a
different order would have used both. The plugin works this out by searching
the full turn and only offering moves that begin a longest possible sequence,
so the highlighted moves are always the legal ones — occasionally fewer than
expected.

## Design notes

**Display.** The board uses flat greys rather than wood textures or gradients,
which ghost badly on e-ink. Checkers are distinguished by shape as well as
shade (white is a light disc in a heavy dark ring, black is a solid disc with a
light inner ring), so they stay legible even on low-contrast screens.
Highlighted destinations carry both a border and a filled marker. The dice are
white with black pips and sit centred on the bar for both players. The board
scales to the screen and re-lays out if the device is rotated mid-game.

**Responsiveness.** The fixed parts of the board are drawn once into an
offscreen buffer and reused, so each repaint is cheap. Screen refreshes are
grouped so that a move triggers under two updates on average and a roll two,
which keeps taps feeling immediate on slow panels; a full-screen refresh
happens only as the deliberate flash when a game ends.

**Footprint.** Game state is a few dozen numbers, and move generation reuses
its working memory rather than allocating per move, so a long match does not
grow the heap. The only sizeable allocation is the offscreen board image, which
is freed when the plugin closes.

## Limitations

- Two human players only — no computer opponent.
- No doubling cube.
- No undo once a checker is tapped into place.
- Bearing off is always on the right; the side is not configurable.
- Nothing is saved: closing the plugin discards the score and any game in
  progress.

## Development

The rules engine in `bg/rules.lua` has no KOReader dependency and runs under a
plain `luajit`. Tests run from the plugin directory:

```
luajit tests/run.lua      # rules engine
luajit tests/view.lua     # board view against a mock KOReader
```

`tests/run.lua` covers the opening position, hitting, bar entry against partly
and fully blocked home boards, the forced-move and higher-die rules, doubles,
bearing off, and scoring, then plays several thousand random games to
completion checking that the checkers are always accounted for, that no game
stalls, and that every score matches its final position.

`tests/view.lua` checks the layout across a range of screen sizes, verifies
that taps map back to the right points, that drawing stays within bounds, that
a mid-game rotation preserves the position, and that every change on the board
is actually refreshed. `tests/preview.lua` renders the board to an SVG for
inspection without a device:

```
luajit tests/preview.lua board.svg 1448 1072
```

## Project layout

```
backgammon.koplugin/
├── _meta.lua           plugin manifest
├── main.lua            menu entry
├── bg/
│   ├── rules.lua       board, legal moves, bearing off, scoring (pure Lua)
│   ├── game.lua        turn and match state
│   ├── dice.lua        seeding and rolling
│   └── boardview.lua   drawing, touch input, screen refresh
└── tests/
    ├── run.lua         engine tests
    ├── view.lua        view tests against a mock KOReader
    ├── preview.lua     SVG dump of a painted board
    └── mock/           stand-ins for the KOReader modules the view uses
```
