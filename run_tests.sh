#!/usr/bin/env bash
# Run the RailBuilder headless test suite.
set -uo pipefail
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/.local/bin/godot4}"

# A GDScript runtime error aborts the test method without recording an assertion
# failure, so the runner alone can report a false ALL GREEN. Treat any script
# error in the output as a failed run.
out="$("$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1)"
rc=$?
echo "$out"
if grep -q "SCRIPT ERROR" <<< "$out"; then
    echo "RED: script errors detected (see above)"
    exit 1
fi
exit $rc
