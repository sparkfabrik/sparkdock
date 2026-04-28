#!/usr/bin/env node

// Fetches Copilot model context/output limits from the GitHub Copilot Business API
// and compares them against the deployed opencode.json configuration.
//
// Temporary workaround until opencode syncs limits from the API automatically.
// Refs:
//   https://github.com/anomalyco/models.dev/issues/1136
//   https://github.com/anomalyco/opencode/issues/16129

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import path, { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { fail, fetchWithAuth, BASE_HEADERS } from "./lib/copilot-auth.mjs";
import { printTable } from "./lib/gum.mjs";

const OPENCODE_JSON_PATH = path.join(
  homedir(),
  ".config/opencode/opencode.json",
);
const SOURCE_CONFIG_PATH = path.resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "config",
  "macos",
  "opencode.json",
);
const API_BASE = "https://api.business.githubcopilot.com";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function parseNumber(value) {
  return typeof value === "number" ? value : null;
}

function fmt(value) {
  return value == null ? "-" : new Intl.NumberFormat("en-US").format(value);
}

function inferContext(limits) {
  const prompt = parseNumber(limits.max_prompt_tokens);
  const output = parseNumber(limits.max_output_tokens);
  const window = parseNumber(limits.max_context_window_tokens);
  const sum = prompt != null && output != null ? prompt + output : null;
  if (window != null && sum != null) return Math.min(window, sum);
  return window ?? sum;
}

// ---------------------------------------------------------------------------
// Data fetching
// ---------------------------------------------------------------------------

async function fetchModels() {
  const headers = { ...BASE_HEADERS };
  const response = await fetchWithAuth(`${API_BASE}/models`, headers, "Bearer");
  if (!response.ok) {
    const body = await response.text();
    fail(
      `Copilot Business API returned ${response.status} ${response.statusText}\n${body}`,
    );
  }
  return response.json();
}

function buildApiModels(payload) {
  return (payload.data || [])
    .filter((m) => m?.model_picker_enabled)
    .map((m) => {
      const limits = m?.capabilities?.limits || {};
      const prompt = parseNumber(limits.max_prompt_tokens);
      const output = parseNumber(limits.max_output_tokens);
      const window = parseNumber(limits.max_context_window_tokens);
      const multiplier = m?.billing?.multiplier ?? null;
      const premium = m?.billing?.is_premium ?? false;
      return {
        id: m.id,
        prompt,
        output,
        window,
        promptPlusOutput:
          prompt != null && output != null ? prompt + output : null,
        context: inferContext(limits),
        multiplier,
        premium,
      };
    })
    .sort((a, b) => a.id.localeCompare(b.id));
}

// ---------------------------------------------------------------------------
// Local config reading
// ---------------------------------------------------------------------------

async function readLocalLimits() {
  let raw;
  try {
    raw = await readFile(OPENCODE_JSON_PATH, "utf8");
  } catch {
    return null;
  }
  let config;
  try {
    config = JSON.parse(raw);
  } catch {
    fail(
      `Invalid JSON in ${OPENCODE_JSON_PATH} — the config file may be corrupted.`,
    );
  }
  return config?.provider?.["github-copilot"]?.models || null;
}

// ---------------------------------------------------------------------------
// Update support
// ---------------------------------------------------------------------------

function buildModelsBlock(apiModels) {
  const models = {};
  for (const m of apiModels) {
    if (m.context == null || m.output == null) continue;
    models[m.id] = { limit: { context: m.context, output: m.output } };
  }
  return models;
}

