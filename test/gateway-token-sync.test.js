import test from 'node:test';
import assert from 'node:assert/strict';

import {
  gatewayTokensAlreadySynced,
  syncGatewayTokensInConfig,
} from '../src/lib/gateway-token-sync.js';

test('gatewayTokensAlreadySynced requires all gateway token fields to match', () => {
  const config = {
    gateway: {
      auth: { mode: 'token', token: 'tok' },
      remote: { token: 'tok' },
    },
  };

  assert.equal(gatewayTokensAlreadySynced(config, 'tok'), true);
  assert.equal(gatewayTokensAlreadySynced(config, 'other'), false);
  assert.equal(gatewayTokensAlreadySynced({ gateway: { auth: { token: 'tok' } } }, 'tok'), false);
});

test('syncGatewayTokensInConfig skips OpenClaw config rewrites when token is already current', async () => {
  const calls = [];
  const result = await syncGatewayTokensInConfig({
    configPath: '/tmp/openclaw.json',
    token: 'tok',
    openclawNode: 'node',
    clawArgs: (args) => ['entry.js', ...args],
    readConfig: () => ({
      gateway: {
        auth: { mode: 'token', token: 'tok' },
        remote: { token: 'tok' },
      },
      agents: {
        list: [
          {
            id: 'treebot',
            tools: { alsoAllow: ['memory_add'] },
          },
        ],
      },
    }),
    runCmd: async (cmd, args) => {
      calls.push({ cmd, args });
    },
  });

  assert.deepEqual(result, { skipped: true, reason: 'already-synced' });
  assert.deepEqual(calls, []);
});

test('syncGatewayTokensInConfig falls back to OpenClaw config set when token is stale', async () => {
  const calls = [];
  const result = await syncGatewayTokensInConfig({
    configPath: '/tmp/openclaw.json',
    token: 'new-token',
    openclawNode: 'node',
    clawArgs: (args) => ['entry.js', ...args],
    readConfig: () => ({
      gateway: {
        auth: { mode: 'token', token: 'old-token' },
        remote: { token: 'old-token' },
      },
    }),
    runCmd: async (cmd, args) => {
      calls.push({ cmd, args });
    },
  });

  assert.deepEqual(result, { skipped: false, reason: 'synced' });
  assert.deepEqual(calls, [
    { cmd: 'node', args: ['entry.js', 'config', 'set', 'gateway.auth.mode', 'token'] },
    { cmd: 'node', args: ['entry.js', 'config', 'set', 'gateway.auth.token', 'new-token'] },
    { cmd: 'node', args: ['entry.js', 'config', 'set', 'gateway.remote.token', 'new-token'] },
  ]);
});

test('syncGatewayTokensInConfig preserves compatibility fallback for unreadable configs', async () => {
  const calls = [];
  const result = await syncGatewayTokensInConfig({
    configPath: '/tmp/openclaw.json',
    token: 'tok',
    openclawNode: 'node',
    clawArgs: (args) => ['entry.js', ...args],
    readConfig: () => {
      throw new Error('jsonc or unreadable');
    },
    runCmd: async (cmd, args) => {
      calls.push({ cmd, args });
    },
  });

  assert.equal(result.skipped, false);
  assert.equal(calls.length, 3);
});
