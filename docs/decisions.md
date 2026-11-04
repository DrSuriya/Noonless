# Decision log

Decisions made after `docs/design.pdf` (v1, September 20, 2026). Anything
recorded here overrides the PDF. Only decisions belong here, not ideas or
suggestions. The table follows Appendix C of the PDF.

When a decision changes a number or rule, also update its value and comment
in `config/tuning.cfg`.

| Date | Decision (ID) | Choice | Notes |
|------|---------------|--------|-------|
| 2026-09-27 | Objective placement (no ID) | Middle of a random room from the farther half of rooms, by walking distance from the start | Holds on the finished map, after braiding. Stage 2. |
| 2026-09-27 | Rooms per map (no ID) | 6 to 8 rooms, 2×2 to 3×3 cells | The numbers are placeholders in `config/tuning.cfg`. Stage 2. |
| 2026-09-27 | Braiding distance (no ID) | Straight-line distance to the objective | Dead-end survival scales linearly from 80% at the objective to 20% at the farthest cell (Section 6.5 values). Stage 2. |
| 2026-09-27 | Landing-spot placement (no ID) | Random, in the half of the map farther from the objective, kept apart | One-cell alcoves. Stage 2. |
| 2026-11-03 | Minimum dead-end branch length (no ID) | Keep 3 cells, the Section 6.5 value | Leaves about 4 dead ends per map (about 8 with 2 cells, 17 with 1). Stage 3. |
| 2026-11-03 | Blended wall look (no ID) | Vertical panels across the alcove's back wall, stepping from the origin map's color to this map's | The panel count is a placeholder in `config/tuning.cfg`. Stage 3. |
| 2026-11-03 | Trigger facing angle (no ID) | Measured on the full look direction; looking up or down counts | Staring at a dead end's floor or ceiling doesn't fire the trigger. Stage 3. |
