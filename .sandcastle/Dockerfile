# Sandcastle sandbox image for my-project.
#
# Build from the repo root (the wizard does this for you):
#   docker build -f .sandcastle/Dockerfile \
#     --build-arg AGENT_UID=$(id -u) --build-arg AGENT_GID=$(id -g) \
#     -t sandcastle:my-project .
#
# Secrets (STARIMG_API_KEY, GH_TOKEN) are NOT baked in — they arrive via
# .sandcastle/.env at container start.

FROM node:22-slim

ARG AGENT_UID=1000
ARG AGENT_GID=1000

# git is required (commits/branches); gh is required for issue fetching
# inside the sandbox; curl/jq/ca-certificates for tooling.
RUN apt-get update \
  && apt-get install -y --no-install-recommends git curl jq ca-certificates gnupg \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# pi CLI — the coding agent sandcastle drives.
RUN npm install -g @earendil-works/pi-coding-agent

# Non-root agent user; UID/GID must match the host user (build args) so
# bind-mounted worktrees are writable.
RUN groupadd -g ${AGENT_GID} agent \
  && useradd -m -u ${AGENT_UID} -g agent -s /bin/bash agent

USER agent
ENV HOME=/home/agent
WORKDIR /home/agent/workspace

# pi configuration: starimg aggregator provider. models.json references the
# key via $STARIMG_API_KEY — no secret in the image.
COPY --chown=agent:agent .sandcastle/pi-config/models.json   /home/agent/.pi/agent/models.json
COPY --chown=agent:agent .sandcastle/pi-config/settings.json /home/agent/.pi/agent/settings.json
COPY --chown=agent:agent .sandcastle/pi-config/trust.json    /home/agent/.pi/agent/trust.json

# Model discovery extension (dynamic model list from the aggregator) and the
# git identity for commits made inside the sandbox.
RUN pi install npm:pi-models-discovery \
  && git config --global user.name "sandcastle-agent" \
  && git config --global user.email "sandcastle-agent@users.noreply.github.com" \
  && git config --global --add safe.directory /home/agent/workspace \
  && mkdir -p /home/agent/workspace
