# Playtest 1 (roadmap Stage 7)

The prototype exists to answer one question: **is the dead-end swap fun and
readable?** This playtest answers it. Stage 7 is done when the
keep / change / cut list at the end of this page is written.

This guide follows Section 6.6 of `docs/design.pdf`. Where it adds something
(a session length, a controls card), it says so.

## Before the session

1. In `config/tuning.cfg`, set `debug_keys_enabled=false` under
   `[playtest]`. This turns off the debug overlay (Tab) and the swap-now key
   (N), so a stray key press can't change what testers see or skew the
   metrics.
2. Clear old logs, or note which files are new. The event logs are in:
   - Linux: `~/.local/share/godot/app_userdata/Horror maze prototype/event_logs/`
   - Windows: `%APPDATA%\Godot\app_userdata\Horror maze prototype\event_logs\`
   - macOS: `~/Library/Application Support/Godot/app_userdata/Horror maze prototype/event_logs/`
3. Run the game once yourself to check it starts, and close it.
4. Have sound on: the monsters' footsteps are a cue.
5. Decide how long each person plays. The design doesn't say; 20 to 30
   minutes, or until they've finished three runs, is a suggestion.

## Who and how (Section 6.6)

- Three to five people, ideally including someone who doesn't usually play
  horror.
- Explain the controls and nothing else. Don't explain dead ends, landing
  spots, the objective, the bar or the monsters.
- Watch in person or record the screen, and stay quiet while they play.

## Controls card (read this out, nothing more)

| Input | Action |
|---|---|
| W A S D | Walk |
| Mouse | Look |
| Shift | Sprint |
| Ctrl (hold) | Crouch |
| E | Use / activate |
| 1 2 3 | Use the item in that slot |
| Esc | Free the mouse (click to capture it again) |
| Enter (after a run ends) | Start a new run |

## Watch for (Section 6.6)

Tick these off per tester on the note sheet below.

- Do they notice the environmental tells (the floor darkening along a dead
  end)?
- How many swaps does it take before they understand that dead ends lead
  elsewhere?
- Do they ever swap by accident, or feel cheated by a swap?
- Do they start using dead ends on purpose to escape?
- Does the collapse feel like a climax?
- Do they read the blended walls as "this is where I came from"?
- Do they hide rather than explore?

## Ask afterward (Section 6.6)

- When were you most afraid, and when did you feel safe?
- Did any swap feel unfair? Which one?
- What did the blended walls mean to you?
- What would you do differently on your next run?

One extra question, not from the design: *Can you explain what happens at a
dead end?* (It checks the first pass criterion below.)

## Logged automatically (Section 6.6)

Every run writes a log file. Together they cover:

- swaps per minute, split into swaps during a chase and swaps without one;
- quick swaps: no chase, within 5 s of entering the dead end's branch (the
  proxy for accidents);
- time to reach each objective, and how many times the player was ejected
  near it;
- rush length and the toll paid;
- deaths by cause;
- time spent standing still;
- for each swap during a chase, how far behind the nearest chasing monster
  was (for counting narrow escapes).

To summarize a playtest, copy every tester's `.jsonl` files into one folder
and run, from the project folder:

```
godot --headless --path . -s res://tools/summarize_logs.gd -- /path/to/that/folder
```

With no folder, it reads this computer's own logs. It prints each run and
then totals, including the two pass criteria the logs can speak to. A
"narrow escape" in the report is a swap during a chase with the monster
within 5 m, which is a reading aid rather than a design value.

## The prototype passes if (Section 6.6)

- [ ] Players can explain the dead-end rule in their own words.
- [ ] Most sessions produce at least one narrow dead-end escape.
- [ ] Accidental swaps are rare.
- [ ] The turn-around reveal still gets a reaction after ten or more swaps.

## Things testers may notice that are known

- Escaping the first collapse ends the run on the results screen. That's
  the placeholder for D1 and D2 (what the last map does, what the final map
  is), not the intended ending.
- Everything is gray-box: flat colors, no art, lighting or music.
- The choices in `docs/provisional_choices.md` (speeds, monster sight,
  item counts and so on) are untested guesses. Note anything that feels off;
  most are one line in `config/tuning.cfg`.

## Note sheet (copy one per tester)

```
Tester:                     Plays horror? yes / no      Date:
Runs played:                Session length:

Noticed the tells?                         when / how:
Swaps before getting the rule:
Accidental or unfair swaps (when, which):
Used dead ends on purpose to escape?       first time at:
Collapse felt like a climax?
Read the blended walls as "where I came from"?
Hid rather than explored?
Reaction to the turn-around after 10+ swaps:

Most afraid when:
Felt safe when:
Unfair swap:
Blended walls meant:
Next run they'd:
Could explain the dead-end rule? (their words):

Other notes:
```

## Keep / change / cut

Stage 7 is done when this list is written. Fill it in after all sessions,
from the notes, the summary report and the pass criteria. Record any
decisions it leads to in `docs/decisions.md`.

| Keep | Change | Cut |
|---|---|---|
| | | |
