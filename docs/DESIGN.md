# Design notes

## Feel and presentation

Prism is a relaxed puzzle game with a playful candy-world identity: pink, aqua, purple, and warm yellow against quiet violet scenery. Liquid colors lead the composition. Rounded buttons have bright upper edges and dimensional pressed states; Nunito provides readable, friendly typography.

Pip is an original aqua droplet with a tiny yellow star companion. The backdrop, mascot, glass, icons, and particles are vector or procedural artwork. This keeps the project self-contained and lets it scale between portrait and desktop windows. Sound effects are short original harmonic plucks synthesized into PCM samples at startup.

## Rules and progression

Each tube is an array of integer color IDs, stored **bottom to top**. `PuzzleRules` owns the game rules independently of rendering. A legal move requires a nonempty source, a different destination with free capacity, and an empty destination or matching top color. A move transfers the entire contiguous top run up to available capacity. A solved board contains at least one occupied tube, and every occupied tube is full and monochrome.

The campaign has six chapters of 40 levels. Color count, bottle capacity, hidden information, and available working space change the challenge:

| Variant | Behavior |
| --- | --- |
| `classic` | Visible colors; normally four-layer bottles and two empty helpers |
| `mist` / Mystery | Only the top contiguous color block is visible; lower colors appear as they are uncovered |
| `tall` / Sky high | Five-layer bottles |
| `tight` / Tight space | One empty helper at the start |

The mixed final chapter includes three-layer puzzles. An optional free extra helper, unlimited undo, and restart allow recovery without a timer or currency penalty. Move counts are feedback and personal bests, not a failure condition.

## Generated levels and solvability

`tools/generate_levels.py` produces `data/levels.json` deterministically. Levels are generated, with a simple explicit opening tutorial; they are not individually handcrafted. Every bundled board includes a `solution` sequence. The generator normalizes boards and rejects duplicates; independent Python and Godot checks replay the certificates using maximal legal pours and verify the winning state.

A solution certificate proves that a puzzle can be solved. It does not prove that the recorded solution is shortest or that the assigned difficulty label matches every player's experience. Future difficulty tuning should include playtesting.

Daily and endless puzzles reuse certified campaign boards with shuffled tube positions and color IDs. Their solution steps are remapped alongside the board. Daily seeds derive from the **UTC date**, giving the same puzzle for a date without a backend; endless mode uses a fresh random seed. These remixes add replay value but are not newly generated puzzle topologies.

Hints use the stored certificate while the player follows that path. After a different move, a bounded best-first search looks for a proven route to a win. When its budget expires or no route is found, it returns no hint and the UI suggests undo or a helper. It never presents an unverified move as a solution step.

## Liquid and feedback

The authoritative board changes by discrete units. During a pour, the source's visible volume decreases while the destination's increases by the same amount. Bottle rendering clips colored polygons to the glass and locates fill surfaces by polygon area. Tilting changes the surface slope; highlights, menisci, a curved stream, and droplets provide the liquid impression.

This is stylized, volume-conserving 2D animation. It does not model fluid pressure, turbulent mixing, real splashing, or computational fluid dynamics. Color layers remain distinct because clear puzzle state matters more than physical realism.

Completed bottles glow and sparkle; wins add a wider celebration. Chapter completions receive distinct wording. Gentle motion shortens transfers, disables travel/tilt animations and ambient drift, and suppresses particle bursts. Numbered color labels provide an additional cue without changing the rules or revealing hidden Mystery colors.

## Rewards and persistence

A first campaign completion awards 15 sparkles, or 35 on every tenth level. A first daily completion awards 30. Replaying a completed campaign level can improve its best move count but does not repeatedly award currency. Endless and variant practice do not award campaign rewards.

The first scenery, glass, and palette options are available immediately. Each category's alternatives cost 90 and 180 sparkles. There are no ads, payments, network calls, or third-party SDKs.

`SaveStore` writes `user://prism_save.json` through a temporary file and keeps a `.bak` fallback. It persists campaign unlocks, completed levels, preferences, purchases, daily completions, and the current campaign board with undo history. Daily/endless boards are not resumed after closing. Saves remain local to the device; there is no cloud synchronization.

## Source map

| File | Responsibility |
| --- | --- |
| `scenes/main.tscn`, `scripts/main.gd` | Responsive screens, input, game flow, pour choreography, settings, studio |
| `scripts/puzzle_rules.gd` | Pure legal-move logic, win checks, bounded hint search |
| `scripts/level_catalog.gd` | Bundled campaign, daily seed, certified remixes |
| `scripts/bottle_view.gd` | Glass shapes, volume clipping, labels, completion feedback |
| `scripts/pour_overlay.gd` | Streams, splashes, confetti |
| `scripts/ambient_backdrop.gd` | Three illustrated background themes |
| `scripts/droplet_mascot.gd` | Pip and star companion |
| `scripts/sound_bank.gd` | Cached synthesized sound cues |
| `scripts/save_store.gd` | Local persistence, progression, cosmetic economy |
| `tools/generate_levels.py` | Deterministic campaign generation |
| `tests/` | Rules, certificates, state integration, and data invariants |

Use Godot's Compatibility renderer and standard GDScript. Python tooling has no third-party runtime dependencies. See [Testing](TESTING.md) before changing rules or regenerating levels.
