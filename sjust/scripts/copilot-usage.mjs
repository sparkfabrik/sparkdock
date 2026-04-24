#!/usr/bin/env node

// Fetches and displays GitHub Copilot premium usage for the authenticated user.
// Shows a formatted dashboard with visual progress bars and quota details.
//
// Usage:
//   node copilot-usage.mjs          # formatted dashboard
//   node copilot-usage.mjs --json   # raw API JSON

import { fail, fetchWithAuth, BASE_HEADERS } from "./lib/copilot-auth.mjs";
import { printBox } from "./lib/gum.mjs";

const API_URL = "https://api.github.com/copilot_internal/user";
const DAY_MS = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Data fetching
// ---------------------------------------------------------------------------

async function fetchUsage() {
  const headers = {
    ...BASE_HEADERS,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  const response = await fetchWithAuth(API_URL, headers, "token");
  if (!response.ok) {
    const body = await response.text();
    fail(
      `Copilot API returned ${response.status} ${response.statusText}\n${body}`,
    );
  }
  return response.json();
}

function fmt(value) {
  return value == null ? "-" : new Intl.NumberFormat("en-US").format(value);
}

function progressBar(used, total, width = 30) {
  const ratio = total > 0 ? Math.max(0, Math.min(used / total, 1)) : 0;
  const filled = Math.max(0, Math.min(width, Math.round(ratio * width)));
  const empty = width - filled;
  return "█".repeat(filled) + "░".repeat(empty);
}

function daysUntil(dateStr) {
  if (!dateStr) {
    return null;
  }

  const reset = new Date(dateStr);
  if (Number.isNaN(reset.getTime())) {
    return null;
  }

  const now = new Date();

  // Normalize both dates to UTC midnight so date-only API values stay stable
  // regardless of local timezone or time-of-day.
  const resetUTC = Date.UTC(
    reset.getUTCFullYear(),
    reset.getUTCMonth(),
    reset.getUTCDate(),
  );
  const nowUTC = Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  );
  const diff = (resetUTC - nowUTC) / DAY_MS;

  return diff > 0 ? diff : 0;
}

function formatDate(dateStr) {
  if (!dateStr) {
    return "-";
  }

  return dateStr.split("T")[0];
}

// ---------------------------------------------------------------------------
// Dashboard rendering
// ---------------------------------------------------------------------------

function renderQuota(snapshot) {
  if (!snapshot) {
    return "  (no data)";
  }

  if (snapshot.unlimited) {
    return "  unlimited";
  }

  const entitlement = snapshot.entitlement || 0;
  const remaining = snapshot.remaining ?? 0;
  const used = entitlement - remaining;
  const pctUsed =
    entitlement > 0 ? ((used / entitlement) * 100).toFixed(1) : "0.0";
  const bar = progressBar(used, entitlement);
  const overage = snapshot.overage_permitted ? "overage permitted" : "no overage";

  const lines = [];
  lines.push(`  [${bar}] ${pctUsed}%`);
  lines.push(`  ${fmt(used)} used / ${fmt(entitlement)} quota (${overage})`);

  if (snapshot.overage_count > 0) {
    lines.push(`  Overage requests: ${fmt(snapshot.overage_count)}`);
  }

  return lines.join("\n");
}

function renderDashboard(data) {
  const plan = data.copilot_plan || "unknown";
  const orgs = (data.organization_list || [])
    .map((o) => o.name || o.login)
    .join(", ") || "-";
  const resetDate = formatDate(data.quota_reset_date_utc || data.quota_reset_date);
  const days = daysUntil(data.quota_reset_date_utc || data.quota_reset_date);
  let daysStr = "reset date unavailable";
  if (days != null) {
    daysStr =
      days === 0
        ? "resets today"
        : `resets in ${days} day${days !== 1 ? "s" : ""}`;
  }

  const snapshots = data.quota_snapshots || {};
  const premium = snapshots.premium_interactions;
  const chat = snapshots.chat;
  const completions = snapshots.completions;

  const lines = [];
  lines.push("  GitHub Copilot Premium Usage");
  lines.push("  " + "\u2501".repeat(31));
  lines.push("");
  lines.push(`  Plan:         ${plan} (${orgs})`);
  lines.push(`  Period:       ${daysStr} (${resetDate})`);
  lines.push("");
  lines.push("  Premium Requests");
  lines.push(renderQuota(premium));
  lines.push("");

  // Chat and completions — compact single-line each
  const chatStatus = chat?.unlimited ? "unlimited" : `${fmt(chat?.entitlement || 0)} quota`;
  const compStatus = completions?.unlimited ? "unlimited" : `${fmt(completions?.entitlement || 0)} quota`;
  lines.push(`  Chat:         ${chatStatus}`);
  lines.push(`  Completions:  ${compStatus}`);

  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const doJson = process.argv.includes("--json");
  const data = await fetchUsage();

  if (doJson) {
    console.log(JSON.stringify(data, null, 2));
    process.exit(0);
  }

  const dashboard = renderDashboard(data);

  console.log("");
  printBox(dashboard);
  console.log("");
}

main().catch((error) => {
  fail(error instanceof Error ? error.stack || error.message : String(error));
});
