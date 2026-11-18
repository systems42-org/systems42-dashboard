#!/bin/sh
# Run every test script and say which ones failed. Exit 1 if any did.
#
#   sh tests/run-all.sh [python]      from the dashboard directory
#
# `./dashboard.sh test` runs this in the test stage of the Dockerfile. A plain
# `for` loop would report only its last script, so a failure in the middle
# would scroll past and the shell would still exit 0.
cd "$(dirname "$0")/.." || exit 2
PY="${1:-python3}"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
total=0
failed=""
for t in tests/test_*.py; do
  total=$((total + 1))
  if ! "$PY" "$t" >"$out" 2>&1; then
    failed="$failed $t"
    echo "✗ $t"
    sed 's/^/    /' "$out"
  fi
done
if [ -n "$failed" ]; then
  echo "✗ $(echo "$failed" | wc -w | tr -d ' ') of $total test scripts failed:"
  for t in $failed; do echo "    $t"; done
  exit 1
fi
echo "✓ $total test scripts passed."
