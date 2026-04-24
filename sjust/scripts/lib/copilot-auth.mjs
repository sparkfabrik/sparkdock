// Shared authentication and HTTP helpers for GitHub Copilot API scripts.
//
// Auth resolution order (first available wins):
//   1. GitHub CLI (`gh auth token`)
//   2. OpenCode (~/.local/share/opencode/auth.json)
//
// If a token is rejected by the API (401/403), the next provider is tried
// automatically — so even if `gh` tokens don't work for a specific Copilot
// endpoint, the chain falls through to the next available token.

import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import path from "node:path";

const OPENCODE_AUTH_PATH = path.join(
  homedir(),
  ".local/share/opencode/auth.json",
);

export const BASE_HEADERS = {
  "User-Agent": "GitHubCopilotChat/0.39.0",
  "Editor-Version": "vscode/1.111.0",
  "Editor-Plugin-Version": "copilot-chat/0.39.0",
  "Copilot-Integration-Id": "vscode-chat",
  "X-GitHub-Api-Version": "2025-05-01",
};

export function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(2);
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

async function readJsonFile(filePath, warnings) {
  let raw;
  try {
    raw = await readFile(filePath, "utf8");
  } catch (err) {
    if (err.code === "ENOENT") {
      return null;
    }
    warnings.push(`Cannot read ${filePath}: ${err.message}`);
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    warnings.push(`Malformed JSON in ${filePath} — file may be corrupted`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Auth providers (each returns a token string or null)
// ---------------------------------------------------------------------------

function getGhToken() {
  try {
    const token = execFileSync("gh", ["auth", "token"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return token || null;
  } catch {
    return null;
  }
}

async function getOpenCodeToken(warnings) {
  const auth = await readJsonFile(OPENCODE_AUTH_PATH, warnings);
  if (!auth) {
    return null;
  }
  return auth?.["github-copilot"]?.access || null;
}

// ---------------------------------------------------------------------------
// Provider chain
// ---------------------------------------------------------------------------

const providers = [
  { name: "GitHub CLI (gh)", fn: getGhToken },
  { name: "OpenCode", fn: getOpenCodeToken },
];

async function resolveTokens() {
  const warnings = [];
  const tokens = [];
  for (const { name, fn } of providers) {
    const token = await fn(warnings);
    if (token) {
      tokens.push({ token, source: name });
    }
  }
  return { tokens, warnings };
}

function failNoAuth(warnings) {
  const extra =
    warnings.length > 0 ? "\n\nWarnings:\n  " + warnings.join("\n  ") : "";
  fail(
    "No Copilot authentication found.\n" +
      "Authenticate with one of the following:\n" +
      "  • GitHub CLI: run `gh auth login`\n" +
      "  • OpenCode: run opencode and sign in with GitHub Copilot" +
      extra,
  );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Returns the first available access token from the provider chain.
 */
export async function getAccessToken() {
  const { tokens, warnings } = await resolveTokens();
  if (tokens.length === 0) {
    failNoAuth(warnings);
  }
  return tokens[0].token;
}

/**
 * Fetch a URL trying each available token in priority order.
 * Falls back to the next token on 401/403 responses.
 * Set DEBUG=1 to log auth source activity to stderr.
 * @param {string} url
 * @param {Record<string, string>} headers - base headers (Authorization is added automatically)
 * @param {"token"|"Bearer"} scheme - Authorization scheme
 * @returns {Promise<Response>} the first successful response
 */
export async function fetchWithAuth(url, headers, scheme = "Bearer") {
  const debug = Boolean(process.env.DEBUG);
  const { tokens, warnings } = await resolveTokens();
  if (tokens.length === 0) {
    failNoAuth(warnings);
  }
  let lastResponse;
  for (const { token, source } of tokens) {
    const response = await fetch(url, {
      headers: { ...headers, Authorization: `${scheme} ${token}` },
    });
    if (response.status !== 401 && response.status !== 403) {
      if (debug) {
        console.error(`[copilot-auth] Token from "${source}" accepted`);
      }
      return response;
    }
    // Drain the response body to allow connection reuse before trying the next token.
    await response.text().catch((err) => {
      if (debug) {
        console.error(`[copilot-auth] Error draining response body: ${err.message}`);
      }
    });
    if (debug) {
      console.error(
        `[copilot-auth] Token from "${source}" rejected (${response.status}), trying next`,
      );
    }
    lastResponse = response;
  }
  return lastResponse;
}
