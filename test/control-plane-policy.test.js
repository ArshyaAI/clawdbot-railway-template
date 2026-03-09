import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadControlPlanePolicy } from '../src/lib/control-plane-policy.js';

test('control-plane policy loads from file path and validates shape', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'policy-'));
  const file = path.join(dir, 'policy.json');
  fs.writeFileSync(file, JSON.stringify({
    primaryAgentId: 'primary-agent',
    primaryChannel: 'test-channel',
    requiredWorkerTools: ['read', 'write', 'web_fetch', 'web_search'],
    requiredPrimaryAgentDeniedTools: ['gateway'],
    requirePrimaryAgentWorkspaceOnly: true,
    forbidRunTimeoutSecondsZero: true,
  }));
  const policy = loadControlPlanePolicy(file);
  assert.equal(policy.primaryAgentId, 'primary-agent');
  assert.equal(policy.primaryChannel, 'test-channel');
  assert.equal(policy.requirePrimaryAgentWorkspaceOnly, true);
  assert.deepEqual(policy.requiredPrimaryAgentDeniedTools, ['gateway']);
});
