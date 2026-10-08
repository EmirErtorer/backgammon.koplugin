<p><picture><source media="(prefers-color-scheme: dark)" srcset="assets/backgammon-title-dark.svg"><img src="assets/backgammon-title.svg" alt="Backgammon"></picture><br>
<img src="assets/readme-divider.svg" width="100%" alt=""></p>

[![GitHub Release](https://img.shields.io/github/v/release/EmirErtorer/backgammon.koplugin?style=for-the-badge&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZiIgZmlsbC1ydWxlPSJldmVub2RkIj48cGF0aCBkPSJNMyAzaDguNUwyMSAxMi41IDEyLjUgMjEgMyAxMS41ek03LjUgNS41YTIgMiAwIDEgMCAwIDQgMiAyIDAgMCAwIDAtNHoiLz48L3N2Zz4%3D&label=Latest%20Release&labelColor=rgb(91%2C%2052%2C%2032)&color=rgb(239%2C233%2C223))](https://github.com/EmirErtorer/backgammon.koplugin/releases/latest)
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/EmirErtorer/backgammon.koplugin/total?style=for-the-badge&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZiI%2BPHBhdGggZD0iTTExIDNoMnY5LjE3bDMuNTktMy41OEwxOCAxMGwtNiA2LTYtNiAxLjQxLTEuNDFMMTEgMTIuMTd6TTQgMTVoMnYzaDEydi0zaDJ2NUg0eiIvPjwvc3ZnPg%3D%3D&label=Total%20Downloads&labelColor=rgb(91%2C%2052%2C%2032)&color=rgb(239%2C233%2C223))](https://github.com/EmirErtorer/backgammon.koplugin/releases)

A **backgammon** (tavla) board for KOReader. Play a friend on the same device, or take on the **computer** at five levels, the top two running **GNU Backgammon's neural network**. Tap a checker to see where it can go, tap a point to move it. When the game is over, the review shows where you lost ground.

## Screenshots

<table>
  <tr>
    <td width="33%" valign="top"><a href="assets/screenshots/board.png"><img src="assets/screenshots/board.png" alt="The board"></a><br><sub>Tap a checker and the points it can reach light up. Undo takes a move back.</sub></td>
    <td width="33%" valign="top"><a href="assets/screenshots/setup.png"><img src="assets/screenshots/setup.png" alt="Choosing a game"></a><br><sub>Two players on one device, or the computer at five levels.</sub></td>
    <td width="33%" valign="top"><a href="assets/screenshots/review.png"><img src="assets/screenshots/review.png" alt="Game review"></a><br><sub>After the game: your costliest moves and what would have been better.</sub></td>
  </tr>
  <tr>
    <td colspan="2" width="66%" valign="top"><a href="assets/screenshots/landscape.png"><img src="assets/screenshots/landscape.png" alt="Landscape with a double offered"></a><br><sub>Landscape at the tap of a button. With the doubling cube on, the computer doubles you when it likes its chances.</sub></td>
    <td width="33%" valign="top"><a href="assets/screenshots/statistics.png"><img src="assets/screenshots/statistics.png" alt="Statistics"></a><br><sub>Your record against every level.</sub></td>
  </tr>
</table>


## Features

### Play

| | |
|---|---|
| **The computer** | Five levels, from a beginner who leaves easy shots to a master that looks a full roll ahead. |
| **Two players** | Share one device. The board can turn round each turn so whoever is on roll reads it upright. |
| **Tap to move** | Tap a checker and every point it can legally reach lights up. Tap one to move there. No dragging. |
| **Take back** | Undo steps back through the current turn one checker at a time and hands each die back. |
| **Doubling cube** | Optional. Either side can offer a double and the other takes or drops it. The computer does both on its own. |
| **Resume** | Close mid game and it is saved. Next time it is waiting under **Resume game**. |

### The computer

| Level | How it plays |
|---|---|
| **1 · Beginner** | Plays mostly by the race and leaves easy shots. A gentle start for learning. |
| **2 · Casual** | Plays safe and punishes loose blots, one move deep. |
| **3 · Skilled** | Looks a full roll ahead and plays the percentages. |
| **4 · Expert** | GNU Backgammon's neural network judges every position. Beats Skilled about four games in five. |
| **5 · Master** | The same network, looking a full roll ahead. The strongest, and the slowest: a couple of seconds a move on e ink. |

Levels 1 to 3 are hand written. Levels 4 and 5 run GNU Backgammon's contact, race and crashed networks in pure Lua, checked against the original C code across thousands of positions. The computer pauses between its moves so you can follow what it played.

### After the game

| | |
|---|---|
| **Review** | Every move you made is compared with the neural network's choice. The costliest ones are listed with the better play and a tip. |
| **Statistics** | Games played, your win streak and your record against each level. |
| **Scoreboard** | The session score across the top: 1 point for a win, 2 for a mars, 3 for a backgammon, times the cube. |

### Board and screen

| | |
|---|---|
| **Made for e ink** | Flat greys instead of textures, checkers told apart by shape as well as shade and small screen refreshes so play stays quick. |
| **Portrait or landscape** | A button in the header turns the board without turning the device. Both are equally fast, and KOReader goes back to its own orientation when you close. |
| **Your layout** | Play white or black at the bottom and bear off on the left or the right. |
| **Languages** | English and Turkish. It follows KOReader's language or you pick one. |

<details>
<summary><b>Rules and scoring</b></summary>

The standard starting position: two checkers on the 24 point, five on the 13, three on the 8 and five on the 6, counted from each player's own side.

* The first roll only decides who starts. Each side throws one die and the higher one goes first.
* A point with two or more enemy checkers is blocked. Landing on a single enemy checker (a blot) sends it to the bar.
* Doubles are played as four moves.
* Both dice must be played when there is a legal way to do so. If only one can be played, it must be the higher one when that is legal. So a move that looks fine on its own can be ruled out because it strands the other die. The highlighted points are always the legal ones.
* A checker on the bar must come back in before anything else moves. If it can't enter with either die, the turn passes on its own.
* Bearing off needs all fifteen checkers in the home board. A higher roll than your furthest checker bears that one off.

**Scoring:** 1 point for a normal win, 2 for a mars (the loser has borne off nothing), 3 for a backgammon (borne off nothing and still has a checker in the winner's home board). Wins are multiplied by the cube. A dropped double pays the stake before it.

</details>


## Installation

<a href="https://github.com/EmirErtorer/backgammon.koplugin/releases/latest"><img src="assets/readme-download.svg" alt="Download the latest release"></a>

Unzip the download and copy the `backgammon.koplugin` folder inside it into KOReader's `plugins` directory:

- Kindle: `koreader/plugins/backgammon.koplugin/`
- Kobo: `.adds/koreader/plugins/backgammon.koplugin/`
- Android: `koreader/plugins/backgammon.koplugin/` in app storage
- Desktop: the `plugins` folder next to the KOReader binary

Then restart KOReader. Open it from the top menu → **Tools** tab → **Backgammon**.


## Notes

- Works on any device KOReader runs on (Kindle, Kobo, PocketBook, Android or desktop) with any reasonably recent version. Pure Lua with no extra dependencies.
- The doubling cube is off by default. Turn it on under **Board & colours** on the start screen.
- Leaving a game with **Menu** or starting a **New game** mid play asks first.
- There is no match play yet: games are not played to a set number of points.


## License

GPL 3.0 or later (see [`LICENSE`](LICENSE)). The Expert and Master levels use the neural network weights and evaluation from GNU Backgammon, see [`NOTICE.md`](NOTICE.md).
