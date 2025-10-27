# Chrome Web App Integration - Feature Overview

## What This Feature Does

This feature changes how URL menu items behave in the Sparkdock menu bar application.

### Before This Change

When clicking a URL menu item (like "Company Playbook"):
- The URL opened in the default browser
- Opened as a regular browser tab
- Full browser UI visible (address bar, tabs, bookmarks, etc.)
- Mixed with other browser tabs

### After This Change

When clicking a URL menu item (like "Company Playbook"):
- The URL opens in Google Chrome as a **web app**
- Opens as a **standalone window** (no browser UI)
- No address bar, no tabs, no bookmarks toolbar
- Dedicated window just for the content
- Behaves like a native application

## Visual Difference

```
┌─────────────────────────────────────────────┐
│  Regular Browser Tab (Before)               │
├─────────────────────────────────────────────┤
│ ← → ⟳  https://playbook.sparkfabrik.com/   │  ← Address bar
├─────────────────────────────────────────────┤
│ [Home] [About] [Projects] ... other tabs    │  ← Tab bar
├─────────────────────────────────────────────┤
│ ☆ Bookmarks Toolbar                         │  ← Bookmarks
├─────────────────────────────────────────────┤
│                                             │
│         Company Playbook Content            │
│                                             │
└─────────────────────────────────────────────┘
```

```
┌─────────────────────────────────────────────┐
│  Chrome Web App (After)                     │
├─────────────────────────────────────────────┤
│                                             │
│         Company Playbook Content            │  ← Just the content!
│                                             │
│                                             │
│                                             │
└─────────────────────────────────────────────┘
```

## Benefits

1. **Cleaner Interface**: No browser clutter, just the content
2. **Dedicated Space**: Each link gets its own window
3. **App-Like Experience**: Feels like a native macOS application
4. **Easy Switching**: Appears as separate app in Cmd+Tab and Mission Control
5. **Focused Work**: No distractions from other browser tabs

## How It Works

The implementation uses Chrome's built-in `--app` flag:

```bash
# Old behavior (opens in default browser with full UI)
open https://playbook.sparkfabrik.com/

# New behavior (opens as Chrome web app)
open -a "Google Chrome" --args --app=https://playbook.sparkfabrik.com/
```

## Example URLs Affected

All URL-type menu items in `menu.json` will open as web apps:

- **Company Playbook**: https://playbook.sparkfabrik.com/
- **Core Skills**: https://playbook.sparkfabrik.com/working-at-sparkfabrik/core-skills
- **Universal Definition of Done**: https://playbook.sparkfabrik.com/tools-and-policies/universal-dod

## Fallback Behavior

If Google Chrome is not available:
- Automatically falls back to the default browser
- Opens as a regular tab (same as before)
- User sees no error, just different window style
- Logs the fallback for debugging

## Inspired By

This implementation follows the pattern from Basecamp's [omarchy-launch-webapp](https://github.com/basecamp/omarchy/blob/14f803857cf9965fac0cb480b8dad345c7f0065c/bin/omarchy-launch-webapp), simplified for macOS and Chrome.

## Technical Details

- **Command**: `open -a "Google Chrome" --args --app=<URL>`
- **Requirement**: Google Chrome (pre-installed by Sparkdock)
- **Fallback**: Default browser if Chrome unavailable
- **Window Type**: Chrome app window (borderless, no browser UI)
- **Code Location**: `src/menubar-app/Sources/SparkdockManager/main.swift`
- **Function**: `openUrlAsChromeWebApp()`
