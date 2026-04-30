import fs from 'node:fs';

export function gatewayTokensAlreadySynced(config, token) {
  if (!config || typeof config !== 'object' || !token) return false;
  return (
    config.gateway?.auth?.mode === 'token'
    && config.gateway?.auth?.token === token
    && config.gateway?.remote?.token === token
  );
}

export function readConfigJson(path) {
  return JSON.parse(fs.readFileSync(path, 'utf8'));
}

export async function syncGatewayTokensInConfig({
  configPath,
  token,
  runCmd,
  openclawNode,
  clawArgs,
  readConfig = readConfigJson,
}) {
  if (!token) {
    return { skipped: true, reason: 'missing-token' };
  }

  try {
    const config = readConfig(configPath);
    if (gatewayTokensAlreadySynced(config, token)) {
      return { skipped: true, reason: 'already-synced' };
    }
  } catch {
    // Preserve historical behavior when the config cannot be read as JSON.
    // The OpenClaw CLI remains the compatibility fallback for unusual configs.
  }

  await runCmd(openclawNode, clawArgs(['config', 'set', 'gateway.auth.mode', 'token']));
  await runCmd(openclawNode, clawArgs(['config', 'set', 'gateway.auth.token', token]));
  await runCmd(openclawNode, clawArgs(['config', 'set', 'gateway.remote.token', token]));
  return { skipped: false, reason: 'synced' };
}
