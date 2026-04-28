import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const script = new URL("../scripts/patch-openclaw-channel-startup-registry.mjs", import.meta.url);
const scriptPath = fileURLToPath(script);

function writeFixture(root) {
  const dir = path.join(root, "src/plugins");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "gateway-startup-plugin-ids.ts"),
    `import { listPotentialConfiguredChannelIds } from "../channels/config-presence.js";
import type { OpenClawConfig } from "../config/types.openclaw.js";
import { normalizeOptionalLowercaseString } from "../shared/string-coerce.js";

function listDisabledChannelIds(config: OpenClawConfig): Set<string> {
  const channels = config.channels;
  if (!channels || typeof channels !== "object" || Array.isArray(channels)) {
    return new Set();
  }
  return new Set(
    Object.entries(channels)
      .filter(([, value]) => {
        return (
          value &&
          typeof value === "object" &&
          !Array.isArray(value) &&
          (value as { enabled?: unknown }).enabled === false
        );
      })
      .map(([channelId]) => normalizeOptionalLowercaseString(channelId))
      .filter((channelId): channelId is string => Boolean(channelId)),
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === "object" && !Array.isArray(value));
}

function isConfigActivationValueEnabled(value: unknown): boolean {
  if (value === false) {
    return false;
  }
  if (isRecord(value) && value.enabled === false) {
    return false;
  }
  return true;
}

function listPotentialEnabledChannelIds(config: OpenClawConfig, env: NodeJS.ProcessEnv): string[] {
  const disabled = listDisabledChannelIds(config);
  return listPotentialConfiguredChannelIds(config, env, { includePersistedAuthState: false })
    .map((id) => normalizeOptionalLowercaseString(id) ?? "")
    .filter((id) => id && !disabled.has(id));
}
`,
  );
}

test("patch restores configured disabled channels to gateway startup registry", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "openclaw-channel-registry-"));
  writeFixture(root);

  const output = execFileSync(process.execPath, [scriptPath, root, "v2026.4.26"], {
    encoding: "utf8",
  });
  const patched = fs.readFileSync(
    path.join(root, "src/plugins/gateway-startup-plugin-ids.ts"),
    "utf8",
  );

  assert.match(output, /restored configured-channel startup registry/);
  assert.match(patched, /Preserve upstream stale-disabled protection/);
  assert.match(patched, /function listDisabledChannelIds/);
  assert.match(patched, /hasExplicitChannelPluginStartupOverride/);
  assert.match(
    patched,
    /!disabled\.has\(id\) \|\| hasExplicitChannelPluginStartupOverride\(config, id\)/,
  );
});
