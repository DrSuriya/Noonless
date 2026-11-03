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
| 3 | Grace period effect before monsters exist | Only a timer | — |
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
