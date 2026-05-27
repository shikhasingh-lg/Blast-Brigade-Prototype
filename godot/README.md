# Pop Brigade v2 — Godot prototype

Greybox of the v2 redesign. Design spec lives one folder up at `../*.md`.

## Run it

Open this folder in Godot 4.6 (Mobile). Press F5 — boots into `MatchScene`.

**Controls:**
- **Move mouse** to aim (clamped ±75° from straight up).
- **Click** away from heroes to fire the cannon. Each shot spends a move.
- **Press-and-drag** a hero on row 0 to move/swap/merge it along the row (no phase gate — drag is always live).
- **R** to reseed the current wave's gate.
- **N** to manually advance to the next wave.
- **K** to kill all live enemies (debug).
- **C** to crack a random closed column (debug — tests 3-state gate + hero firing reaction).

What works: hex grid (odd-r offset) gate, seed cluster per wave palette, match-3 BFS pop, floater drop, cannon misses attach + cost a move, wall-reflect; pseudo-3D enemy lane with telegraph → bash → walk-down → engage or breach to cannon; heroes (Fire Knight / Ice Mage / Archer) freed by popping hero bubbles (tier scales with match size: 3-5 Bronze, 6-9 Silver, 10+ Gold), auto-fire through gate with column-occlusion (Archer checks own column, FK/IM check target's column), color counter ×2 same-class-vs-enemy, FK 25% cleave, IM AoE splash, Archer execute <30% HP, drag/merge/swap on row 0, queue overflow (FIFO max 3), enemy-hero melee engagement (DPS tick), hero death → queue refill.

What's missing (later phases): VFX scenes (placeholder draw_circle stubs), ultimates, class synergies, color frenzy, boss wave, audio.

3-state gate is now in: bubbles can be `is_cracked` (visible fracture overlay), `Gate.column_state()` returns open/cracked/open, `Hero.gd` respects column state per combat-design §1.2 — Archer + Wizard gate own column, FK/IM/Druid gate target's column. Closed = 60% opacity + dashed "would-fire" line to the blocking bubble. **C** key cracks a random column for testing. The "enemy bashes the gate → crack" trigger is not yet wired; cracks currently come from the debug key only.

Display is locked portrait, 720×1560.

## Folder map

```
godot/
├── project.godot
├── icon.svg
├── scenes/
│   ├── Main.tscn          # boot scene → MatchScene
│   └── MatchScene.tscn    # gameplay root (placeholder)
├── scripts/
│   ├── GameConfig.gd      # autoload: all §9 + combat §7 tunables
│   ├── RunState.gd        # autoload: per-run state + signals
│   ├── Telemetry.gd       # autoload: §10 event stubs
│   ├── Main.gd
│   ├── MatchScene.gd
│   ├── Gate.gd / Bubble.gd / Projectile.gd / Cannon.gd
│   ├── EnemyLane.gd / Enemy.gd / LaneBackdrop.gd
│   └── HeroRow.gd / Hero.gd / HeroBullet.gd     # phase 3
├── assets/                # sprites, sfx (empty)
└── configs/               # tuning JSON / .tres (empty)
```

## Phase status

| Phase | What | Status |
|---|---|---|
| 0 | Scaffold: project + autoloads + zone overlay | ✅ |
| 1 | Gate grid + cannon + match/pop | ✅ |
| 2 | Enemy depth lane (spawn → walk → bash → base dmg) | ✅ |
| 3 | Heroes + bullet occlusion | ✅ |
| 4 | 5-wave loop with intermission | ✅ |
| 5 | Hero classes (Druid/Wizard) + status effects (5) | ✅ |
| 6 | Boss wave: The Corrupter | — |
| 7 | Ultimates + class synergies + frenzy | — |
| 8 | Telemetry wiring + tuning UI | — |

Meta loop (gacha, shards, battle pass, world map) is **out of scope** for the prototype — separate phase once core combat feel locks.

## Where the spec lives

- `../README.md` — design overview, locked decisions
- `../concept.md` — gate metaphor + elevator pitch
- `../design-spec.md` — mechanical truth (§9 = config exports, §10 = telemetry)
- `../combat-design.md` — hero classes, ultimates, status effects, synergies
- `../boss-design.md` — Corrupter spec
- `../progression.md`, `../economy.md`, `../onboarding.md` — meta-loop (out of prototype scope)
