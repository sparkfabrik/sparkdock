// caveman — opencode plugin
//
// Provides dynamic caveman mode tracking for opencode:
// - Writes the mode flag on plugin initialization (session start)
// - Parses user messages for /caveman commands and natural-language toggles
// - Injects per-turn reinforcement into the system prompt
//
// The always-on caveman ruleset is provided separately via
// ~/.config/opencode/AGENTS.md (Tier-3 base). This plugin handles dynamic
// state only: flag writes, slash-command parsing, natural-language
// activation, and per-turn reinforcement.
//
// Compatible with opencode >=1.15.x plugin API:
// - Plugin factory for session initialization (runs once at load)
// - `chat.message` for intercepting user prompts
// - `experimental.chat.system.transform` for system prompt injection

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { existsSync, unlinkSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));

function loadConfig() {
  try { return require(join(here, 'caveman-config.cjs')); }
  catch (e) {
    if (e.code !== 'MODULE_NOT_FOUND') throw e;
    return require(join(here, '..', '..', 'hooks', 'caveman-config.js'));
  }
}
const config = loadConfig();

const { getDefaultMode, safeWriteFlag, readFlag, VALID_MODES } = config;

// Modes handled by independent skills — not selectable via /caveman <arg>.
const INDEPENDENT_MODES = new Set(['commit', 'review', 'compress']);

function opencodeConfigDir() {
  if (process.env.XDG_CONFIG_HOME) {
    return path.join(process.env.XDG_CONFIG_HOME, 'opencode');
  }
  if (process.platform === 'win32') {
    return path.join(
      process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
      'opencode'
    );
  }
  return path.join(os.homedir(), '.config', 'opencode');
}

const flagPath = path.join(opencodeConfigDir(), '.caveman-active');

function reinforcementLine(mode) {
  return 'CAVEMAN MODE ACTIVE (' + mode + '). ' +
    'Drop articles/filler/pleasantries/hedging. Fragments OK. ' +
    'Code/commits/security: write normal.';
}

// Parse a prompt for slash-command activation or natural-language toggles.
// Returns the new mode to write, the literal string 'off' to deactivate, or
// null when the prompt doesn't change state.
function parseModeChange(promptRaw) {
  const prompt = (promptRaw || '').trim().toLowerCase();
  if (!prompt) return null;

  // Natural-language deactivation — checked before activation so "stop talking
  // like caveman" doesn't trip the activation regex.
  if (/\b(stop|disable|deactivate|turn off)\b.*\bcaveman\b/i.test(prompt) ||
      /\bcaveman\b.*\b(stop|disable|deactivate|turn off)\b/i.test(prompt) ||
      /\bnormal mode\b/i.test(prompt)) {
    return 'off';
  }

  // Natural-language activation
  if (/\b(activate|enable|turn on|start|talk like)\b.*\bcaveman\b/i.test(prompt) ||
      /\bcaveman\b.*\b(mode|activate|enable|turn on|start)\b/i.test(prompt)) {
    const mode = getDefaultMode();
    return mode === 'off' ? null : mode;
  }

  // Slash-command parsing
  if (prompt.startsWith('/caveman')) {
    const parts = prompt.split(/\s+/);
    const cmd = parts[0];
    const arg = parts[1] || '';

    if (cmd === '/caveman-commit')   return 'commit';
    if (cmd === '/caveman-review')   return 'review';
    if (cmd === '/caveman-compress') return 'compress';

    if (cmd === '/caveman') {
      if (!arg)                                     return getDefaultMode();
      if (arg === 'off' || arg === 'stop' || arg === 'disable') return 'off';
      if (arg === 'wenyan-full')                    return 'wenyan';
      if (VALID_MODES.includes(arg) && !INDEPENDENT_MODES.has(arg)) return arg;
      return null;
    }
  }

  return null;
}

function applyModeChange(mode) {
  if (!mode) return;
  if (mode === 'off') {
    try { if (existsSync(flagPath)) unlinkSync(flagPath); } catch (e) {}
    return;
  }
  safeWriteFlag(flagPath, mode);
}

export const CavemanPlugin = async (_ctx) => {
  // Initialize flag at plugin load time (equivalent to session start).
  // The factory runs once per opencode session.
  const mode = getDefaultMode();
  if (mode === 'off') {
    try { if (existsSync(flagPath)) unlinkSync(flagPath); } catch (e) {}
  } else {
    safeWriteFlag(flagPath, mode);
  }

  return {
    // Intercept user messages to detect /caveman commands and
    // natural-language mode toggles.
    'chat.message': async (_input, output) => {
      if (!output || !output.parts) return;
      for (const part of output.parts) {
        if (part && part.type === 'text' && part.text) {
          const change = parseModeChange(part.text);
          if (change) applyModeChange(change);
        }
      }
    },

    // Inject reinforcement line into system prompt when caveman is active.
    // This fires before every LLM call, ensuring the model stays in mode.
    'experimental.chat.system.transform': async (_input, output) => {
      const active = readFlag(flagPath);
      if (active && !INDEPENDENT_MODES.has(active)) {
        output.system.push(reinforcementLine(active));
      }
    },
  };
};

export default CavemanPlugin;
