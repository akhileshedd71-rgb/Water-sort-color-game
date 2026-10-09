# Testing Prism

Use **Godot 4.6.3 standard** and **Python 3**. Run commands from the repository root. No Python packages are required.

## Automated checks

Import resources once after cloning so fonts, SVGs, and global script classes are available:

```sh
godot --headless --path . --editor --import --quit
```

Then run the suites:

```sh
godot --headless --path . --script tests/test_puzzles.gd
godot --headless --path . --script tests/test_save.gd
godot --headless --path . --script tests/test_game.gd
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

`test_puzzles.gd` checks move legality, maximal transfers, completion rules, all 240 campaign solution certificates, deterministic daily/seeded remixes, and the hint solver. `test_game.gd` exercises the game scene and state integration. `test_levels.py` independently verifies campaign size, chapter/variant coverage, board uniqueness, capacities, color inventory, and every recorded solution with its own pour implementation.

`test_save.gd` verifies reward rules, purchases, round trips, corrupted-file recovery, and preserving campaign progress while playing side modes. Both save-writing suites use unique temporary save filenames and clean them up, leaving normal player progress alone. On Linux/macOS, `bash tools/check.sh` runs all suites with isolated writable XDG directories.

Treat script errors, failed assertions, or nonzero exits as failures. Headless checks validate logic and scene behavior; they do not establish visual quality, audible sound quality, real touchscreen behavior, or device performance.

On Linux environments where the normal user directories are read-only, give Godot writable XDG directories before running these commands:

```sh
export XDG_DATA_HOME=/tmp/prism-test/data
export XDG_CACHE_HOME=/tmp/prism-test/cache
export XDG_CONFIG_HOME=/tmp/prism-test/config
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
```

These settings also isolate the test session's user data from ordinary Linux play sessions.

## Manual play check

1. Launch with F5. Verify the home illustration, readable text, button hover/focus/pressed states, and sound.
2. Finish the opening puzzle. Confirm matching-color rules, full-bottle rejection, smooth pour travel, a completion celebration, and unlocking the next level.
3. Use Undo, Hint, Restart, and the free helper. Confirm that undo restores the previous board and that restart requests confirmation.
4. Leave a campaign puzzle partway through, close the game, reopen, and continue. Verify board, move count, and undo history.
5. Open the modes screen. Try Mystery, Sky high, Tight space, daily, and endless play. Mystery must conceal lower colors while its top block remains readable.
6. Enable Color labels and Gentle motion. Verify numbered visible colors, unchanged mystery concealment, short pours, and still scenery. Disable sound and confirm cues stop.
7. Earn sparkles, purchase a studio item, select it, and reopen the game. Confirm the purchase and selection persist without charging again.
8. Resize between portrait and desktop windows. Check the largest boards, the studio, settings, dialogs, and keyboard focus for overlap or clipping. Repeat with touch on a physical device.

## Level regeneration

The campaign is already bundled; do not regenerate it just to play or export. To intentionally rebuild its data:

```sh
python3 tools/generate_levels.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script tests/test_puzzles.gd
```

Regeneration overwrites `data/levels.json`. Review the diff, rerun the game integration suite, and play representative early, late, and variant levels before committing a changed campaign. A legal solution proves solvability, not enjoyable pacing or optimal difficulty.

## Export checks

Install export templates matching the editor. Include `*.json` in the preset's non-resource export filter. Verify a packaged build opens its campaign with no missing-resource errors and can save in its user data directory.

Windows, Linux, and Android need separate platform testing. Android export additionally requires Godot's documented SDK/JDK setup and signing configuration; test a debug APK on a physical device before considering a store release. An editor run or headless Linux pass is not an Android validation.
