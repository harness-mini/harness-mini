#!/usr/bin/env bash
# CIB issue #6 — end-to-end smoke test of the orchestrator in offline mock mode.
# Hermetic: no network, no deps. Proves build→run→score→analyze→report plumbing.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"   # bench/cib
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
pass() { echo "  ok   $1"; }
bad()  { echo "  FAIL $1"; fail=1; }

bash "$DIR/run.sh" --mock --buckets 10,40,70 --trials 2 --out "$TMP" >/dev/null 2>&1 \
  || bad "run.sh --mock exited non-zero"

lines=$(wc -l < "$TMP/results.jsonl" 2>/dev/null | tr -d ' ')
[ "$lines" = "6" ] && pass "results.jsonl has 6 trials" || bad "results.jsonl lines=$lines (want 6)"

[ -f "$TMP/cib_report.html" ] && pass "cib_report.html written" || bad "cib_report.html missing"

if grep -qiE 'src="http|cdn' "$TMP/cib_report.html" 2>/dev/null; then
  bad "report references an external resource (not self-contained)"
else
  pass "report is self-contained"
fi

[ "$fail" = "0" ] && echo "smoke OK" || { echo "smoke FAILED"; exit 1; }
