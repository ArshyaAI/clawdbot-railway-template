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

# Ensure treebot has guardrails and required tools without overwriting the
# environment's exec posture. Production currently relies on full exec; staging
# and production must not silently flip between full and allowlist during boot.
TREEBOT_BASE_TOOLS = ['read', 'write', 'web_search', 'web_fetch', 'image',
                      'session_status', 'sessions_send', 'sessions_spawn']
TREEBOT_MEMORY_TOOLS = ['memory_add', 'memory_search', 'memory_get',
                        'memory_list', 'memory_update', 'memory_delete',
                        'memory_event_list', 'memory_event_status']
TREEBOT_DENY = ['edit', 'apply_patch', 'process', 'gateway', 'agents_list']
TREEBOT_SUBAGENTS = {
    'allowAgents': ['nikin-content', 'nikin-sustainability',
                    'nikin-analytics', 'nikin-ops', 'nikin-support']
}
for agent in config.get('agents', {}).get('list', []):
    if agent.get('id') == 'treebot':
        tools = agent.get('tools')
        if not isinstance(tools, dict):
            tools = {}
            agent['tools'] = tools
            changed = True
            print('[nikin-entrypoint] Rebuilt treebot tools object')
        if tools.get('profile') != 'messaging':
            tools['profile'] = 'messaging'
            agent['subagents'] = TREEBOT_SUBAGENTS
            changed = True
            print('[nikin-entrypoint] Fixed treebot tool profile -> messaging')

        also_allow = tools.get('alsoAllow')
        if not isinstance(also_allow, list):
            also_allow = []
            tools['alsoAllow'] = also_allow
            changed = True
        for tool_name in TREEBOT_BASE_TOOLS + TREEBOT_MEMORY_TOOLS:
            if tool_name not in also_allow:
                also_allow.append(tool_name)
                changed = True
                print(f'[nikin-entrypoint] Added treebot tool: {tool_name}')

        deny = tools.get('deny')
        if not isinstance(deny, list):
            deny = []
            tools['deny'] = deny
            changed = True
        for tool_name in TREEBOT_DENY:
            if tool_name not in deny:
                deny.append(tool_name)
                changed = True
                print(f'[nikin-entrypoint] Added treebot deny: {tool_name}')

        if 'exec' not in tools:
            tools['exec'] = {'security': 'full', 'ask': 'off'}
            changed = True
            print('[nikin-entrypoint] Added default treebot exec policy (full, ask off)')

        fs_cfg = tools.get('fs')
        if not isinstance(fs_cfg, dict):
            fs_cfg = {}
            tools['fs'] = fs_cfg
            changed = True
        if fs_cfg.get('workspaceOnly') is not True:
            fs_cfg['workspaceOnly'] = True
            changed = True
            print('[nikin-entrypoint] Fixed treebot fs.workspaceOnly -> true')

        if agent.get('subagents') != TREEBOT_SUBAGENTS:
            agent['subagents'] = TREEBOT_SUBAGENTS
            changed = True
            print('[nikin-entrypoint] Applied treebot subagent allowlist')

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

echo "[nikin-entrypoint] Done. Handing off to: $*"
exec "$@"
