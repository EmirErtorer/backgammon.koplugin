<p><picture><source media="(prefers-color-scheme: dark)" srcset="assets/backgammon-title-dark.svg"><img src="assets/backgammon-title.svg" alt="Backgammon"></picture><br>
<img src="assets/readme-divider.svg" width="100%" alt=""></p>

[![GitHub Release](https://img.shields.io/github/v/release/EmirErtorer/backgammon.koplugin?style=for-the-badge&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZiIgZmlsbC1ydWxlPSJldmVub2RkIj48cGF0aCBkPSJNMyAzaDguNUwyMSAxMi41IDEyLjUgMjEgMyAxMS41ek03LjUgNS41YTIgMiAwIDEgMCAwIDQgMiAyIDAgMCAwIDAtNHoiLz48L3N2Zz4%3D&label=Latest%20Release&labelColor=rgb(91%2C%2052%2C%2032)&color=rgb(239%2C233%2C223))](https://github.com/EmirErtorer/backgammon.koplugin/releases/latest)
[![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/EmirErtorer/backgammon.koplugin/total?style=for-the-badge&logo=data%3Aimage%2Fsvg%2Bxml%3Bbase64%2CPHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0iI2ZmZiI%2BPHBhdGggZD0iTTExIDNoMnY5LjE3bDMuNTktMy41OEwxOCAxMGwtNiA2LTYtNiAxLjQxLTEuNDFMMTEgMTIuMTd6TTQgMTVoMnYzaDEydi0zaDJ2NUg0eiIvPjwvc3ZnPg%3D%3D&label=Total%20Downloads&labelColor=rgb(91%2C%2052%2C%2032)&color=rgb(239%2C233%2C223))](https://github.com/EmirErtorer/backgammon.koplugin/releases)

A **backgammon** (tavla) board for KOReader. Play a friend on the same device, or take on the **computer** at five levels, the top two running **GNU Backgammon's neural network**. On a colour screen it comes in mother of pearl and brown, with six themes to pick from.

<table>
  <tr>
    <td width="33%" valign="top"><a href="assets/screenshots/board.png"><img src="assets/screenshots/board.png" alt="The board"></a><br><sub>Tap a checker and the points it can reach light up.</sub></td>
    <td width="33%" valign="top"><a href="assets/screenshots/themes.png"><img src="assets/screenshots/themes.png" alt="The theme picker"></a><br><sub>Six themes, from <b>Board &amp; colours</b>.</sub></td>
    <td width="33%" valign="top"><a href="assets/screenshots/setup.png"><img src="assets/screenshots/setup.png" alt="Choosing a game"></a><br><sub>Two players, or the computer at five levels.</sub></td>
  </tr>
  <tr>
    <td colspan="2" width="66%" valign="top"><a href="assets/screenshots/landscape.png"><img src="assets/screenshots/landscape.png" alt="Landscape with a double offered"></a><br><sub>Landscape at the tap of a button, with the doubling cube on.</sub></td>
    <td width="33%" valign="top"><a href="assets/screenshots/review.png"><img src="assets/screenshots/review.png" alt="Game review"></a><br><sub>After the game: your costliest moves.</sub></td>
  </tr>
</table>


## Features

| | |
|---|---|
| **The computer** | Five levels. Levels 1 to 3 are hand written. Levels 4 and 5 run GNU Backgammon's networks in pure Lua, and Master looks a full roll ahead. |
| **Two players** | Share one device. The board can turn round each turn. |
| **Doubling cube** | Optional. Turn it on under **Board & colours**. |
| **Colour and themes** | Classic (mother of pearl and brown), Forest, Ocean, Rosewood, Midnight or Black & white. Board, dice, buttons, menus and dialogs follow the theme, and a one is red. Black and white screens keep the grey look. |
| **Review and statistics** | Every move is compared with the neural network's choice, and your record against each level is kept. |
| **Take back and resume** | Undo steps back through the turn. A game left half way is waiting under **Resume game**. |
| **Portrait or landscape, English or Turkish** | Both orientations are equally fast. |


## Installation

<a href="https://github.com/EmirErtorer/backgammon.koplugin/releases/latest"><img src="assets/readme-download.svg" alt="Download the latest release"></a>

Unzip the download and copy the `backgammon.koplugin` folder inside it into KOReader's `plugins` directory:

- Kindle: `koreader/plugins/backgammon.koplugin/`
- Kobo: `.adds/koreader/plugins/backgammon.koplugin/`
- Android: `koreader/plugins/backgammon.koplugin/` in app storage
- Desktop: the `plugins` folder next to the KOReader binary

Then restart KOReader. Open it from the top menu → **Tools** tab → **Backgammon**.


## License

GPL 3.0 or later (see [`LICENSE`](LICENSE)). The Expert and Master levels use the neural network weights and evaluation from GNU Backgammon, see [`NOTICE.md`](NOTICE.md).
