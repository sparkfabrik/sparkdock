# Xcode License Error Handling

This document describes the enhanced error handling for Xcode license issues in the Sparkdock menubar app.

## Problem

When running `brew outdated` commands, if the Xcode license has not been accepted, brew fails with an error message like:

```
Error: You have not agreed to the Xcode license. Please resolve this by running:
  sudo xcodebuild -license accept
```

Previously, the menubar app treated this as a generic failure and returned 0 (no updates), causing the UI to show green "up to date" status even when there were actually updates available.

## Solution

The enhanced error handling now:

1. **Detects License Errors**: Captures stderr output and checks for specific Xcode license error messages
2. **Tracks License State**: Maintains a separate `hasBrewLicenseError` state
3. **Updates UI Appropriately**: Shows red error status instead of green "up to date"
4. **Provides User Guidance**: Menu items show actionable instructions

## Behavior Changes

### Status Display
- **Before**: Green "Brew packages: up to date" (incorrect)
- **After**: Red "Brew packages: License error - run 'sudo xcodebuild -license accept'" (correct)

### Menu Bar Icon
- **Before**: Gray template icon (indicating no updates)
- **After**: Orange/red icon (indicating attention needed)

### Tooltip
- **Before**: "Sparkdock - Up to date"
- **After**: "Sparkdock - Brew license error, ..."

### Menu Items
- **Before**: "Upgrade Brew Packages" menu item hidden
- **After**: "Fix Xcode License (run 'sudo xcodebuild -license accept')" menu item visible but disabled

## Error Detection

The app detects Xcode license errors by checking if stderr contains:
- "You have not agreed to the Xcode license"
- "xcodebuild -license accept"

## Logging

License errors are logged at ERROR level with the full error message for debugging.

## User Experience

Users now receive clear visual indication when the Xcode license needs to be accepted, along with the exact command to run to fix the issue.