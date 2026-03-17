#!/usr/bin/env node

// Fetches Copilot model context/output limits from the GitHub Copilot Business API
// and compares them against the deployed opencode.json configuration.
//
// Temporary workaround until opencode syncs limits from the API automatically.
// Refs:
//   https://github.com/anomalyco/models.dev/issues/1136
//   https://github.com/anomalyco/opencode/issues/16129

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";

const AUTH_PATH = path.join(homedir(), ".local/share/opencode/auth.json");
const OPENCODE_JSON_PATH = path.join(homedir(), ".config/opencode/opencode.json");
const API_BASE = "https://api.business.githubcopilot.com";

const BASE_HEADERS = {
  "User-Agent": "GitHubCopilotChat/0.39.0",
  "Editor-Version": "vscode/1.111.0",
  "Editor-Plugin-Version": "copilot-chat/0.39.0",
  "Copilot-Integration-Id": "vscode-chat",
  "X-GitHub-Api-Version": "2025-05-01",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(2);
}

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

async function getAccessToken() {
  let raw;
  try {
    raw = await readFile(AUTH_PATH, "utf8");
  } catch {
    fail(
      `Cannot read ${AUTH_PATH}\nMake sure opencode is installed and authenticated with GitHub Copilot.`
    );
  }
  const token = JSON.parse(raw)?.["github-copilot"]?.access;
  if (!token) fail(`No github-copilot access token found in ${AUTH_PATH}`);
  return token;
}

async function fetchModels(accessToken) {
  const headers = { ...BASE_HEADERS, Authorization: `Bearer ${accessToken}` };
  const response = await fetch(`${API_BASE}/models`, { headers });
  if (!response.ok) {
    const body = await response.text();
    fail(
      `Copilot Business API returned ${response.status} ${response.statusText}\n${body}`
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
      return {
        id: m.id,
        prompt,
        output,
        window,
        promptPlusOutput: prompt != null && output != null ? prompt + output : null,
        context: inferContext(limits),
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
  const config = JSON.parse(raw);
  return config?.provider?.["github-copilot"]?.models || null;
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

function compare(apiModels, localModels) {
  const warnings = [];

  if (!localModels) {
    warnings.push({
      type: "INFO",
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

function printTable(apiModels) {
  console.table(
    apiModels.map((r) => ({
      id: r.id,
      prompt: fmt(r.prompt),
      output: fmt(r.output),
      window: fmt(r.window),
      "prompt+output": fmt(r.promptPlusOutput),
      "inferred context": fmt(r.context),
    }))
  );
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
      `  ${w.type.padEnd(maxType)}  ${w.id.padEnd(maxId)}  ${w.message}`
    );
  }
}

function printSnippet(apiModels) {
  const models = {};
  for (const m of apiModels) {
    if (m.context == null || m.output == null) continue;
    models[m.id] = { limit: { context: m.context, output: m.output } };
  }
  console.log("\n--- opencode.json provider snippet ---\n");
  console.log(
    JSON.stringify({ provider: { "github-copilot": { models } } }, null, 2)
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const accessToken = await getAccessToken();
  const payload = await fetchModels(accessToken);
  const apiModels = buildApiModels(payload);
  const localModels = await readLocalLimits();

  console.log(`API endpoint: ${API_BASE}`);
  console.log(`Local config: ${OPENCODE_JSON_PATH}\n`);

  printTable(apiModels);

  const warnings = compare(apiModels, localModels);
  printWarnings(warnings);

  const hasDrift = warnings.some(
    (w) => w.type === "DRIFT" || w.type === "MISSING" || w.type === "STALE"
  );

  if (hasDrift) {
    printSnippet(apiModels);
    console.log(
      "\nUpdate the provider.github-copilot.models block in opencode.json with the snippet above."
    );
  }

  process.exit(hasDrift ? 1 : 0);
}

main().catch((error) => {
  fail(error instanceof Error ? error.stack || error.message : String(error));
});
