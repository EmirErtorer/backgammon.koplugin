# Backgammon for KOReader

A two-player backgammon (tavla) board for [KOReader](https://github.com/koreader/koreader).
Both players share one device and take turns on the same screen.

Built for e-ink: flat greys instead of textures, checkers told apart by shape as
well as shade, and small screen refreshes so play stays responsive.

- Two players on one device
- Full standard rules: hitting, the bar, bearing off, forced moves, doubles
- Tap to select a checker, tap a highlighted point to move — no dragging
- Session scoreboard with 1 / 2 / 3 point scoring (mars and backgammon)
- Portrait and landscape, switchable from a button in-game
- Pure Lua, no external dependencies, nothing written to disk

<img width="1448" height="1072" alt="backgammon_landscape" src="https://github.com/user-attachments/assets/ff82c57c-c1fc-49a2-a6fc-17443ca15987" />
<img width="1072" height="1448" alt="backgammon_portrait" src="https://github.com/user-attachments/assets/89d08650-7cf1-47af-a394-4e38bc3aa3ac" />



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

**Orientation.** The button in the top-left of the header flips the board
between portrait and landscape without physically rotating the device.

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

### A note on legal moves

Whether a move is legal can depend on the rest of the turn, not just one die.
Because both dice must be played when possible, a move that looks fine on its
own can be illegal if it would strand the other die. The highlighted moves are
always the legal ones — occasionally fewer than expected.

## Orientation and performance

Portrait is the recommended way to play. It is the native orientation of most
e-ink panels, so it stays fast and responsive.

Landscape is available from the button in the top-left, but on e-ink it has to
be redrawn with a software rotation, so it is slower. This is a device and
KOReader characteristic, not something the game controls.

**If play starts to feel sluggish** — most likely after switching orientation
back and forth, or after opening the game while KOReader itself is already in
landscape — **restart KOReader** and it returns to normal. For the smoothest
experience, keep KOReader in portrait and use the in-game button for landscape
rather than rotating the whole device.

## Limitations

- Two human players only, no computer opponent yet.
- No doubling cube.
- No undo once a checker is tapped into place.
- Bearing off is always on the right; the side is not configurable.
- Landscape is slower than portrait on e-ink; portrait is recommended.
- Nothing is saved: closing the plugin discards the score and any game in
  progress.
