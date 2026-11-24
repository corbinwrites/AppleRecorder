#!/usr/bin/env bash
# Run one build step with a fresh agent session, then verify. Stops on red.
#
#   AGENT_CMD='claude -p' scripts/run-step.sh P1
#   AGENT_CMD='aider --yes --message-file "$PROMPT_FILE"' scripts/run-step.sh P2 4
#   AGENT_CMD='ollama run qwen3-coder' scripts/run-step.sh P3       # prompt arrives on stdin
#
# The prompt is written to $PROMPT_FILE and also piped to AGENT_CMD's stdin. AGENT_CMD runs with eval.
# Env: PUSH=1 to push main after a green step. MAX attempts = 2nd arg (default 3).
set -u
STEP="${1:?step id, e.g. P1}"; MAX="${2:-3}"
cd "$(git rev-parse --show-toplevel)" || exit 1
TASK="docs/tasks/$STEP.md"; [ -f "$TASK" ] || { echo "no $TASK (run: make tasks)"; exit 2; }
: "${AGENT_CMD:?set AGENT_CMD, see the header of this script}"
VERIFY="$(grep -m1 '^VERIFY: ' "$TASK" | sed 's/^VERIFY: //')"
NOTE="$(grep -m1 '^\*\*Note:\*\*' "$TASK" || true)"
[ -n "$NOTE" ] && echo "$NOTE"
export PROMPT_FILE="$(mktemp -t ar-prompt.XXXXXX)"; LOG="/tmp/ar-step-$STEP.log"
BASE="You are building one step of the Apple Recorder app. Read AGENTS.md, then docs/tasks/$STEP.md. Do only that step. Run the VERIFY command from the task file until it passes, update PROGRESS.md, commit as '$STEP: <what>', then stop. If blocked, write BLOCKERS.md and stop."
for n in $(seq 1 "$MAX"); do
  echo "== $STEP attempt $n/$MAX"
  if [ "$n" -eq 1 ]; then echo "$BASE" > "$PROMPT_FILE"
  else { echo "$BASE"; echo; echo "Your previous attempt failed verification. Last 80 lines of output:"; tail -80 "$LOG"; } > "$PROMPT_FILE"; fi
  eval "$AGENT_CMD" < "$PROMPT_FILE"
  { echo "--- protect-tests"; ./scripts/protect-tests.sh; echo "--- VERIFY: $VERIFY"; bash -c "$VERIFY"; } >"$LOG" 2>&1
  RC=$?
  if grep -q '^FAIL protect-tests' "$LOG"; then echo "STOP: the agent changed spec tests. Revert them: git checkout spec-v1 -- Packages/*/Tests"; tail -20 "$LOG"; exit 3; fi
  if [ "$RC" -eq 0 ]; then
    echo "GREEN: $STEP"
    git status --short | grep -q . && echo "WARNING: uncommitted changes remain (the agent should have committed)."
    [ "${PUSH:-0}" = "1" ] && git pull --rebase origin main && git push origin main
    exit 0
  fi
  echo "RED: see $LOG"
done
echo "STOP: $STEP still red after $MAX attempts. See $LOG and BLOCKERS.md."; exit 1
