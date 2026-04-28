import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

test("Docker image pins bundled plugins to packaged dist tree", () => {
  const dockerfile = fs.readFileSync(new URL("../Dockerfile", import.meta.url), "utf8");

  assert.match(
    dockerfile,
    /RUN node scripts\/test-built-bundled-channel-entry-smoke\.mjs/,
  );
  assert.match(
    dockerfile,
    /ENV OPENCLAW_BUNDLED_PLUGINS_DIR=\/openclaw\/dist\/extensions/,
  );
});
