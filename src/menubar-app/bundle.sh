#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
configuration="${1:-release}"
app="${package_dir}/.build/Sparkdock Manager.app"
identifier="${BUNDLE_IDENTIFIER:-com.sparkfabrik.sparkdock.menubar}"
version="${BUNDLE_VERSION:-0.0.$(git -C "${package_dir}" rev-list --count HEAD 2>/dev/null || printf 0)}"
revision="${BUNDLE_REVISION:-$(git -C "${package_dir}" rev-parse HEAD 2>/dev/null || printf unknown)}"

mkdir -p "${app}/Contents/MacOS" "${app}/Contents/Resources"
cp "${package_dir}/.build/${configuration}/sparkdock-manager" "${app}/Contents/MacOS/sparkdock-manager"
cp "${package_dir}/Info.plist" "${app}/Contents/Info.plist"
cp "${package_dir}/Sources/SparkdockManager/Resources/menu.json" "${app}/Contents/Resources/"
cp "${package_dir}/Sources/SparkdockManager/Resources/sparkfabrik-logo.png" "${app}/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${identifier}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${version}" "${app}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SparkdockRevision string ${revision}" "${app}/Contents/Info.plist"
codesign --force --sign - --identifier "${identifier}" "${app}"
codesign --verify --strict "${app}"
printf '%s\n' "${app}"
