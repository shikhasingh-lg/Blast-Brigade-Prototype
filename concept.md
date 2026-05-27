---
name: Blast Brigade — Concept (one-pager)
status: under-review — both prior reviews (lead designer + producer) recommended KILL/don't-pivot
created: 2026-05-26
sibling-concepts: Pop Brigade, Ricochet Brigade, Stomp Brigade
audience: leadership pitch (concept selection)
origin: variant of Pop Brigade v2 — replace bubble-pop with direct-damage cannon + TD currency spawn
---

# Blast Brigade

## One-line pitch

*Aim the cannon. Blast the horde. Earn currency. Spawn heroes. Hold the line.*

## Identity

| Field | Value |
| --- | --- |
| Working title | **Blast Brigade** *(alt: Boom Brigade, Volley Brigade, Cannon Brigade)* |
| Genre / subgenre | Portrait lane-defense × player-aimed artillery. Cannon at bottom of screen, enemies march in from the top depth-rail. Player aims cannon and fires bombs that kill enemies directly. Kills drop currency. Currency spawns heroes onto the row above the cannon; heroes auto-fire at enemies. Five colors = five hero classes. Roguelike runs + gacha hero meta. |
| Target audience | Hybrid casual leaning mid-core. Random Dice / Survivor.io / Squad Busters player. ~5-min sessions. Two parallel inputs: continuous cannon aim + intermittent hero placement. |
| Theme / lore | Reuses Pop Brigade roster + brand aesthetic. Cannon-operator-on-the-wall fantasy retained from Pop Brigade v2, but without the bubble wall — direct-fire artillery instead. |

## Core thesis

**Player-voice, ~110 words.**

I'm at the bottom of the screen with a cannon. Enemies march at me from the horizon, getting bigger as they approach. I aim the cannon with my thumb and fire bombs — each shot kills directly, no mediation, just explosions and ragdolling enemies. Every kill drops coins. When I have enough coins, a slot lights up — I tap it to spawn a hero on the row above me. That hero auto-fires at enemies in their column. Five colors, five classes. The cannon is my main weapon; the heroes are my passive line. Survive fifteen waves, kill the boss, pull the gacha.

### Comp anchor in one line

**Random Dice's currency-spawn TD loop × Survivor.io's continuous auto-DPS × Squad Busters' colored brigade meta.** Three proven layers, no novel binding — that's the central concern.

## Layout

```
   ☁              ☁              ← sky
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━

       e   e   e   e             ← far enemies on horizon (small)
              e   e
       e   e   e                  ← they walk forward on depth rail
                                       (pseudo-3D scaling up)

         🔥  ❄   🌿  🏹           ← hero row (auto-fire, TD-spawned)

                ⊕                 ← cannon (player POV, aim + fire)
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━
            [COINS: 🪙 320 / 500] [next hero unlock]
            [WAVE 1 / 5]
```

Portrait. Same general layout as Pop Brigade v2 — but the bubble wall between cannon and enemies is **gone**. Cannon fires directly at enemies on the depth rail.

## Core verb

**Two verbs, two modes:**

1. **Continuous (the main verb):** drag-aim cannon → release to fire bomb. Bomb travels, impacts, AOE damage to enemies in the splash radius. Pre-trained twitch aim, reflex layer.
2. **Intermittent (the meta verb):** when coin budget passes a threshold, a hero-spawn slot lights up. Tap the slot, pick a hero (or it spawns next-in-queue), hero takes a fixed cell on the hero row and auto-fires forever (or until killed).

The two verbs don't interact mechanically — they're parallel damage sources hitting the same enemy pool.

## Why this concept exists

Blast Brigade is the **variant pitch** that emerged from prototype frustration with Pop Brigade v2's two complaints:
1. **Bubble pop doesn't feel like a kill** (causality break)
2. **Three pressures on one verb is too heavy** (cognitive overload)

The variant solves both by:
- Replacing the bubble wall with direct-fire cannon → kill is immediate
- Replacing "pop the wall to free heroes" with "currency-on-kill spawns heroes" → no overloaded verb

**But:** the variant solves these problems by deleting the moat. The bubble wall (and gate trilemma) was Pop Brigade's differentiation — the thing that made it *not* generic TD. Without it, Blast Brigade lands in a saturated comp set.

## Prior review verdicts

Both pressure-tests recommended **don't pivot, kill the variant**:

| Reviewer | Verdict | Key reason |
|---|---|---|
| Lead Designer (game-feel) | KILL — stay on Pop Brigade v2 | Decisions/30s drops from ~10-12 to ~2-3; cannon-aim is reflex not decision; cannon+heroes are parallel DPS, not synergy. Differentiation collapses. |
| Senior Producer (scope/market) | Stay on v2, don't pivot | Variant comp set (Random Dice / Squad Busters / Survivor.io) is unwinnable for a 10-person team in 6 months. UA hook becomes "watch a meter fill" — generic vs Pop Brigade's "wall-pours-heroes-out" scroll-stopper. |

Both reviewers said: **steal the currency-on-kill drip and a charged-cannon ultimate from Blast Brigade and fold them into Pop Brigade v2 as secondary systems.** Don't replace the wall.

## The case for Blast Brigade anyway

