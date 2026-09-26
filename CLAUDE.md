# Horror maze prototype

A gray-box prototype of a roguelite horror maze game. It exists to answer one
question: is the dead-end swap fun and readable? I make the design decisions;
you build the prototype.

## Sources of truth
- `docs/design.pdf` (v1) is the design record. Read only the sections a task
  needs: 2 (current design; wins over the rest of the PDF), 6.1 (roadmap),
  6.2 (prototype scope), 6.4 (technical notes), 6.5 (starting values),
  6.6 (playtest metrics).
- `docs/decisions.md` holds decisions made after v1 and overrides the PDF.
- Only items tagged DECIDED are decisions. Section 6.2 uses a few IDEA items
  (such as the fill-and-ceiling bar) as things to test: build those as 6.2
  describes them. Don't implement any other IDEA item unless
  `docs/decisions.md` adopts it.

## Scope
- Build only what Section 6.2 lists under "In the prototype". Nothing from
  "Left out for now": no final art, lighting or music, no second monster type,
  no items beyond bandages and hospital kits, no sun dials, shop or unlocks,
  no final map or lore, no menus, settings or saving.
- One roadmap stage per session. Do the stage I name, meet its "Done when"
  in Section 6.1, then stop. Don't start the next stage.
- No features, polish or refactors I didn't ask for. If the design doesn't
  cover something a stage needs, ask me rather than inventing it.

## Open decisions
- Every undecided number and rule goes in one config file (for example
  `config/tuning.cfg`), set to its Section 6.5 starting value, with a comment
  naming the decision it stands in for (D3, D5, D16, D17 and so on). Never
  hard-code these.
- The prototype has two maps, so a dead end always leads to the other one
  (D4 doesn't apply yet).
- Placeholder for D1 and D2, not a design decision: escaping the first
  collapse ends the run on a results screen showing the logged metrics.

## Tech
- Godot 4 (current stable release), GDScript. Keyboard and mouse only.
- Keep scenes and resources as text (`.tscn`, `.tres`). Gray-box geometry
  and flat colors only, no imported assets.
- All generation is seeded, and any run must be reproducible from its seed.
- As the stages reach them, add the debug overlay, seed field, "swap now" key
  and event log from Section 6.4. The event log records the Section 6.6
  metrics.
- Write headless tests for the maze generator's validation rules in
  Section 6.4. Run them before finishing if Godot can run in this
  environment; if it can't, tell me how to run them locally.

## Ending a session
- You can't see or play the game. End every session with what you built,
  how to run it, the controls, and a short list of what I should check when
  I play it.
- Commit in small steps with clear messages, and keep `README.md` current:
  what exists, how to run it, the controls.
