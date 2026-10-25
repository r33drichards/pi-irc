import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const aiRoot = join(resolve(process.argv[2] ?? "."), "packages/ai");
const { createModelDataManifest, readModelDataStructure, validateGeneratedModelData } =
  await import(pathToFileURL(join(aiRoot, "scripts/model-data.ts")).href);

// Validate the checksum-pinned release snapshot before making any changes.
validateGeneratedModelData(aiRoot);
const dataRoot = join(aiRoot, "src/providers/data");
const catalogPath = join(dataRoot, "github-copilot.json");
const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));

// Preserve Pi commit 7d8ab31a4 (#9253), included in PI_COMMIT but newer than
// the 0.85.1 release: every Copilot gpt-* model uses the Responses API.
for (const [api, models] of Object.entries(catalog)) {
  if (api === "openai-responses") continue;
  for (const [id, model] of Object.entries(models)) {
    if (!id.startsWith("gpt-")) continue;
    catalog["openai-responses"] ??= {};
    const routed = { ...model, api: "openai-responses" };
    // Match the generator's API-specific metadata, not completions-only flags.
    delete routed.compat;
    if (Number(/^gpt-(\d+)/.exec(id)?.[1]) >= 5) {
      routed.compat = { supportsOpenAIGrammarTools: true };
    }
    if (id === "gpt-6-astra") {
      routed.thinkingLevelMap = {
        ...model.thinkingLevelMap,
        off: null, minimal: null, low: "low", medium: "medium", high: "high", xhigh: "xhigh", max: "max",
      };
    }
    catalog["openai-responses"][id] = routed;
    delete models[id];
  }
  if (Object.keys(models).length === 0) delete catalog[api];
}
writeFileSync(catalogPath, `${JSON.stringify(catalog)}\n`);

const manifestPath = join(dataRoot, ".manifest.json");
const original = JSON.parse(readFileSync(manifestPath, "utf8"));
const files = Object.fromEntries(
  Object.keys(original.files).map((file) => [file, readFileSync(join(dataRoot, file), "utf8")]),
);
const manifest = createModelDataManifest(readModelDataStructure(aiRoot), files, original.generatedAt);
writeFileSync(manifestPath, `${JSON.stringify(manifest)}\n`);
validateGeneratedModelData(aiRoot);
