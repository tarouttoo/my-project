#!/usr/bin/env bash
# Sandcastle host setup wizard for my-project.
#
# Run on the host (WSL Ubuntu), from anywhere inside the repo:
#   bash .sandcastle/wizard.sh        (or: npm run wizard)
#
# Walks through everything only a human can do: installing host tooling,
# authenticating gh, extracting the STARIMG_API_KEY from the Windows
# environment, writing .sandcastle/.env, building the sandbox image and
# smoke-testing pi inside it.

set -euo pipefail

# --- helpers -----------------------------------------------------------------

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; reset=$'\033[0m'

step() { printf '\n%s==> %s%s\n' "$bold" "$1" "$reset"; }
ok()   { printf '%s  ✓%s %s\n' "$green" "$reset" "$1"; }
warn() { printf '%s  !%s %s\n' "$yellow" "$reset" "$1"; }
die()  { printf '%s  ✗%s %s\n' "$red" "$reset" "$1" >&2; exit 1; }

confirm() { # confirm <question> [default]
  local default="${2:-y}" prompt reply
  if [ "$default" = "y" ]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
  read -r -p "  $1 $prompt " reply || reply=""
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
IMAGE_NAME="sandcastle:my-project"
ENV_FILE=".sandcastle/.env"

# --- 1. Node 22+ -------------------------------------------------------------

step "Node.js (need v22+)"
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$NODE_MAJOR" -ge 22 ]; then
    ok "node $(node --version)"
  else
    warn "node $(node --version) is older than v22."
    confirm "Install v22 LTS via nvm now?" || die "Install Node 22+ manually, then re-run."
    export NVM_DIR="$HOME/.nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    # shellcheck disable=SC1091
    \. "$NVM_DIR/nvm.sh"
    nvm install 22
    nvm use 22
    ok "node $(node --version) (via nvm)"
  fi
else
  warn "node not found."
  confirm "Install v22 LTS via nvm now?" || die "Install Node 22+ manually, then re-run."
  export NVM_DIR="$HOME/.nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  # shellcheck disable=SC1091
  \. "$NVM_DIR/nvm.sh"
  nvm install 22
  nvm use 22
  ok "node $(node --version) (via nvm)"
fi

# --- 2. Docker ---------------------------------------------------------------

step "Docker"
if docker info >/dev/null 2>&1; then
  ok "docker $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo ok)"
else
  warn "docker not usable."
  cat <<'EOF'
  Install Docker on WSL Ubuntu, then re-run:
    https://docs.docker.com/engine/install/ubuntu/
  (or install Docker Desktop with WSL integration enabled)
EOF
  die "Docker is required to build and run the sandbox image."
fi

# --- 3. GitHub CLI + auth ----------------------------------------------------

step "GitHub CLI"
if ! command -v gh >/dev/null 2>&1; then
  warn "gh not found — installing…"
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y gh
  else
    apt-get update && apt-get install -y gh
  fi
fi
ok "gh $(gh --version | head -1)"

if gh auth status >/dev/null 2>&1; then
  ok "gh authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
else
  warn "gh not authenticated."
  confirm "Run 'gh auth login' now?" || die "Authenticate gh, then re-run."
  gh auth login
  gh auth status >/dev/null 2>&1 || die "gh auth failed."
  ok "gh authenticated."
fi

# --- 4. pi CLI ---------------------------------------------------------------

step "pi CLI"
if command -v pi >/dev/null 2>&1; then
  ok "pi on PATH"
else
  warn "pi not found — installing globally…"
  npm install -g @earendil-works/pi-coding-agent
  ok "pi installed"
fi

# --- 5. pi provider config ---------------------------------------------------

step "pi provider config (.sandcastle/pi-config/)"
if [ -f "$HOME/.pi/agent/models.json" ]; then
  cp "$HOME/.pi/agent/models.json"  .sandcastle/pi-config/models.json
  cp "$HOME/.pi/agent/settings.json" .sandcastle/pi-config/settings.json 2>/dev/null || true
  # Strip any inline apiKey → reference the env var instead. No secrets in the repo.
  node -e '
    const fs = require("fs");
    const p = ".sandcastle/pi-config/models.json";
    const j = JSON.parse(fs.readFileSync(p, "utf8"));
    for (const provider of Object.values(j.providers || {})) {
      if (provider && typeof provider.apiKey === "string" && !provider.apiKey.startsWith("$")) {
        provider.apiKey = "$STARIMG_API_KEY";
      }
    }
    fs.writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
  ' || die "Failed to normalise models.json."
  ok "copied from ~/.pi/agent and normalised (apiKey → \$STARIMG_API_KEY)"
else
  ok "using committed pi-config (starimg via \$STARIMG_API_KEY) — no host override found"
fi

# --- 6. STARIMG_API_KEY + GH_TOKEN → .sandcastle/.env -------------------------

step "Secrets → $ENV_FILE"
KEY=""
if command -v powershell.exe >/dev/null 2>&1; then
  KEY="$(powershell.exe -NoProfile -Command 'Write-Output $env:STARIMG_API_KEY' | tr -d '\r' || true)"
elif command -v cmd.exe >/dev/null 2>&1; then
  KEY="$(cmd.exe /c "echo %STARIMG_API_KEY%" 2>/dev/null | tr -d '\r' || true)"
fi

if [ -z "$KEY" ] || [[ "$KEY" == *"%"* ]]; then
  warn "could not read STARIMG_API_KEY from the Windows environment."
  read -r -s -p "  Paste STARIMG_API_KEY (input hidden): " KEY
  echo
fi
[ -n "$KEY" ] || die "STARIMG_API_KEY is required."

GH_TOKEN="$(gh auth token)"
[ -n "$GH_TOKEN" ] || die "gh auth token returned nothing."

umask 177
{
  echo "STARIMG_API_KEY=$KEY"
  echo "GH_TOKEN=$GH_TOKEN"
} > "$ENV_FILE"
umask 022
ok "wrote $ENV_FILE (${dim}gitignored${reset})"

# --- 7. npm dependencies -----------------------------------------------------

step "npm dependencies"
npm install
ok "installed"

# --- 8. Build the sandbox image ----------------------------------------------

step "Build sandbox image $IMAGE_NAME"
docker build -f .sandcastle/Dockerfile \
  --build-arg AGENT_UID="$(id -u)" \
  --build-arg AGENT_GID="$(id -g)" \
  -t "$IMAGE_NAME" .
ok "image built"

# --- 9. Smoke test: pi + starimg inside the container -------------------------

step "Smoke test (pi --model glm-5.3 in the container)"
SMOKE="$(command -v timeout >/dev/null 2>&1 && echo "timeout 180" || echo "")"
if $SMOKE docker run --rm --env-file "$ENV_FILE" "$IMAGE_NAME" \
    pi -p --model glm-5.3 "Reply with exactly: OK" 2>&1 | grep -q "OK"; then
  ok "pi ↔ starimg works inside the sandbox"
else
  die "Smoke test failed. Check the key, the provider config and network access to https://ai.starimg.ru/v1"
fi

# --- 10. Next steps -----------------------------------------------------------

step "Done"
cat <<EOF

  ${green}Setup complete.${reset} Next:

  1. Label a fully-specified issue as ${bold}ready-for-agent${reset}:
       gh issue edit <number> --add-label ready-for-agent
     (create the label first if needed:
       gh label create ready-for-agent --description "Fully specified, ready for an AFK agent")

  2. Run the autonomous loop:
       ${bold}npm run sandcastle${reset}

  The planner picks unblocked issues, implementers work on
  sandcastle/issue-<id> branches, reviewers polish, and the orchestrator
  opens PRs (${dim}Closes #N${reset}). You merge.

EOF
