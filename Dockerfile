# Build openclaw from source to avoid npm packaging gaps (some dist files are not shipped).
FROM node:22-bookworm AS openclaw-build

# Dependencies needed for openclaw build
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    python3 \
    make \
    g++ \
  && rm -rf /var/lib/apt/lists/*

# Install Bun (openclaw build uses it)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /openclaw

# Pin to a known-good ref (tag/branch). Override in Railway template settings if needed.
# Using a released tag avoids build breakage when `main` temporarily references unpublished packages.
ARG OPENCLAW_GIT_REF=v2026.2.9
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

# Patch: relax version requirements for packages that may reference unpublished versions.
# Apply to all extension package.json files to handle workspace protocol (workspace:*).
RUN set -eux; \
  find ./extensions -name 'package.json' -type f | while read -r f; do \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
    sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
  done

# Bypass pnpm minimumReleaseAge for packages that OC pins but are freshly published
RUN pnpm install --no-frozen-lockfile --config.minimumReleaseAge=0
RUN pnpm build
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build
# Fail the image build if a bundled channel entry was generated without the
# runtime contract required by newer OpenClaw channel loading.
RUN node scripts/test-built-bundled-channel-entry-smoke.mjs


# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    tini \
    python3 \
    python3-pip \
    python3-venv \
    gettext-base \
  && pip3 install --break-system-packages duckdb \
  && rm -rf /var/lib/apt/lists/*

# `openclaw update` expects pnpm. Provide it in the runtime image.
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# Persist user-installed tools by default by targeting the Railway volume.
# - npm global installs -> /data/npm
# - pnpm global installs -> /data/pnpm (binaries) + /data/pnpm-store (store)
ENV NPM_CONFIG_PREFIX=/data/npm
ENV NPM_CONFIG_CACHE=/data/npm-cache
ENV PNPM_HOME=/data/pnpm
ENV PNPM_STORE_DIR=/data/pnpm-store
ENV PATH="/data/npm/bin:/data/pnpm:${PATH}"
# The image is built from a source checkout, so OpenClaw can otherwise prefer
# dist-runtime wrappers. NIKIN production needs the packaged dist tree with
# staged channel runtime deps for Telegram/OpenClaw v2026.4.26+.
ENV OPENCLAW_BUNDLED_PLUGINS_DIR=/openclaw/dist/extensions

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide an openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
  && chmod +x /usr/local/bin/openclaw

COPY src ./src

# NIKIN production config: templates + workspace seeds.
# envsubst at container start renders ${VAR} references using Railway env vars.
COPY nikin-config /etc/nikin-config
COPY nikin-entrypoint.sh /usr/local/bin/nikin-entrypoint.sh
RUN chmod +x /usr/local/bin/nikin-entrypoint.sh

# The wrapper listens on $PORT.
# IMPORTANT: Do not set a default PORT here.
# Railway injects PORT at runtime and routes traffic to that port.
# If we force a different port, deployments can come up but the domain will route elsewhere.
EXPOSE 8080

# Ensure PID 1 reaps zombies and forwards signals.
# nikin-entrypoint.sh seeds config/tools/workspace then execs the original CMD.
ENTRYPOINT ["tini", "--", "/usr/local/bin/nikin-entrypoint.sh"]
CMD ["node", "src/server.js"]
