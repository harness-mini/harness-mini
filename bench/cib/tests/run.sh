#!/usr/bin/env bash
# CIB island test runner — Python unit tests + the offline smoke test.
# Kept separate from the zero-dep core tests/run.sh (this one needs python3).
# One entry point so a grader/CI can run the whole island with a single
# already-permitted `bash bench/cib/tests/run.sh`.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"   # bench/cib
fail=0

echo "== bench/cib python unit tests =="
( cd "$DIR" && python3 -m unittest discover -s tests -p 'test_*.py' ) || fail=1

echo "== bench/cib offline smoke =="
bash "$DIR/tests/test_run_smoke.sh" || fail=1

if [ "$fail" = "0" ]; then echo "BENCH OK"; else echo "BENCH FAILED"; fi
exit "$fail"
