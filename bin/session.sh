#!/usr/bin/env sh
# session.sh — Outer session runner (P2, OPTIONAL; not required for Mini core).
#
# Forces the matching session-* playbook into a FRESH context for unattended
# or scripted runs: reads the `path:` line from `bin/harness.sh status`, picks
# `session-init` or `session-coding`, and emits that skill's body verbatim
# (frontmatter stripped) under a short generic wrapper. The skill files are
# the single source of truth — this runner never forks their text.
#
# It is deliberately host-agnostic: no vendor CLI, no host session-start hook
# APIs, no runtime. The interactive path (routing gate + skills) remains
# authoritative; this is a convenience wrapper on top of the landed assets.
#
# Usage:
#   bin/session.sh                 print the first user message to stdout
#   bin/session.sh -- <cmd...>     exec <cmd...> with the message as its final
#                                  argument (e.g. your host CLI's prompt flag)
#                                  — a fresh process per invocation, so every
#                                  session starts from a clean context.
#
# Env: HARNESS_ROOT  project root (default: parent of this script's dir)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${HARNESS_ROOT:-$(cd "$HERE/.." && pwd)}"

# 1. session path from the workboard (file truth; offline; default init)
path="$(HARNESS_NO_NET=1 bash "$HERE/harness.sh" status 2>/dev/null \
        | awk -F': *' '/^path:/{print $2; exit}')"
case "$path" in
  coding) skill="session-coding" ;;
  *)      skill="session-init" ;;
esac

# 2. the skill body — installed layout first, source layout second
SKILL_MD=""
for f in "$ROOT/.claude/skills/$skill/SKILL.md" "$ROOT/skills/$skill/SKILL.md"; do
  [ -f "$f" ] && { SKILL_MD="$f"; break; }
done
[ -n "$SKILL_MD" ] || { echo "session.sh: skill not found: $skill" >&2; exit 1; }

# 3. body verbatim, YAML frontmatter (first --- block) stripped — presentation
#    only; the directive text is never edited here
body="$(awk '
  NR==1 && $0 == "---" { fm=1; next }
  fm && $0 == "---"    { fm=0; next }
  !fm
' "$SKILL_MD")"

# 4. short generic wrapper + the body = the first user message
msg="$(cat <<EOF
You are starting a fresh, unattended harness-mini session.
Session path: $skill (selected by bin/harness.sh status from file truth).
The skill below is your directive for this session — follow it exactly; it
tells you how to orient, what you may write, and how to end the session
cleanly.

$body
EOF
)"

# 5. deliver: stdout by default, or exec a host command with the message as
#    its final argument (each invocation = a new process = fresh context)
if [ "${1:-}" = "--" ]; then
  shift
  [ $# -gt 0 ] || { echo "session.sh: -- needs a command" >&2; exit 64; }
  exec "$@" "$msg"
fi
printf '%s\n' "$msg"
exit 0
