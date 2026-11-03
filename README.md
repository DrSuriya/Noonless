# Horror maze prototype

A gray-box prototype of a roguelite horror maze game. It exists to answer one
question: is the dead-end swap fun and readable?

- `docs/design.pdf` is the design record (v1).
- `docs/decisions.md` logs decisions made since, and overrides the PDF.
- `docs/provisional_choices.md` lists choices made while building where the
  design gave no answer. None are decisions; they're there for you to review.
- `CLAUDE.md` is the brief for building the prototype.

## What exists

Roadmap stages 1 to 5 from Section 6.1 of the design.

**Stage 1, engine spike.** A first-person controller (walk and mouse look).
The old gray-box test room is still in `scenes/test_room.tscn` for trying the
controller on its own.

**Stage 2, maze generator.** Each run generates two maps from one seed and
keeps both built, far apart. You start in the middle of map A. Generation
follows Section 6.4:

1. A perfect maze (recursive backtracker), 20 × 20 cells of 3 m.
2. 6 to 8 rooms of 2×2 to 3×3 cells, never over the start.
3. The objective, in the middle of a random room from the farther half of
   rooms by walking distance from the start.
4. Three landing spots per map (for arrivals from the other map): one-cell
   alcoves off a corridor, in the half of the map farther from the
   objective, kept apart.
5. Braiding: each dead end survives with a chance that falls from 80% at the
   objective to 20% at the farthest cell (straight-line distance).
6. The long walk: dead-end branches shorter than 3 cells are opened up.
7. Validation: dead ends whose wall can be seen from the objective are opened
   up, and the Section 6.4 rules are checked.

Each map is one flat color: map A gray-blue, map B sandy brown. There's no
objective or dead-end tell in the 3D world yet; the debug view shows where
they are.

**Stage 3, the swap.** Walk to the end of a dead end and look at its end wall:
within 2 m of it and within 30° of facing it (looking up or down counts), a
hold timer runs, and after 0.3 s you swap to the other map. You land in one of
its landing spots for the map you came from, facing the blended wall: four
panels that step from the old map's color to the new one's. Turn around to
see the new map. Look away before 0.3 s and the timer resets. Each swap
starts a 10 s grace period; until monsters arrive in Stage 6 it's only a
timer in the debug overlay. Both maps stay built the whole run, so a map
you return to is unchanged. The landing spot is picked at random from the
run seed, so the same seed and the same swaps land in the same places.

**Stage 4, bar and movement.** Shift sprints and Ctrl crouches. The bar at
the bottom of the screen is the fill-and-ceiling model from Section 6.2:

- The bright part is the **fill** (stamina). Sprinting drains it (a full bar
  lasts 15 s); not sprinting regenerates it (60 s from empty).
- The **ceiling** (health) is where the dark part ends. Past it, shown in dark
  red, is what's lost until healed. Heavy hits and the escape toll lower it.
- The thin tick is the **floor**. Sprinting can't take the fill below it, so
  sprinting alone can't kill; at the floor, sprinting stops until you release
  Shift and press it again.
- Hits take 25 off the fill; if it reaches zero you die.

Each map has 3 bandages (small white boxes) and a hospital kit (red box)
lying in its corridors and rooms. Walk over one to put it in the first free
slot (three, shown next to the bar). Press 1, 2 or 3 to use a slot: a bandage
raises the ceiling by 10; a hospital kit raises it by 40 and refills the
fill. Taken items stay gone for the run.

**Stage 5, objective and collapse.** Each map's objective is a yellow
pedestal in the middle of a room, with a beam of light rising far above the
walls as its signal. Stand within 2 m and press E to activate it. That
starts the map's collapse:

- You **rush**: sprinting costs nothing and every speed is 25% faster. The
  fill turns red.
- The map **rearranges** into its collapse layout, precomputed from the seed
  with the braiding weighting inverted: dead ends near the objective open
  up and new ones appear toward the edges. Walls only change where you can't
  see them, never right next to you, and never in a way that cuts part of
  the map off. Memorized dead ends become useless.
- Escaping takes the **one-second stare** at a dead end instead of 0.3 s.
- When you escape, earlier wounds heal and then the **toll** comes off the
  ceiling: 1% of the bar per second of rushing, capped at 50%. The map
  leaves the pool.

As a placeholder for D1 and D2 (what the last map does and what the final
map is), escaping the first collapse ends the run on the **results screen**,
which shows the run's Section 6.6 metrics. Dying (the fill reaching zero)
ends the run there too. Enter starts a new run with a new seed; R replays
the same seed.

Every layout keeps at least two dead ends, normal and collapse, so a map can
always be left and a collapse always escaped.

