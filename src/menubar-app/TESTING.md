# Manual Testing Guide for Chrome Web App Integration

This guide describes how to test the Chrome web app integration feature on macOS.

## Prerequisites

- macOS system with Sparkdock installed
- Google Chrome installed (should be pre-installed by Sparkdock)
- Menu bar app built and installed

## Test Cases

### Test 1: Basic Chrome Web App Launch

**Steps:**
1. Click on the Sparkdock menu bar icon
2. Navigate to the "Company" section
3. Click on "Company Playbook"

**Expected Result:**
- A new Chrome window opens as a web app (standalone window without browser toolbar)
- The URL https://playbook.sparkfabrik.com/ loads
- The window has no address bar or Chrome UI elements
- The window shows only the website content

### Test 2: Multiple Web App Instances

**Steps:**
1. Click on the Sparkdock menu bar icon
2. Click on "Company Playbook"
3. Click on the Sparkdock menu bar icon again
4. Click on "Core Skills"

**Expected Result:**
- Two separate Chrome web app windows open
- Each has its own standalone window
- Both windows remain open simultaneously

### Test 3: Fallback to Default Browser

**Note:** This test is optional and more safely tested in a VM or test environment.

**Steps:**
1. Quit Google Chrome completely
2. In a test environment, temporarily rename Chrome: `sudo mv "/Applications/Google Chrome.app" "/Applications/Google Chrome.app.backup"`
3. Click on the Sparkdock menu bar icon
4. Click on "Company Playbook"

**Expected Result:**
- The URL opens in the default browser (Safari, Firefox, etc.)
- Check Console.app for log message: "Fell back to default browser for URL: https://playbook.sparkfabrik.com/"

**Cleanup:**
1. Restore Chrome: `sudo mv "/Applications/Google Chrome.app.backup" "/Applications/Google Chrome.app"`

**Alternative Test (Safer):**
- Test fallback behavior by checking the error handling code path in Console.app logs when Chrome is unavailable

### Test 4: Command Type Menu Items Still Work

**Steps:**
1. Click on the Sparkdock menu bar icon
2. Navigate to the "Tools" section
3. Click on "Open sjust"

**Expected Result:**
- A Ghostty terminal window opens running the sjust command
- This should work the same as before (no regression)

### Test 5: Log Verification

**Steps:**
1. Open Console.app
2. Filter for process "sparkdock-manager"
3. Click on a URL menu item (e.g., "Company Playbook")
4. Check the logs

**Expected Result:**
- Log entry appears: "Opened URL as Chrome web app: https://playbook.sparkfabrik.com/"
- No error messages appear

## Verification Checklist

- [ ] URL items open in Chrome as web apps (standalone windows)
- [ ] Web app windows have no browser UI (no address bar, tabs, etc.)
- [ ] Multiple web app instances can be opened simultaneously
- [ ] Fallback to default browser works if Chrome is unavailable
- [ ] Command type menu items continue to work correctly
- [ ] Appropriate log messages appear in Console.app
- [ ] No crashes or errors occur

## Known Limitations

- Only Google Chrome is used for web apps (by design)
- If Chrome is not installed, falls back to default browser (not as a web app)
- No support for other Chromium-based browsers (by design for simplicity)

## Debugging

If web apps don't open correctly:

1. Check if Chrome is installed: `test -d "/Applications/Google Chrome.app" && echo "Chrome is installed" || echo "Chrome not found"`
2. Check Console.app for error messages from sparkdock-manager
3. Verify the menu.json file has correct URL entries
4. Try the exact command used by the app: `/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --app=https://playbook.sparkfabrik.com/`

## Reference

The implementation follows the pattern from [omarchy-launch-webapp](https://github.com/basecamp/omarchy/blob/14f803857cf9965fac0cb480b8dad345c7f0065c/bin/omarchy-launch-webapp), simplified for macOS and Chrome.