Why this folder exists despite both reviews:
1. **Cognitive load is genuinely lower** — two clean modes, each with a single decision, beats Pop Brigade v2's 3-pressures-on-1-verb load
2. **Feel is genuinely higher** — direct bomb-cannon kills are dopamine-loaded vs Pop Brigade v2's mediated pop→hero→kill chain
3. **The verb is pre-trained** — aim-and-shoot is muscle memory; bubble-shooter mediated-kill is not
4. **Production scope is lower** — TD-spawn loops are well-understood; bubble + TD coupling is novel and tuning-heavy

If the Stomp Brigade paper test fails AND the Pop Brigade v2 causality hack fails, Blast Brigade becomes the fallback — but only with a clear answer to "how is this different from Random Dice with a cannon?"

## The three hypotheses (if revisited)

| # | Claim | Falsification |
|---|---|---|
| H1 | A single-line answer exists to "why isn't this Random Dice with a cannon?" | 30-min web search + AppMagic comp scan finds 3+ shipped games with same loop and no clear differentiator |
| H2 | UA creative for "aim cannon, kill enemy, currency spawns hero" is thumb-stoppable vs incumbent ads | Creative test against Lucky Defense / Random Dice baseline CTR — must hit ≥75% of baseline |
| H3 | Live-ops content burn is sustainable for a 10-person team | Map a 12-month content cadence — heroes, enemies, boss patterns, events. If ≥3 of 12 months are content-starved, scope fails. |

## What it borrows from Pop Brigade

Direct port:
- Cannon position + aim mechanic (cannon already exists in v2 Godot build)
- All 5 hero classes and color identities
- Gacha + merge meta-loop
- Wave + boss-stage structure
- Brand aesthetic, palette

Replaces:
- Bubble wall → no wall, direct-fire cannon
- Pop verb → fire-bomb verb
- Hero-bubble-frees-hero → currency-on-kill spawns hero
- Move budget → ammo regen + currency budget

## Honest weaknesses

1. **No moat** — primary concern. The conveyor (Stomp Brigade) and bubble wall (Pop Brigade) both have co-owned front-line resources. Blast Brigade does not — the depth rail is just a path enemies walk on.
2. **Cannon-aim is reflex, not decision** — twitch skill, not strategy. Lowers ceiling for puzzle-trained players (Pop Brigade's actual audience).
3. **Cannon + heroes = parallel DPS** — no mechanical reason for the two damage sources to feel like cooperation. Risk: cannon feels redundant after heroes are spawned.
4. **UA economics** — competing against shipped games with 5+ years of balance work and 100× the ad spend in the same comp set.

## Mitigation paths (if revived)

To make Blast Brigade viable, you'd need at least one of:
- **Cannon-hero synergy** — cannon applies debuff (stagger, armor break, wet) that heroes exploit for bonus damage. Not parallel DPS.
- **Cannon doesn't kill, only softens** — heroes must finish for currency to drop. Forces tradeoff.
- **Cannon charges hero ultimates** — shots build hero meter, not damage. Repositions cannon as support, not primary.
- **A unique front-line resource** — destructible terrain, push-back conveyor, breakable barricades. Something the player and enemy both manipulate.

Without one of these, Blast Brigade is generic TD with a player-aimed cannon — not differentiable enough to win UA against incumbents.

## Differentiation — comp set

Closest shipped games (the unwinnable ones):
- **Random Dice: Defense** — currency-spawn TD with dice-merge. 5+ years of balance.
- **Lucky Defense** — color-class hero TD with currency. Habby's playbook.
- **Survivor!.io / Archero** — auto-aim artillery with meta heroes.
- **Squad Busters** — colorful spawn-from-currency rhythm. Supercell.

**The honest answer to "how is this different?":** Currently — it isn't. That's the core problem this concept must solve before greenlight.

## What it is NOT

- ❌ Not Pop Brigade (no bubble wall, no pop verb, no gate trilemma)
- ❌ Not Stomp Brigade (no conveyor, no shared grid)
- ❌ Not Ricochet Brigade (no slingshot, no ricochet, no flicked-hero placement)

## Status

| Phase | Status |
|---|---|
| Concept doc | ✓ this file |
| Lead Designer review | ✓ KILL (see prior verdict) |
| Producer review | ✓ Don't pivot (see prior verdict) |
| Paper test | ☐ not scheduled — gated on Stomp Brigade + Pop Brigade v2 hack results |
| Verdict (BUILD / ITERATE / KILL) | ☐ pending |
| Godot prototype | ✓ V0 forked from Pop Brigade v2 at `./godot/` — cannon fires bombs, currency on kill, hero spawn button (start 60, kill +12, spawn cost 30) |

## Next action

**Do not pursue actively.** Hold in folder as the explicit fallback if:
1. Stomp Brigade paper test fails (D1+D2+D3 averages <4)
2. AND Pop Brigade v2 causality hack fails (D1/D3 deltas <+1)
3. AND a credible differentiator emerges (cannon-hero synergy mechanic, novel front-line resource)

If all three conditions are met, revisit this doc and design the differentiator before committing engineering time.

## Related concepts

- Sibling: `~/game-research/pop-brigade/` (the concept Blast Brigade is a variant of)
- Sibling: `~/game-research/stomp-brigade/` (the active third-option being paper-tested)
- Sibling: `~/game-research/ricochet-brigade/` (the slingshot mid-core counterpart)
