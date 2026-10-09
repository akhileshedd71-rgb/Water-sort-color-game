#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_test_root="$(mktemp -d /tmp/prism-check.XXXXXX)"
trap 'rm -rf "$task_test_root"' EXIT
export XDG_DATA_HOME="$task_test_root/data"
export XDG_CACHE_HOME="$task_test_root/cache"
export XDG_CONFIG_HOME="$task_test_root/config"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
godot --headless --path . --editor --import --quit
python3 -m unittest discover -s tests -p 'test_*.py' -v
godot --headless --path . --script tests/test_puzzles.gd
godot --headless --path . --script tests/test_save.gd
godot --headless --path . --script tests/test_game.gd
