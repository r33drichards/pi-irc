import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { test } from "node:test";

// Run against the extracted Pi checkout or /app in the built image. No API calls.
assert.ok(process.env.PI_SOURCE_ROOT, "Set PI_SOURCE_ROOT to the hydrated Pi checkout");
const aiRoot = join(resolve(process.env.PI_SOURCE_ROOT), "packages/ai");
const dataRoot = join(aiRoot, "src/providers/data");
const readCatalog = (provider) => JSON.parse(readFileSync(join(dataRoot, `${provider}.json`), "utf8"));

test("release snapshot passes Pi's manifest and provider-shard validation", () => {
  execFileSync(process.execPath, [join(aiRoot, "scripts/check-model-data.ts")], { stdio: "pipe" });
});

test("Kimi Coding catalog is retained for its statically imported provider", () => {
  const models = readCatalog("kimi-coding");
  assert.deepEqual(Object.keys(models), ["anthropic-messages"]);
  assert.ok(Object.keys(models["anthropic-messages"]).length > 0);
  assert.match(readFileSync(join(aiRoot, "src/providers/kimi-coding.models.ts"), "utf8"), /KIMI_CODING_MODELS/);
});

test("OpenCode Go catalog uses only APIs implemented by the pinned provider", () => {
  const supported = new Set(["anthropic-messages", "openai-completions", "openai-responses"]);
  const models = readCatalog("opencode-go");
  assert.ok(Object.keys(models).length > 0);
  for (const api of Object.keys(models)) assert.ok(supported.has(api), `Unsupported OpenCode Go API: ${api}`);
});

test("snapshot preserves the pinned source's Copilot GPT Responses routing (#9253)", () => {
  const models = Object.values(readCatalog("github-copilot")).flatMap(Object.values);
  const gpt = models.filter((model) => model.id.startsWith("gpt-"));
  assert.ok(gpt.length > 0);
  for (const model of gpt) assert.equal(model.api, "openai-responses", model.id);
  const astra = gpt.find((model) => model.id === "gpt-6-astra");
  assert.deepEqual(astra.compat, { supportsOpenAIGrammarTools: true });
  assert.deepEqual(astra.thinkingLevelMap, {
    off: null, minimal: null, low: "low", medium: "medium", high: "high", xhigh: "xhigh", max: "max",
  });
});

test("offline validation rejects corrupted catalog data", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-model-data-test-"));
  try {
    cpSync(join(aiRoot, "scripts"), join(root, "scripts"), { recursive: true });
    cpSync(join(aiRoot, "src"), join(root, "src"), { recursive: true });
    writeFileSync(join(root, "src/providers/data/kimi-coding.json"), "{}\n");
    assert.throws(
      () => execFileSync(process.execPath, [join(root, "scripts/check-model-data.ts")], { stdio: "pipe" }),
      /contains no generated model data|manifest hash/,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
