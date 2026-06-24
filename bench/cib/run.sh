#!/usr/bin/env bash
# CIB orchestrator — sweep occupancy buckets × trials, then write results.jsonl
# and a self-contained cib_report.html into --out.
#
#   bash run.sh --mock --buckets 10,20,30,40,50,60,70,80 --trials 5 --out ./report
#
# --mock is a fully offline demo (no API key, no deps beyond the stdlib). A real
# run needs ANTHROPIC_API_KEY and `pip install -r requirements.txt`.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/run.py" "$@"