async function updateLocalConfig(modelsBlock) {
  let raw;
  let source = OPENCODE_JSON_PATH;

  try {
    raw = await readFile(OPENCODE_JSON_PATH, "utf8");
  } catch (err) {
    if (err.code !== "ENOENT") {
      fail(`Cannot read ${OPENCODE_JSON_PATH}: ${err.message}`);
    }
    // File doesn't exist — seed from sparkdock source config
    source = SOURCE_CONFIG_PATH;
    try {
      raw = await readFile(SOURCE_CONFIG_PATH, "utf8");
    } catch {
      fail(
        `Cannot read ${OPENCODE_JSON_PATH} or ${SOURCE_CONFIG_PATH}\n` +
          "The sparkdock installation may be incomplete.",
      );
    }
  }

  let config;
  try {
    config = JSON.parse(raw);
  } catch {
    fail(`Invalid JSON in ${source} — the config file may be corrupted.`);
  }

  // Deep-set provider.github-copilot.models, creating intermediate keys if needed
  if (!config.provider) config.provider = {};
  if (!config.provider["github-copilot"])
    config.provider["github-copilot"] = {};
  config.provider["github-copilot"].models = modelsBlock;

  await mkdir(dirname(OPENCODE_JSON_PATH), { recursive: true });
  await writeFile(OPENCODE_JSON_PATH, JSON.stringify(config, null, 2) + "\n");

  const count = Object.keys(modelsBlock).length;
  if (source !== OPENCODE_JSON_PATH) {
    console.log(`\nSeeded from ${source}`);
  }
  console.log(`Updated ${count} models in ${OPENCODE_JSON_PATH}`);
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

function compare(apiModels, localModels) {
  const warnings = [];

  if (!localModels) {
    warnings.push({
      type: "MISSING",
      id: "-",
      message: `No provider.github-copilot.models found in ${OPENCODE_JSON_PATH}`,
    });
    return warnings;
  }

  const localIds = new Set(Object.keys(localModels));
  const apiIds = new Set(apiModels.map((m) => m.id));

  for (const model of apiModels) {
    if (model.context == null) continue;

    const local = localModels[model.id];
    if (!local) {
      warnings.push({
        type: "MISSING",
        id: model.id,
        message: `not in opencode.json (api: context=${fmt(model.context)}, output=${fmt(model.output)})`,
      });
      continue;
    }

    const localContext = local?.limit?.context;
    const localOutput = local?.limit?.output;

    if (localContext !== model.context) {
      warnings.push({
        type: "DRIFT",
        id: model.id,
        message: `context: ${fmt(localContext)} (file) -> ${fmt(model.context)} (api)`,
      });
    }
    if (localOutput !== model.output) {
      warnings.push({
        type: "DRIFT",
        id: model.id,
        message: `output: ${fmt(localOutput)} (file) -> ${fmt(model.output)} (api)`,
      });
    }
  }

  for (const id of localIds) {
    if (!apiIds.has(id)) {
      warnings.push({
        type: "STALE",
        id,
        message: "in opencode.json but no longer in the Copilot API",
      });
    }
  }

  return warnings;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

function splitModels(apiModels) {
  const included = apiModels
    .filter((m) => !m.premium)
    .sort((a, b) => a.id.localeCompare(b.id));
  const premium = apiModels
    .filter((m) => m.premium)
    .sort((a, b) => (a.multiplier ?? 0) - (b.multiplier ?? 0) || a.id.localeCompare(b.id));
  return { included, premium };
}

function toRow(r) {
  return [
    r.id,
    r.multiplier != null ? `${r.multiplier}x` : "-",
    fmt(r.prompt),
    fmt(r.output),
    fmt(r.window),
    fmt(r.promptPlusOutput),
    fmt(r.context),
  ].join("\t");
}

function printModelsTable(apiModels) {
  const { included, premium } = splitModels(apiModels);
  const header =
    "Model\tMultiplier\tPrompt\tOutput\tWindow\tPrompt+Output\tContext";

  if (included.length) {
    console.log("\n📦 Included models (0x)\n");
    const csv = [header, ...included.map(toRow)].join("\n");
    printTable(csv);
  }

  if (premium.length) {
    console.log("\n💎 Premium models (by multiplier)\n");
    const csv = [header, ...premium.map(toRow)].join("\n");
    printTable(csv);
  }
}

function printWarnings(warnings) {
  if (warnings.length === 0) {
    console.log("\nAll models match the current opencode.json configuration.");
    return;
  }

  console.log("\n--- Warnings ---\n");
  const maxType = Math.max(...warnings.map((w) => w.type.length));
  const maxId = Math.max(...warnings.map((w) => w.id.length));
  for (const w of warnings) {
    console.log(
      `  ${w.type.padEnd(maxType)}  ${w.id.padEnd(maxId)}  ${w.message}`,
    );
  }
}

function printSnippet(modelsBlock) {
  console.log("\n--- opencode.json provider snippet ---\n");
  console.log(
    JSON.stringify(
      { provider: { "github-copilot": { models: modelsBlock } } },
      null,
      2,
    ),
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const doUpdate = process.argv.includes("--update");
  const doList = process.argv.includes("--list");
  const payload = await fetchModels();
  const apiModels = buildApiModels(payload);

  if (doList) {
    const { included, premium } = splitModels(apiModels);
    const listHeader = "Model\tMultiplier\tContext";

    if (included.length) {
      console.log("\n📦 Included models (0x)\n");
      const rows = included.map((m) => `${m.id}\t-\t${fmt(m.context)}`);
      const csv = [listHeader, ...rows].join("\n");
      printTable(csv);
    }
    if (premium.length) {
      console.log("\n💎 Premium models (by multiplier)\n");
      const rows = premium.map(
        (m) => `${m.id}\t${m.multiplier}x\t${fmt(m.context)}`,
      );
      const csv = [listHeader, ...rows].join("\n");
      printTable(csv);
    }
    process.exit(0);
  }

  const localModels = await readLocalLimits();

  console.log(`API endpoint: ${API_BASE}`);
  console.log(`Local config: ${OPENCODE_JSON_PATH}\n`);

  printModelsTable(apiModels);

  const warnings = compare(apiModels, localModels);
  printWarnings(warnings);

  const hasDrift = warnings.some(
    (w) => w.type === "DRIFT" || w.type === "MISSING" || w.type === "STALE",
  );

  if (hasDrift) {
    const modelsBlock = buildModelsBlock(apiModels);

    if (doUpdate) {
      await updateLocalConfig(modelsBlock);
    } else {
      printSnippet(modelsBlock);
      console.log(
        "\nRun with --update to apply automatically, or copy the snippet above into opencode.json.",
      );
    }
  }

  process.exit(hasDrift && !doUpdate ? 1 : 0);
}

main().catch((error) => {
  fail(error instanceof Error ? error.stack || error.message : String(error));
});
