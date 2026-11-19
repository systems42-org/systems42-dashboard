#!/bin/sh
# Run every test script and say which ones failed or skipped. Exit 1 if any
# failed.
#
#   sh tests/run-all.sh [python]      from the dashboard directory
#
# `./dashboard.sh test` runs this in the test stage of the Dockerfile. A plain
# `for` loop would report only its last script, so a failure in the middle
# would scroll past and the shell would still exit 0.
#
# A script that cannot run at all here (a missing tool) exits 77, the automake
# convention for "skipped". The summary counts and names those scripts, so a
# skip does not pass as a pass.
cd "$(dirname "$0")/.." || exit 2
PY="${1:-python3}"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
total=0
failed=""
skipped=""
for t in tests/test_*.py; do
  total=$((total + 1))
  "$PY" "$t" >"$out" 2>&1
  rc=$?
  if [ "$rc" -eq 77 ]; then
    skipped="$skipped $t"
  elif [ "$rc" -ne 0 ]; then
    failed="$failed $t"
    echo "✗ $t"
    sed 's/^/    /' "$out"
  fi
done
nfailed=$(echo "$failed" | wc -w | tr -d ' ')
nskipped=$(echo "$skipped" | wc -w | tr -d ' ')
npassed=$((total - nfailed - nskipped))
summary="$total test scripts: $npassed passed"
[ "$nfailed" -gt 0 ] && summary="$summary, $nfailed failed"
[ "$nskipped" -gt 0 ] && summary="$summary, $nskipped skipped"
if [ "$nfailed" -gt 0 ]; then mark="✗"; else mark="✓"; fi
echo "$mark $summary."
for t in $failed; do echo "    failed:  $t"; done
for t in $skipped; do echo "    skipped: $t"; done
[ "$nfailed" -eq 0 ]
