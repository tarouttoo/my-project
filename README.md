# my-project

## Autonomous agents (sandcastle)

Issues labeled `ready-for-agent` are implemented autonomously:

1. **Planner** (pi `glm-5.3`, thinking high) picks unblocked issues and emits a
   `<plan>` JSON (max 3 per cycle).
2. **Implementer** (pi `glm-5.3-flash`) codes on `sandcastle/issue-<id>`
   branches, one sandbox per issue, in parallel.
3. **Reviewer** (pi `glm-5.3`) polishes the same branch (clarity, no behavior
   changes).
4. The orchestrator deterministically pushes each completed branch and opens a
   PR (`Closes #N`). **A human merges.**

### First run (host setup)

```bash
npm run wizard          # interactive: Node, Docker, gh auth, STARIMG_API_KEY → .env, image build, smoke test
```

### Run the loop

```bash
npm run sandcastle
```

### Layout

- `.sandcastle/main.ts` — orchestration (plan → execute+review → PR)
- `.sandcastle/*-prompt.md` — agent prompts
- `.sandcastle/Dockerfile` — sandbox image (node 22, git, gh, pi)
- `.sandcastle/pi-config/` — pi provider config (starimg aggregator, key via
  `$STARIMG_API_KEY` — no secrets committed)
- `.sandcastle/.env` — secrets (gitignored): `STARIMG_API_KEY`, `GH_TOKEN`

Rebuild the image after changing the Dockerfile or pi-config:

```bash
docker build -f .sandcastle/Dockerfile \
  --build-arg AGENT_UID=$(id -u) --build-arg AGENT_GID=$(id -g) \
  -t sandcastle:my-project .
```
