#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = path.resolve(process.argv[2] ?? process.cwd());
const ref = process.argv[3] ?? process.env.OPENCLAW_GIT_REF ?? "";
const target = path.join(root, "src/plugins/gateway-startup-plugin-ids.ts");

const original = `function listDisabledChannelIds(config: OpenClawConfig): Set<string> {
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
`;

const patched = `function listDisabledChannelIds(config: OpenClawConfig): Set<string> {
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

function hasExplicitChannelPluginStartupOverride(config: OpenClawConfig, channelId: string): boolean {
  const plugins = config.plugins;
  if (!plugins || typeof plugins !== "object" || Array.isArray(plugins)) {
    return false;
  }
  const entries = (plugins as { entries?: unknown }).entries;
  if (!entries || typeof entries !== "object" || Array.isArray(entries)) {
    return false;
  }
  const entry = (entries as Record<string, unknown>)[channelId];
  return (
    Boolean(entry && typeof entry === "object" && !Array.isArray(entry)) &&
    (entry as { enabled?: unknown }).enabled === true
  );
}

function listPotentialEnabledChannelIds(config: OpenClawConfig, env: NodeJS.ProcessEnv): string[] {
  const disabled = listDisabledChannelIds(config);
  // NIKIN staging keeps Telegram's account disabled but explicitly enables the
  // plugin entry. Preserve upstream stale-disabled protection while still
  // loading that explicitly selected channel plugin for channels.status.
  return listPotentialConfiguredChannelIds(config, env, { includePersistedAuthState: false })
    .map((id) => normalizeOptionalLowercaseString(id) ?? "")
    .filter(
      (id) => id && (!disabled.has(id) || hasExplicitChannelPluginStartupOverride(config, id)),
    );
}
`;

const marker = "Preserve upstream stale-disabled protection";
const isTargetedRef = ref === "v2026.4.26";

if (!fs.existsSync(target)) {
  console.log(`[nikin-openclaw-patch] skipped; file not found: ${target}`);
  process.exit(0);
}

const source = fs.readFileSync(target, "utf8");
if (source.includes(marker)) {
  console.log(`[nikin-openclaw-patch] already applied for ${ref || "unknown ref"}`);
  process.exit(0);
}

if (!source.includes(original)) {
  if (isTargetedRef) {
    console.error(
      `[nikin-openclaw-patch] expected v2026.4.26 channel startup block not found in ${target}`,
    );
    process.exit(1);
  }
  console.log(`[nikin-openclaw-patch] skipped; unsupported ref ${ref || "unknown"}`);
  process.exit(0);
}

fs.writeFileSync(target, source.replace(original, patched));
console.log(`[nikin-openclaw-patch] restored configured-channel startup registry for ${ref}`);
