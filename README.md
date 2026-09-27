# Horror maze prototype

A gray-box prototype of a roguelite horror maze game. It exists to answer one
question: is the dead-end swap fun and readable?

- `docs/design.pdf` is the design record (v1).
- `docs/decisions.md` logs decisions made since, and overrides the PDF.
- `CLAUDE.md` is the brief for building the prototype.

## What exists

Roadmap stages 1 and 2 from Section 6.1 of the design.

**Stage 1, engine spike.** A first-person controller (walk and mouse look).
The old gray-box test room is still in `scenes/test_room.tscn` for trying the
controller on its own.

**Stage 2, maze generator.** Each run generates two maps from one seed and
keeps both built, far apart. You start in the middle of map A. Map B is
built but can't be reached until the swap in Stage 3. Generation follows
Section 6.4:

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
objective, landing-spot wall or dead-end tell in the 3D world yet; the debug
view shows where they are.

**Debug view** (Tab): both maps from above, with dead ends colored by
distance to the objective (their branches faded), landing spots lettered
with the map arrivals come from, the objective, the start and you. It shows
the run seed and counts dead ends in the halves nearer to and farther from
the objective. Type a seed in its field to regenerate the run.

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
| Tab        | Show or hide the debug view        |
| Esc        | Free the mouse cursor              |
| Left click | Capture the mouse cursor again     |

To load a seed: press Tab, then Esc, click the seed field, type a number and
press Enter. The run regenerates and you're back at the start of map A.

To quit, press Esc and close the window.

## Tests

Headless tests for the maze generator and the Section 6.4 validation rules
(the objective is reachable, no dead-end wall is visible from the objective,
landing spots never count as dead ends). They sweep 200 run seeds, check that
the same seed gives the same maps, and check that the validator catches each
broken rule. From the project folder:

```
godot --headless --path . -s res://tests/test_maze_generator.gd
```

It prints each check and exits with the number of failures (0 means all
passed). It takes about 20 seconds.

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
| `scripts/player.gd`               | Walk and mouse look                          |
| `scripts/tuning.gd`               | Loads `config/tuning.cfg`                    |
| `scripts/maze/maze_map.gd`        | A map's grid: walls and tags                 |
| `scripts/maze/maze_generator.gd`  | Seeded generation (Section 6.4)              |
| `scripts/maze/maze_validator.gd`  | The validation rules                         |
| `scripts/maze/maze_builder.gd`    | Turns a map's grid into 3D geometry          |
| `scripts/maze/maze_params.gd`     | Maze settings from `config/tuning.cfg`       |
| `scripts/debug/debug_view.gd`     | The Tab debug view and seed field            |
| `tests/test_maze_generator.gd`    | Headless generator tests                     |
