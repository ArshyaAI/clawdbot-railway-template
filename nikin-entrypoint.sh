#!/bin/sh
# nikin-entrypoint.sh — NIKIN OpenClaw config seeder for Railway
#
# Runs before `node src/server.js` on every container start.
# - Always re-renders config + tools from templates (picks up rotated secrets).
# - Seeds workspace files only if absent (preserves agent-written data on redeploy).
#
# Required env vars (set in Railway Variables panel):
#   ANTHROPIC_API_KEY, SETUP_PASSWORD, TELEGRAM_BOT_TOKEN,
#   TELEGRAM_WEBHOOK_SECRET, TELEGRAM_NICHOLAS_CHAT_ID,
#   CONNECTOS_URL, CONNECTOS_TOKEN
#
# Injected by railway.toml:
#   OPENCLAW_STATE_DIR    — /data/.clawdbot (persistent volume)
#   OPENCLAW_WORKSPACE_DIR — /data/workspace (persistent volume)

set -e

STATE_DIR="${OPENCLAW_STATE_DIR:-${CLAWDBOT_STATE_DIR:-/data/.clawdbot}}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
INIT_DIR="/etc/nikin-config"

echo "[nikin-entrypoint] STATE_DIR=$STATE_DIR"
echo "[nikin-entrypoint] WORKSPACE_DIR=$WORKSPACE_DIR"

# ── Create required directories ───────────────────────────────────────────────
mkdir -p "$STATE_DIR/tools"
mkdir -p "$WORKSPACE_DIR/nikin-assistant/skills"

# ── Config: select template by NIKIN_CONFIG_PROFILE, seed only if absent ──────
PROFILE="${NIKIN_CONFIG_PROFILE:-default}"
echo "[nikin-entrypoint] Config profile: $PROFILE"

if [ -f "$STATE_DIR/openclaw.json" ]; then
  echo "[nikin-entrypoint] Config exists — preserving runtime config"
else
  case "$PROFILE" in
    arshya)
      TMPL="$INIT_DIR/openclaw.config.arshya.json"
      echo "[nikin-entrypoint] Seeding from arshya template (March 7 treebot)..."
      ;;
    *)
      TMPL="$INIT_DIR/openclaw.config.jsonc.tmpl"
      echo "[nikin-entrypoint] Seeding from default template..."
      ;;
  esac
  envsubst < "$TMPL" > "$STATE_DIR/openclaw.json"
  echo "[nikin-entrypoint] Config written to $STATE_DIR/openclaw.json"
fi

# ── Render tool definitions (envsubst replaces CONNECTOS_URL, CONNECTOS_TOKEN) ──
echo "[nikin-entrypoint] Seeding tool definitions..."
for f in "$INIT_DIR/tools/"*.json; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  envsubst < "$f" > "$STATE_DIR/tools/$fname"
  echo "[nikin-entrypoint] Tool: $STATE_DIR/tools/$fname"
done

# ── Seed workspace files (only if absent — preserves user data) ───────────────
echo "[nikin-entrypoint] Seeding workspace files..."

# Seed agent root files (SOUL.md, etc.)
for f in "$INIT_DIR/workspace/nikin-assistant/"*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  dest="$WORKSPACE_DIR/nikin-assistant/$fname"
  if [ ! -f "$dest" ]; then
    cp "$f" "$dest"
    echo "[nikin-entrypoint] Seeded: $dest"
  else
    echo "[nikin-entrypoint] Exists (skipped): $dest"
  fi
done

# Seed skills subdirectory
for f in "$INIT_DIR/workspace/nikin-assistant/skills/"*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  dest="$WORKSPACE_DIR/nikin-assistant/skills/$fname"
  if [ ! -f "$dest" ]; then
    cp "$f" "$dest"
    echo "[nikin-entrypoint] Seeded: $dest"
  else
    echo "[nikin-entrypoint] Exists (skipped): $dest"
  fi
done

# ── Fix config workspace paths if they drifted ──────────────────────────────
# The config doctor or agent sessions can reset workspace paths to defaults.
# This ensures the gateway always finds workspace files on the persistent volume.
CONFIG_FILE="$STATE_DIR/openclaw.json"
if [ -f "$CONFIG_FILE" ] && command -v python3 >/dev/null 2>&1; then
  python3 -c "
import json, sys

config_path = sys.argv[1]
workspace_dir = sys.argv[2]
changed = False

with open(config_path) as f:
    config = json.load(f)

# Fix agents.defaults.workspace
defaults = config.get('agents', {}).get('defaults', {})
if defaults.get('workspace', '') != workspace_dir:
    config.setdefault('agents', {}).setdefault('defaults', {})['workspace'] = workspace_dir
    changed = True
    print(f'[nikin-entrypoint] Fixed agents.defaults.workspace -> {workspace_dir}')

