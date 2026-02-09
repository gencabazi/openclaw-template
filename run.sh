#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="runs/_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"

exec > >(tee -a "$LOG_FILE") 2>&1

on_err() {
  echo
  echo "🧨 RUN FAILED (exit=$?) at line $1"
  echo "Log: $LOG_FILE"
}
trap 'on_err $LINENO' ERR

echo "🧾 Log: $LOG_FILE"

usage() {
  cat <<'EOF'
Usage:
  ./run.sh [--dry-run] [--stack node|go|python] [--docker] "your app description"

Examples:
  ./run.sh --docker --stack node "Build a minimal Node API with /health (db check) and JSON 404."
  ./run.sh --dry-run --stack node "Plan an API design for ..."
EOF
}

DRY_RUN=0
STACK=""
DOCKER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --docker) DOCKER=1; shift ;;
    --stack)
      [[ $# -lt 2 ]] && { echo "Missing value for --stack"; usage; exit 1; }
      STACK="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done

[[ $# -ge 1 ]] || { usage; exit 1; }

if [[ -n "$STACK" ]]; then
  case "$STACK" in node|go|python) ;; *) echo "Invalid --stack '$STACK'"; exit 1 ;; esac
fi

MESSAGE="$*"
HINTS=""
[[ -n "$STACK" ]] && HINTS="${HINTS}\nPreferred implementation stack: ${STACK}."
[[ "$DOCKER" -eq 1 ]] && HINTS="${HINTS}\nDelivery constraint: include Dockerfile + docker-compose for local run."
[[ -n "$HINTS" ]] && MESSAGE="${MESSAGE}\n\n${HINTS}"

ts="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="runs/${ts}"
mkdir -p "$RUN_DIR"

MAX_ITERS=3
ITER=1

SUP_FEEDBACK_FILE="SUPERVISOR_FEEDBACK.md"
: > "$SUP_FEEDBACK_FILE"

VERIFY_FILE="$(pwd)/VERIFY.md"

# -----------------------
# helpers
# -----------------------
require_file() {
  [[ -f "$1" ]] || { echo "❌ Missing required file: $1"; exit 1; }
}

append_verify() {
  printf "%s\n" "$*" >> "$VERIFY_FILE"
}

curl_capture() {
  local url="$1"
  # keep this fairly strict: fail fast, but don’t abort whole script
  curl -sS -i --max-time 2 "$url" 2>&1 || true
}

wait_for_health() {
  local url="$1"
  local tries="${2:-30}"
  for _ in $(seq 1 "$tries"); do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_verify_docker() {
  local appdir="generated/app"
  local port="3000"
  local health_url="http://127.0.0.1:${port}/health"
  local nope_url="http://127.0.0.1:${port}/nope"

  : > "$VERIFY_FILE"
  append_verify "mode: docker"
  append_verify "started_at: $(date -Is)"
  append_verify ""

  [[ -f "${appdir}/docker-compose.yml" ]] || { append_verify "result: fail"; append_verify "reason: missing docker-compose.yml"; return 1; }

  pushd "$appdir" >/dev/null

  append_verify "## Setup"
  append_verify "docker compose up -d --build"
  docker compose up -d --build >> "$VERIFY_FILE" 2>&1 || true
  append_verify ""

  # wait for api to come up
  if ! wait_for_health "$health_url" 30; then
    append_verify "## ERROR"
    append_verify "health endpoint not reachable after waiting"
    docker compose logs --no-color >> "$VERIFY_FILE" 2>&1 || true
    docker compose down -v >> "$VERIFY_FILE" 2>&1 || true
    popd >/dev/null
    append_verify ""
    append_verify "result: fail"
    return 1
  fi

  append_verify "## /health (DB up) — expect ok"
  curl_capture "$health_url" >> "$VERIFY_FILE"
  append_verify ""

  append_verify "## Stop DB"
  append_verify "docker compose stop db"
  docker compose stop db >> "$VERIFY_FILE" 2>&1 || true
  append_verify ""

  append_verify "## /health (DB down) — expect degraded"
  curl_capture "$health_url" >> "$VERIFY_FILE"
  append_verify ""

  append_verify "## /nope (404 JSON)"
  curl_capture "$nope_url" >> "$VERIFY_FILE"
  append_verify ""

  # cleanup
  append_verify "## Cleanup"
  append_verify "docker compose down -v"
  docker compose down -v >> "$VERIFY_FILE" 2>&1 || true
  popd >/dev/null

  # decide pass/fail based on evidence
  if grep -qE "HTTP/.* 200" "$VERIFY_FILE" \
    && grep -qE "\"status\"[[:space:]]*:[[:space:]]*\"ok\"" "$VERIFY_FILE" \
    && grep -qE "\"status\"[[:space:]]*:[[:space:]]*\"degraded\"" "$VERIFY_FILE" \
    && grep -qE "HTTP/.* 404" "$VERIFY_FILE"; then
    append_verify "result: pass"
    return 0
  fi

  append_verify "result: fail"
  return 1
}

# -----------------------
# main loop
# -----------------------
while true; do
  echo
  echo "=============================="
  echo "🧭 ITERATION $ITER / $MAX_ITERS"
  echo "=============================="

  echo "▶️ Planner"
  if [[ -s "$SUP_FEEDBACK_FILE" ]]; then
    openclaw agent --agent planner --message "$MESSAGE

Apply the following supervisor feedback strictly (latest at bottom):
$(tail -n 200 "$SUP_FEEDBACK_FILE")"
  else
    openclaw agent --agent planner --message "$MESSAGE"
  fi

  echo "▶️ Reviewer"
  openclaw agent --agent reviewer --message "Review PLAN.md and produce REVIEW.md."

  if grep -q "VERDICT: REQUEST_CHANGES" REVIEW.md; then
    echo "🔁 Planner (revision)"
    openclaw agent --agent planner --message "Revise PLAN.md based on REVIEW.md. Make the plan implementable without further questions."
    echo "▶️ Reviewer (re-check)"
    openclaw agent --agent reviewer --message "Review the updated PLAN.md and update REVIEW.md."
  fi

  if ! grep -q "VERDICT: APPROVE" REVIEW.md; then
    echo "❌ Plan not approved. Snapshotting and stopping."
    cp -f PLAN.md REVIEW.md "$RUN_DIR/" 2>/dev/null || true
    exit 1
  fi

  require_file PLAN.md
  require_file REVIEW.md
  grep -q "^implementation_stack:" PLAN.md || { echo "❌ PLAN.md missing implementation_stack"; exit 1; }
  grep -q "^delivery:" PLAN.md || { echo "❌ PLAN.md missing delivery"; exit 1; }

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "✅ Dry-run complete. Snapshotting plan artifacts."
    cp -f PLAN.md REVIEW.md "$RUN_DIR/" 2>/dev/null || true
    echo "Snapshot: $RUN_DIR/"
    echo "Log: $LOG_FILE"
    exit 0
  fi

  echo "▶️ Implementer"
  rm -rf generated/app 2>/dev/null || true
  mkdir -p generated

  IMPLEMENTER_MSG="STRICT:
You MUST implement the CURRENT plan found at: ./PLAN.md
Ignore any prior runs and any existing code.
Before writing, delete and recreate ./generated/app from scratch.
Output MUST match the plan's endpoints and constraints.
You MUST overwrite root IMPLEMENTATION.md with: summary, file tree, run steps, curl verification.
Do NOT touch index.html."

  [[ -n "$STACK" ]] && IMPLEMENTER_MSG="${IMPLEMENTER_MSG} Use ${STACK} as the implementation stack."
  [[ "$DOCKER" -eq 1 ]] && IMPLEMENTER_MSG="${IMPLEMENTER_MSG} Include Dockerfile and docker-compose.yml to run the service + Postgres."

  if [[ -s "$SUP_FEEDBACK_FILE" ]]; then
    IMPLEMENTER_MSG="${IMPLEMENTER_MSG}

Apply the following supervisor feedback strictly (latest at bottom):
$(tail -n 200 "$SUP_FEEDBACK_FILE")"
  fi

  openclaw agent --agent implementer --message "$IMPLEMENTER_MSG"

  [[ -d generated/app ]] || { echo "❌ generated/app missing after implementer"; exit 1; }
  rm -rf generated/app/node_modules 2>/dev/null || true
  [[ -f generated/app/IMPLEMENTATION.md ]] && cp -f generated/app/IMPLEMENTATION.md IMPLEMENTATION.md

  echo "▶️ Verify (smoke test)"
  delivery="$(grep -E "^delivery:" PLAN.md | awk '{print $2}')"

  VERIFY_OK=1
  if [[ "$delivery" == "docker" ]]; then
    run_verify_docker || VERIFY_OK=0
  else
    : > "$VERIFY_FILE"
    append_verify "mode: local"
    append_verify "result: skip"
    append_verify "note: local verify not implemented"
  fi

  [[ "$VERIFY_OK" -eq 1 ]] || echo "⚠️ Verify failed; continuing to supervisor so it can decide."

  echo "▶️ Supervisor"
  openclaw agent --agent supervisor --message "Evaluate PLAN.md, REVIEW.md, IMPLEMENTATION.md, VERIFY.md, and generated/app contents. Produce DECISION.md."

  # Append decision into feedback file for next iteration if needed
  {
    echo
    echo "## Iteration $ITER decision"
    cat DECISION.md
  } >> "$SUP_FEEDBACK_FILE"

  echo
  echo "---- Supervisor Decision ----"
  sed -n '1,220p' DECISION.md || true
  echo "----------------------------"

  if grep -q "^STATUS: COMPLETE" DECISION.md; then
    echo "✅ Supervisor marked COMPLETE."
    break
  fi

  if grep -q "^STATUS: BLOCKED" DECISION.md; then
    echo "🛑 Supervisor marked BLOCKED."
    break
  fi

  if [[ "$ITER" -ge "$MAX_ITERS" ]]; then
    echo "🛑 Reached max iterations ($MAX_ITERS). Stopping."
    break
  fi

  ITER=$((ITER + 1))
done

# Snapshot artifacts + app
cp -f PLAN.md REVIEW.md IMPLEMENTATION.md DECISION.md "$SUP_FEEDBACK_FILE" "$RUN_DIR/" 2>/dev/null || true
mkdir -p "$RUN_DIR/generated"
cp -a generated/app "$RUN_DIR/generated/" 2>/dev/null || true

echo
echo "=============================="
echo "✅ RUN FINISHED"
echo "Snapshot: $RUN_DIR/"
echo "Log: $LOG_FILE"
echo "=============================="
