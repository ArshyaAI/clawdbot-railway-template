import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { appendAuditEvent } from '../src/lib/config-audit-log.js';

test('audit log appends one JSON object per line', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-log-'));
  const file = path.join(dir, 'config-audit.jsonl');
  await appendAuditEvent(file, { event: 'apply_requested', force: false });
  await appendAuditEvent(file, { event: 'apply_succeeded', force: false });
  const lines = fs.readFileSync(file, 'utf8').trim().split('\n');
  assert.equal(lines.length, 2);
  assert.equal(JSON.parse(lines[0]).event, 'apply_requested');
  assert.equal(JSON.parse(lines[1]).event, 'apply_succeeded');
});
