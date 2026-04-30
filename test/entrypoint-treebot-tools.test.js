import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const entrypoint = fs.readFileSync(
  new URL('../nikin-entrypoint.sh', import.meta.url),
  'utf8',
);

test('nikin entrypoint preserves treebot exec policy during tool reconciliation', () => {
  assert.match(entrypoint, /TREEBOT_MEMORY_TOOLS/);
  assert.match(entrypoint, /memory_add/);
  assert.match(entrypoint, /if not isinstance\(tools, dict\):/);
  assert.match(entrypoint, /if 'exec' not in tools:/);
  assert.doesNotMatch(entrypoint, /agent\['tools'\]\s*=\s*TREEBOT_TOOLS/);
});
