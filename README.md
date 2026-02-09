# OpenClaw Template

A minimal, opinionated starter template for building **agent-orchestrated workflows** with OpenClaw.

This repository is intentionally small. It exists to give you a **clear mental model**, a **working baseline**, and a **repeatable structure** for OpenClaw-based projects — not to overwhelm you with abstractions or magic.

---

## What is OpenClaw?

OpenClaw is a CLI-first, agent-orchestration system inspired by the UNIX philosophy:

> small tools, clear contracts, composable workflows.

Instead of a single “do everything” AI agent, OpenClaw encourages:
- multiple specialized agents,
- explicit responsibilities,
- deterministic handoffs,
- and human-readable artifacts.

Think **workflow orchestration**, not chatbots.

---

## What is this repository?

This repository is a **public template** for starting new OpenClaw projects.

It answers one question:

> “What is the *right* way to structure an OpenClaw project from day one?”

If you clone this repo, you get:
- a clean project skeleton,
- predefined conventions,
- and a safe place to experiment without breaking core assumptions.

---

## What you get out of the box

- 🧠 **Clear agent roles**
  - A supervisor-first mental model
  - Explicit task delegation
  - Deterministic stop / iterate decisions

- 📁 **Predictable project structure**
  - Separation between configuration, agents, runs, and outputs
  - No hidden state
  - No magic folders

- 🧪 **Reproducible workflows**
  - Each run produces inspectable artifacts
  - Outputs are versionable
  - Failures are debuggable

- 🧩 **Composable by design**
  - Easy to extend with new agents
  - Easy to integrate external tools later (CI, n8n, scripts, etc.)

---

## What this template intentionally does *not* include

This is important.

This repository does **not** include:
- ❌ complex agent graphs
- ❌ auto-scaling agent pools
- ❌ plugins or extensions
- ❌ UI dashboards
- ❌ n8n or workflow automation glue
- ❌ “AI does everything” abstractions

Those belong **after** you understand the core flow.

This template optimizes for **clarity over cleverness**.

---

## Core mental model

OpenClaw workflows follow a **golden path**:

1. **A task is defined**
2. **The supervisor agent evaluates the task**
3. **Planning or execution agents are invoked**
4. **Artifacts are produced**
5. **The supervisor decides**:
   - stop (task complete), or
   - iterate (refine / fix / retry)

There is always:
- one owner of decisions,
- one source of truth,
- and a visible output.

No agent runs “just because”.

---

## Typical use cases

This template works well for:
- code generation pipelines
- research & analysis workflows
- document generation
- CI-like validation flows
- structured content creation
- local-LLM experimentation with guardrails

If your goal is **traceability and control**, you’re in the right place.

---

## Project structure (high level)

```text
.
├── AGENTS.md          # Agent roles and responsibilities
├── README.md          # You are here
├── runs/              # Execution outputs (artifacts, logs, results)
├── config/            # Project-specific configuration
├── examples/          # Minimal, boring, predictable demos
└── scripts/           # Helper scripts (optional)
