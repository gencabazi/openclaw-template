# OpenClaw Workflow Template

This repository is a reusable OpenClaw workflow that automates:

Plan → Review → Implement → Verify → Decide

It is designed for backend tasks where you want deterministic,
auditable AI output with verification and supervisor approval.

---

## How to run

From the project root:

./run.sh --docker --stack node "Build a minimal Node API with GET /health (db check) and JSON 404."

Examples:

./run.sh --docker --stack node "Build a Node API with Postgres health check"
./run.sh --stack go "Build a Go service with /health endpoint"
./run.sh --dry-run --stack node "Plan an API for inventory management"

---

## What this produces

After a successful run, the following files are created or updated:

- PLAN.md  
- REVIEW.md  
- IMPLEMENTATION.md  
- VERIFY.md  
- DECISION.md  

The generated application is placed in:

generated/app/

Each run is snapshotted under:

runs/<timestamp>/

---

## Verification behavior (docker runs)

When delivery is set to `docker`, verification performs:

1. docker compose up -d --build
2. GET /health while DB is up
   - expects HTTP 200
   - expects status = ok
3. docker compose stop db
4. GET /health while DB is down
   - expects HTTP 200
   - expects status = degraded
5. GET /nope
   - expects JSON 404
6. docker compose down -v

Verification output is recorded in VERIFY.md.

---

## Success criteria

A run is considered successful when:

- REVIEW.md contains `VERDICT: APPROVE`
- VERIFY.md ends with `result: pass`
- DECISION.md contains `STATUS: COMPLETE`

---

## Notes

- `generated/app/` is always recreated from scratch per run
- `node_modules/` is never committed
- Supervisor feedback is preserved across iterations
- Maximum of 3 iterations per run

---

## Requirements

- OpenClaw CLI installed and authenticated
- Docker + docker compose
- curl
- bash

---

## License

Internal / experimental template.
