#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/sparkdock-bundle-test.XXXXXX")"
app="${fixture_dir}/Sparkdock Manager.app"
executable="${app}/Contents/MacOS/sparkdock-manager"
resources="${app}/Contents/Resources"

ditto "${package_dir}/.build/Sparkdock Manager.app" "${app}"
codesign --verify --strict "${app}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Contents/Info.plist")" == "com.sparkfabrik.sparkdock.menubar" ]]
[[ -f "${resources}/menu.json" && -f "${resources}/sparkfabrik-logo.png" ]]
"${executable}" --status
ln -s "${executable}" "${fixture_dir}/sparkdock-manager"
output="$("${fixture_dir}/sparkdock-manager" --status)"
printf '%s\n' "${output}"
[[ "${output}" == *"Bundle identifier: com.sparkfabrik.sparkdock.menubar"* ]]

expect_resource_failure() {
    local executable_path="${1}" result=0 output
    output="$("${executable_path}" --status)" || result=$?
    if [[ "${result}" -ne 1 || "${output}" != *"Status: ERROR"* ]]; then
        printf 'Expected resource validation failure, got exit %s: %s\n' "${result}" "${output}" >&2
        return 1
    fi
}

# Missing or corrupt bundle resources must not fall back to embedded bytes.
for name in menu.json sparkfabrik-logo.png; do
    mv "${resources}/${name}" "${fixture_dir}/${name}"
    expect_resource_failure "${executable}"
    expect_resource_failure "${fixture_dir}/sparkdock-manager"
    printf 'invalid resource' > "${resources}/${name}"
    expect_resource_failure "${executable}"
    expect_resource_failure "${fixture_dir}/sparkdock-manager"
    mv "${fixture_dir}/${name}" "${resources}/${name}"
done
codesign --verify --strict "${app}"
printf 'Bundle checks passed in %s\n' "${fixture_dir}"

# Exported provisioning trees must build metadata without a Git checkout.
export_dir="${fixture_dir}/export"
mkdir -p "${export_dir}/.build/release" "${export_dir}/Sources/SparkdockManager"
cp "${package_dir}/bundle.sh" "${package_dir}/Info.plist" "${export_dir}/"
cp "${app}/Contents/MacOS/sparkdock-manager" "${export_dir}/.build/release/"
cp -R "${package_dir}/Sources/SparkdockManager/Resources" "${export_dir}/Sources/SparkdockManager/"
env -u BUNDLE_VERSION -u BUNDLE_REVISION "${export_dir}/bundle.sh"
export_plist="${export_dir}/.build/Sparkdock Manager.app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${export_plist}")" == 0.0.0 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SparkdockRevision' "${export_plist}")" == unknown ]]
BUNDLE_VERSION=1.2.3 BUNDLE_REVISION=export-test "${export_dir}/bundle.sh"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${export_plist}")" == 1.2.3 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SparkdockRevision' "${export_plist}")" == export-test ]]
printf 'Exported bundle metadata checks passed\n'
