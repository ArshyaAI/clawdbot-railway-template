import fs from 'node:fs/promises';
import path from 'node:path';

export async function appendAuditEvent(filePath, event) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  const payload = {
    timestamp: new Date().toISOString(),
    event: event.event,
    mode: event.mode ?? null,
    force: event.force ?? false,
    baseHash: event.baseHash ?? null,
    candidateHash: event.candidateHash ?? null,
    notes: event.notes ?? null,
    result: event.result ?? null,
    actor: event.actor ?? null,
    activeWorkerCount: event.activeWorkerCount ?? null,
  };
  await fs.appendFile(filePath, JSON.stringify(payload) + '\n', 'utf8');
}
