import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

test('setup run catch path returns JSON directly', () => {
  const src = fs.readFileSync(new URL('../src/server.js', import.meta.url), 'utf8');
  const idx = src.indexOf('app.post("/setup/api/run"');
  assert.ok(idx >= 0);
  const nextRouteIdx = src.indexOf('app.get("/setup/api/debug"', idx);
  assert.ok(nextRouteIdx > idx);
  const window = src.slice(idx, nextRouteIdx);
  assert.match(window, /\[\/setup\/api\/run\] error:/);
  assert.match(window, /res\s*\.\s*status\(500\)\s*\.\s*json\(/);
  assert.doesNotMatch(window, /return respondJson\(500,/);
});