**Event log.** Each run writes a log file, one JSON object per line: the run
start, every swap (trigger, maps, dead end, landing spot, seconds since you
entered the dead end's branch), entering a dead-end branch, and a summary
when the run ends. It also tracks the Section 6.6 metrics that can be
measured so far: swaps per minute (split by chase; there are no chases until
Stage 6), quick swaps (no chase, within 5 s of entering the branch, the
proxy for accidental swaps) and time spent standing still. A new seed or
closing the window ends the run. The file's path is printed in Godot's
Output panel and shown in the full debug view. On Linux the files are in
`~/.local/share/godot/app_userdata/Horror maze prototype/event_logs/`; on
Windows, `%APPDATA%\Godot\app_userdata\Horror maze prototype\event_logs\`; on
macOS, `~/Library/Application Support/Godot/app_userdata/Horror maze prototype/event_logs/`.

**Debug overlay** (Tab cycles off → status strip → full view → off):

- The **status strip** sits in the corner while you play: the map you're in,
  the hold timer (with a bar), the grace timer, the metrics so far and the
  last few events.
- The **full view** adds both maps from above, with dead ends colored by
  distance to the objective (their branches faded), landing spots lettered
  with the map arrivals come from, the objective, the start and you. It shows
  the run seed and counts dead ends near and far from the objective. Type a
  seed in its field to regenerate the run.

Every tunable number is in `config/tuning.cfg`, with a comment naming the
decision it stands in for.

## How to run

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build;
   .NET isn't needed). Built and tested with 4.7.2 stable.
2. In the Godot project manager, choose **Import** and pick `project.godot`
   in this folder.
3. Press **F5** (Run Project).

From a terminal: `godot --path /path/to/this/folder`.

Each launch uses a new random seed. It's printed in Godot's Output panel
(`Run seed: …`) and shown in the debug view.

## Controls

| Input      | Action                             |
|------------|------------------------------------|
| W A S D    | Walk                               |
| Mouse      | Look                               |
| Shift      | Sprint                             |
| Ctrl       | Crouch (hold)                      |
| 1 2 3      | Use the item in that slot          |
| E          | Activate the objective             |
| N          | Swap now (debug)                   |
| Tab        | Debug overlay: off, strip, full    |
| Esc        | Free the mouse cursor              |
| Left click | Capture the mouse cursor again     |

To load a seed: press Tab twice for the full view, then Esc, click the seed
field, type a number and press Enter. The run regenerates and you're back at
the start of map A.

On the results screen: Enter starts a new run, R replays the same seed.

To quit, press Esc and close the window.

## Tests

Two headless test files. From the project folder:

```
godot --headless --path . -s res://tests/test_maze_generator.gd
godot --headless --path . -s res://tests/test_swap.gd
godot --headless --path . -s res://tests/test_bar.gd
godot --headless --path . -s res://tests/test_collapse.gd
```

- `test_maze_generator.gd` checks the maze generator and the Section 6.4
  validation rules (the objective is reachable, no dead-end wall is visible
  from the objective, landing spots never count as dead ends). It sweeps 200
  run seeds, checks that the same seed gives the same maps, and checks that
  the validator catches each broken rule. It takes about 20 seconds.
- `test_swap.gd` checks the trigger and the swap: the hold time, the 30°
  facing limit (including looking down), the 2 m distance, swapping both
  ways, landing facing the blended wall, the swap-now key, the event log,
  that maps are unchanged after swaps, and that the same seed lands in the
  same spots.
- `test_bar.gd` checks the bar rules (regeneration, drain, the sprint floor,
  hits, items, death), the walk, sprint and crouch speeds, and picking up
  and using items in a real run.
- `test_collapse.gd` checks activating the objective, the rush, that the
  rearrangement never changes a wall a 3D raycast from your eyes can see,
  that the map stays connected and reaches its collapse layout, the
  one-second stare, the toll, the pool, the results screen and restarting,
  and death.

Each prints its checks and exits with the number of failures (0 means all
passed). Any engine or script error during a test also counts as a failure,
so a test that breaks partway can't pass.

## Tuning

Edit `config/tuning.cfg` and run again; no code changes needed. The `Tuning`
autoload (`scripts/tuning.gd`) reads the file once at startup, and a missing
key is reported as an error rather than replaced by a default.

## Layout

| Path                              | What it is                                   |
|-----------------------------------|----------------------------------------------|
| `project.godot`                   | Project settings, input map, autoloads       |
| `config/tuning.cfg`               | Every undecided number and rule              |
| `scenes/main.tscn`                | Main scene: both maps, player, debug view    |
| `scenes/player.tscn`              | First-person player                          |
| `scenes/test_room.tscn`           | Stage 1 gray-box test room                   |
| `scripts/main.gd`                 | Generates and builds a run's maps            |
| `scripts/swap_controller.gd`      | The dead-end trigger, swap and grace timer   |
| `scripts/event_log.gd`            | The event log and Section 6.6 metrics        |
| `scripts/bar.gd`                  | The fill-and-ceiling bar                     |
| `scripts/inventory.gd`            | Item slots                                   |
| `scripts/survival.gd`             | The run's bar and items: pickups, use, hits  |
| `scripts/hud.gd`                  | The on-screen bar and item slots             |
| `scripts/collapse.gd`             | The objective, collapse, rush and toll       |
| `scripts/results_screen.gd`       | The end-of-run results screen                |
| `scripts/player.gd`               | Walk and mouse look                          |
| `scripts/tuning.gd`               | Loads `config/tuning.cfg`                    |
| `scripts/maze/maze_map.gd`        | A map's grid: walls and tags                 |
| `scripts/maze/maze_generator.gd`  | Seeded generation (Section 6.4)              |
| `scripts/maze/maze_validator.gd`  | The validation rules                         |
| `scripts/maze/maze_builder.gd`    | Turns a map's grid into 3D geometry          |
| `scripts/maze/maze_params.gd`     | Maze settings from `config/tuning.cfg`       |
| `scripts/debug/debug_view.gd`     | The Tab debug overlay and seed field         |
| `tests/test_maze_generator.gd`    | Headless generator tests                     |
| `tests/test_swap.gd`              | Headless trigger and swap tests              |
| `tests/test_bar.gd`               | Headless bar, movement and item tests        |
| `tests/test_collapse.gd`          | Headless objective and collapse tests        |
| `tests/error_counter.gd`          | Makes any error during a test a failure      |