# Fix nikin-assistant agent workspace (relative -> absolute)
for agent in config.get('agents', {}).get('list', []):
    if agent.get('id') == 'nikin-assistant':
        expected = f'{workspace_dir}/nikin-assistant'
        if agent.get('workspace', '') != expected:
            agent['workspace'] = expected
            changed = True
            print(f'[nikin-entrypoint] Fixed nikin-assistant workspace -> {expected}')

# Ensure treebot has guardrails (sandbox exec, workspace-only FS, deny dangerous tools)
TREEBOT_TOOLS = {
    'profile': 'messaging',
    'alsoAllow': ['read', 'write', 'web_search', 'web_fetch', 'image',
                  'session_status', 'sessions_send', 'sessions_spawn'],
    'deny': ['edit', 'apply_patch', 'process', 'gateway', 'agents_list'],
    'exec': {'security': 'full', 'ask': 'off'},
    'fs': {'workspaceOnly': True}
}
TREEBOT_SUBAGENTS = {
    'allowAgents': ['nikin-content', 'nikin-sustainability',
                    'nikin-analytics', 'nikin-ops', 'nikin-support']
}
for agent in config.get('agents', {}).get('list', []):
    if agent.get('id') == 'treebot':
        if agent.get('tools') != TREEBOT_TOOLS or agent.get('subagents') != TREEBOT_SUBAGENTS:
            agent['tools'] = TREEBOT_TOOLS
            agent['subagents'] = TREEBOT_SUBAGENTS
            changed = True
            print('[nikin-entrypoint] Applied treebot guardrails (sandbox exec, deny dangerous, workspaceOnly)')

# Remove stale google-gemini-cli-auth from plugins.allow (config doctor removes it every boot anyway)
plugins = config.get('plugins', {})
allow = plugins.get('allow', [])
if 'google-gemini-cli-auth' in allow:
    allow.remove('google-gemini-cli-auth')
    changed = True
    print('[nikin-entrypoint] Removed stale google-gemini-cli-auth from plugins.allow')
entries = plugins.get('entries', {})
if 'google-gemini-cli-auth' in entries:
    del entries['google-gemini-cli-auth']
    changed = True
    print('[nikin-entrypoint] Removed stale google-gemini-cli-auth from plugins.entries')

if changed:
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print('[nikin-entrypoint] Config patched successfully')
else:
    print('[nikin-entrypoint] Workspace paths OK')
" "$CONFIG_FILE" "$WORKSPACE_DIR" 2>&1 || echo "[nikin-entrypoint] Config patch skipped (python error)"
fi

# ── Repair persisted Telegram hotfix source if present ─────────────────────
# Some production volumes have a Telegram hotfix script persisted under /data.
# If that script points at /openclaw/dist-runtime/extensions/telegram, it can
# move its own source during startup and crash-loop before SSH is available.
# Keep the persisted script pointed at the packaged OpenClaw copy for this
# image, and restore a missing dist-runtime bundle before the wrapper starts.
TELEGRAM_HOTFIX_SCRIPT="/data/.root/openclaw-hotfix/apply-telegram-hotfix.sh"
TELEGRAM_HOTFIX_SRC="/openclaw/node_modules/openclaw/dist/extensions/telegram"
TELEGRAM_RUNTIME_DST="/openclaw/dist-runtime/extensions/telegram"

if [ -f "$TELEGRAM_HOTFIX_SCRIPT" ] && [ -d "$TELEGRAM_HOTFIX_SRC" ]; then
  echo "[nikin-entrypoint] Repairing Telegram hotfix source"
  python3 - "$TELEGRAM_HOTFIX_SCRIPT" "$TELEGRAM_HOTFIX_SRC" <<'PY' 2>&1 || echo "[nikin-entrypoint] Telegram hotfix source repair skipped"
from pathlib import Path
import sys

script = Path(sys.argv[1])
source = sys.argv[2]
text = script.read_text()
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith("SRC="):
        lines[i] = f"SRC={source}"
        break
else:
    lines.insert(0, f"SRC={source}")
script.write_text("\n".join(lines) + "\n")
PY

  if [ ! -d "$TELEGRAM_RUNTIME_DST" ]; then
    echo "[nikin-entrypoint] Restoring missing Telegram dist-runtime bundle"
    mkdir -p "$(dirname "$TELEGRAM_RUNTIME_DST")"
    cp -a "$TELEGRAM_HOTFIX_SRC" "$TELEGRAM_RUNTIME_DST"
  fi
fi

echo "[nikin-entrypoint] Done. Handing off to: $*"
exec "$@"
