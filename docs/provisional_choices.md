# Provisional choices

Choices Claude made while building the prototype, where the design record
(and `docs/decisions.md`) didn't give an answer. **None of these are design
decisions.** They exist so the prototype can run; each is a starting point
for you to confirm, change or reject. Numbers live in `config/tuning.cfg`
(marked "NOT FROM THE DESIGN" or naming the lean they follow), so most can be
changed without touching code.

When you decide one, record it in `docs/decisions.md` and remove it here.

## Where a Section 5 lean was used

| Open decision | Lean used | Where |
|---|---|---|
| D6 What crouching changes | Slower and harder to spot, no extra drain. "Quieter" waits for the noise system, which isn't in the prototype. | `[player] crouch_speed_mps`; monster sight (Stage 6) |
| D17 Can sprinting alone kill? | No: sprinting stops at a floor. When the fill reaches it, sprinting stops until the key is released and pressed again. | `[bar] sprint_floor_percent_of_max` |
| D17 Does a map clear heal earlier wounds before the toll? | Yes: escaping a collapse restores the ceiling, then applies the toll (Stage 5). | `scripts/bar.gd` `heal_wounds()` |

## Values and rules not in the design

| Stage | Choice | Value | Where |
|---|---|---|---|
| 1 | Walk speed | 3.0 m/s | `[player] walk_speed_mps` |
| 1 | Mouse sensitivity | 0.12° per pixel | `[player] mouse_sensitivity_deg_per_px` |
| 1 | Eye height and body size | 1.6 m eyes, 1.8 m × 0.35 m capsule | `scenes/player.tscn` |
| 2 | Cell size, wall height and thickness | 3 m, 3 m, 0.2 m | `[maze]` |
| 2 | Map colors | A gray-blue, B sandy brown | `[maps]` |
| 2 | Start cell of a 20 × 20 map | (10, 10) | `scripts/maze/maze_generator.gd` |
| 2 | A dead end visible from the objective is opened up (instead of rerolling the map) | — | `scripts/maze/maze_generator.gd` |
| 3 | Blended-wall panel count | 4 | `[swap] blended_wall_panels` |
| 3 | "A few seconds" for the quick-swap (accidental) metric | 5 s | `[playtest] quick_swap_window_seconds` |
| 3 | Swap-now debug key | N | `project.godot` input map |
| 4 | Sprint speed | 5.5 m/s | `[player] sprint_speed_mps` |
| 4 | Crouch speed and eye height | 1.5 m/s, 1.0 m | `[player]` |
| 4 | Sprint floor | 10% of the maximum bar | `[bar] sprint_floor_percent_of_max` |
| 4 | Regeneration and drain rates are measured against the maximum bar ("refills to the ceiling in about 60 s" read as 100% per 60 s), and regeneration runs whenever you aren't sprinting | — | `scripts/bar.gd` |
| 4 | Pickups per map | 3 bandages, 1 hospital kit, at least 4 cells apart, never in a dead-end branch, landing spot, the start or the objective's cell | `[items]` |
| 4 | Picking up | Walk within 1 m; goes to the first free slot; a full inventory leaves the item | `[items] pickup_radius_m` |
| 4 | Using items | Keys 1 to 3 use that slot | `project.godot` input map |
| 4 | Controls | Shift sprints, Ctrl (held) crouches | `project.godot` input map |
| 4 | HUD | Bar at the bottom (fill, ceiling, lost part, sprint floor tick) and three item slots | `scripts/hud.gd` |
| 2 | Every layout (normal and collapse) keeps at least 2 dead ends; braiding is retried from the same seed until it does. Added in Stage 5, after about 1 map in 80 turned out to have none, so it could never be left (or its collapse never escaped) | 2 | `[maze] min_dead_ends_per_layout` |
| 5 | Activating the objective | E within 2 m | `[objective] activate_distance_m` |
| 5 | The signal | A 60 m pale-yellow beam above the objective's pedestal; it goes out (and the pedestal darkens) once activated | `scripts/maze/maze_builder.gd` |
| 5 | The collapse layout | The normal braiding pass with the 80% / 20% weighting swapped, run on the maze as it was before braiding, then the long walk. The "no dead end visible from the objective" rule isn't applied to it | `scripts/maze/maze_generator.gd` `_plan_collapse` |
| 5 | What "the player can't see" means for the rearrangement | Outside 65° of where they look, or with a wall in the way; walls within 1.5 m never change; a closing wall that would cut off any part of the map waits. Checked every 0.25 s | `scripts/collapse.gd` |
| 5 | A dead end in view can't be rearranged away | A side effect of only changing what the player can't see: someone who keeps looking at an old dead end near the objective can still escape through it during the collapse | `scripts/collapse.gd` |
| 5 | Any swap out of the collapsing map counts as the escape, including the debug swap-now key | — | `scripts/collapse.gd` |
| 5 | "Ejected near the objective" | A gaze swap from a dead end in the half of the map nearer the objective (straight-line), before the objective was reached | `scripts/swap_controller.gd` |
| 5 | "Time to reach each objective" | Logged both as run time and as time spent in that map | `scripts/collapse.gd` |
| 5 | Results screen keys | Enter starts a new run with a new seed; R replays the same seed | `scripts/results_screen.gd` |
| 6 | Monsters per map and where they start | 2, at least 6 cells (straight-line) from the start and landing spots and from each other, never in a dead-end branch | `[monsters] monsters_per_map`, `spawn_min_distance_cells` |
| 6 | Monster speeds | Patrol 1.4, suspicious 2.0, chase 4.2 m/s (between walking and sprinting) | `[monsters]` |
| 6 | Monster sight | A 55° half-angle cone, 14 m range (times the sensitivity multiplier: ×1.25 with two maps in the pool), blocked by walls; × 0.6 range against a crouching player (D6 lean) | `[monsters]` |
| 6 | When it gives chase | At once within 5 m; otherwise after seeing the player for 0.75 s while suspicious | `[monsters] close_range_m`, `notice_seconds` |
| 6 | Search | 6 s around the last known position, then back to its spawn and patrol | `[monsters] search_seconds` |
| 6 | Hits | Within 1.2 m, at most every 1.5 s, then a 0.8 s pause. Hits during a collapse count as "heavy" (they also lower the ceiling); the design doesn't say what a heavy hit is | `[monsters]` |
| 3, 6 | Grace period | Starts on every swap. Monsters ignore the player (can't see or hit them) until it runs out | `scripts/monster.gd` |
| 6 | Idle reversion | A map's monsters return to patrol and pause while the player is in another map | `scripts/monsters.gd` |
| 6 | Monsters have no collision | The player can walk through a monster; it only affects them by hitting | `scenes/monster.tscn` |
| 6 | Monster movement | Cell to cell along the maze grid (shortest paths through open walls), not Godot's navigation system; inside the player's cell it steps straight at them | `scripts/monster.gd` |
| 6 | Look and sound | A dark capsule with two red eyes; footsteps are a short thud made in code, louder and faster when chasing | `scenes/monster.tscn`, `scripts/monsters.gd` |
| 6 | Bleed-over | Not built: with two maps, a run ends at the first escape, so no map is ever removed mid-run | — |
| 2 / 6.2 | The environmental tells | The floor darkens along every dead-end branch, from 10% darker at its first cell to 40% at the end wall. During a collapse the tells follow the new dead ends, only where the player can't see. Built in Stage 6, before the playtest: Section 6.2 lists simple tells, but no roadmap stage does | `[maze] tell_darken_entry`, `tell_darken_tip` |
| 7 | Debug keys switch for playtests | `debug_keys_enabled=false` turns off Tab and N | `[playtest] debug_keys_enabled` |
| 7 | "Narrow escape" in the log summary | A swap during a chase with the nearest chasing monster within 5 m | `tools/summarize_logs.gd` |
| 7 | Playtest session length and the extra "explain the rule" question | Suggestions only, in the playtest guide | `docs/playtest_1.md` |
