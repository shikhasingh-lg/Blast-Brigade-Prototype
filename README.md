# Blast Brigade — Prototype

Portrait lane-defense × player-aimed artillery. Aim the cannon, blast the
horde, earn currency on kill, spawn heroes onto the row above the cannon, hold
the line for the wave. A tuning prototype forked from Pop Brigade v2.

> **Working title.** "Blast Brigade" is a codename, not a finalized product
> name. See `concept.md` for status — both prior design reviews recommended
> hold/kill, and this concept is positioned as a fallback gated on sibling
> prototypes (Pop / Stomp / Ricochet Brigade).

## Run it

- **Engine:** Godot **4.6** (Mobile renderer)
- **Open:** launch Godot, import the `godot/` folder (the one containing
  `project.godot`)
- **Main scene:** `godot/scenes/Main.tscn` (set as the run scene — just press
  Play / F5)

## Layout

| Path | What |
|---|---|
| `concept.md` | Design one-pager: pitch, core loop, review verdicts, weaknesses |
| `godot/scripts/GameConfig.gd` | All gameplay tunables (waves, enemy HP/speed, hero stats, cannon) |
| `godot/scenes/` | Main, MatchScene (the run), MetaHub, RunClear, RunFail |
| `godot/assets/` | Runtime art (enemies, heroes, cannon, ui, status, vfx) |

## Debug keys (in a match)

- `R` — reseed gate
- `N` — advance wave
- `K` — kill all enemies

## Notes

- `godot/assets/bubbles/` is intentionally **not committed** — it's dead
  Pop Brigade art the cannon fork never loads. See `.gitignore`.
- Bubble-related scripts (`Bubble.gd`, gate-seeding in `Gate.gd`) are inert in
  this fork; kept only for column geometry.
