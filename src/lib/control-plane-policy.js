import fs from 'node:fs';

export function loadControlPlanePolicy(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed = JSON.parse(raw);
  return parsed;
}
