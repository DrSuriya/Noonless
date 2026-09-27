# Horror maze prototype

A gray-box prototype of a roguelite horror maze game. It exists to answer one
question: is the dead-end swap fun and readable?

- `docs/design.pdf` is the design record (v1).
- `docs/decisions.md` logs decisions made since, and overrides the PDF.
- `CLAUDE.md` is the brief for building the prototype.

## What exists

Roadmap Stage 1 (engine spike) from Section 6.1 of the design:

- A Godot 4 project with a first-person controller: walk and mouse look.
- A gray-box test room (`scenes/test_room.tscn`): 20 × 20 m with 3 m walls,
  two pillars, two boxes and a partition that makes a hallway along one side.
- `config/tuning.cfg`: every starting value from Section 6.5, each with a
  comment naming the decision it stands in for. Only the `[player]` values
  (walk speed and mouse sensitivity) are used so far; those two aren't from
  the design.
- `docs/decisions.md`: the decision log, empty so far.

There's no maze, swap, bar, objective or monster yet (Stages 2 to 6).

## How to run

1. Install [Godot 4.7](https://godotengine.org/download) (the standard build;
   .NET isn't needed). Built and tested with 4.7.2 stable.
2. In the Godot project manager, choose **Import** and pick `project.godot`
   in this folder.
3. Press **F5** (Run Project). The test room is the main scene.

From a terminal: `godot --path /path/to/this/folder`.

## Controls

| Input      | Action                             |
|------------|------------------------------------|
| W A S D    | Walk                               |
| Mouse      | Look                               |
| Esc        | Free the mouse cursor              |
| Left click | Capture the mouse cursor again     |

To quit, press Esc and close the window.

## Tuning

Edit `config/tuning.cfg` and run again; no code changes needed. The `Tuning`
autoload (`scripts/tuning.gd`) reads the file once at startup, and a missing
key is reported as an error rather than replaced by a default.

## Layout

| Path                     | What it is                                   |
|--------------------------|----------------------------------------------|
| `project.godot`          | Project settings, input map, autoloads       |
| `config/tuning.cfg`      | Every undecided number and rule              |
| `scenes/test_room.tscn`  | Gray-box test room (main scene)              |
| `scenes/player.tscn`     | First-person player                          |
| `scripts/player.gd`      | Walk and mouse look                          |
| `scripts/tuning.gd`      | Loads `config/tuning.cfg`                    |
