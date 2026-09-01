# Third-party notices

## GNU Backgammon (neural-net opponent, levels 4 and 5)

The "Expert" and "Master" difficulties use the trained neural network from
**GNU Backgammon (gnubg)**.

- `bg/gnu.weights` are gnubg's trained network weights, repacked (contact, race
  and crashed nets only) from `gnubg.weights` in the gnubg source distribution.
- `bg/gnu.lua` ports gnubg's input encoding and forward pass (`eval.c`,
  `lib/inputs.c`, `lib/neuralnet.c`) to Lua.

GNU Backgammon is Copyright (C) the GNU Backgammon authors and is licensed under
the **GNU General Public License, version 3 or later**. Source:
<https://www.gnu.org/software/gnubg/> and <https://ftp.gnu.org/gnu/gnubg/>.

Because this plugin includes gnubg's weights and ports its evaluation code, the
work is a derivative of gnubg and is therefore distributed under the **GPL-3.0
-or-later**. A copy of the license is available at
<https://www.gnu.org/licenses/gpl-3.0.html>.

Levels 1–3 (the heuristic opponents) and the rest of the plugin are original to
this project and do not use gnubg.
