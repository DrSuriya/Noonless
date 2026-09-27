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
