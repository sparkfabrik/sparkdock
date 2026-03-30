// Shared authentication and HTTP helpers for GitHub Copilot API scripts.

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";

export const AUTH_PATH = path.join(
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

export async function getAccessToken() {
  let raw;
  try {
    raw = await readFile(AUTH_PATH, "utf8");
  } catch {
    fail(
      `Cannot read ${AUTH_PATH}\nMake sure opencode is installed and authenticated with GitHub Copilot.`,
    );
  }
  let auth;
  try {
    auth = JSON.parse(raw);
  } catch {
    fail(`Invalid JSON in ${AUTH_PATH} — the auth file may be corrupted.`);
  }
  const token = auth?.["github-copilot"]?.access;
  if (!token) fail(`No github-copilot access token found in ${AUTH_PATH}`);
  return token;
}
