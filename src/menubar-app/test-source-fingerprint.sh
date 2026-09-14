#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/sparkdock-fingerprint.XXXXXX")"
mkdir -p "${fixture}/Sources/Resources" "${fixture}/.build"
for name in Package.swift Info.plist bundle.sh Makefile .swift-minimum-version source-fingerprint.sh check-swift-version.sh Sources/main.swift 'Sources/Resources/logo image.png'; do
    printf 'original\n' > "${fixture}/${name}"
done
fingerprint() {
    "${package_dir}/source-fingerprint.sh" "${fixture}"
}
original="$(fingerprint)"
[[ "${original}" =~ ^[0-9a-f]{64}$ ]]
for name in Package.swift Info.plist bundle.sh Makefile .swift-minimum-version source-fingerprint.sh check-swift-version.sh Sources/main.swift 'Sources/Resources/logo image.png'; do
    printf 'changed\n' > "${fixture}/${name}"
    [[ "$(fingerprint)" != "${original}" ]]
    printf 'original\n' > "${fixture}/${name}"
    [[ "$(fingerprint)" == "${original}" ]]
done
touch "${fixture}/Sources/main.swift"
printf 'ignored\n' > "${fixture}/.build/output"
[[ "$(fingerprint)" == "${original}" ]]
mv "${fixture}/Sources/main.swift" "${fixture}/Sources/renamed.swift"
[[ "$(fingerprint)" != "${original}" ]]
mv "${fixture}/Sources/renamed.swift" "${fixture}/Sources/main.swift"
mv "${fixture}/Sources/Resources/logo image.png" "${fixture}/saved-logo"
[[ "$(fingerprint)" != "${original}" ]]
mv "${fixture}/saved-logo" "${fixture}/Sources/Resources/logo image.png"
printf 'dependencies\n' > "${fixture}/Package.resolved"
[[ "$(fingerprint)" != "${original}" ]]
for name in Package.swift Info.plist bundle.sh Makefile .swift-minimum-version source-fingerprint.sh check-swift-version.sh; do
    mv "${fixture}/${name}" "${fixture}/saved-input"
    if output="$(fingerprint 2>/dev/null)"; then
        printf 'Missing required input did not fail fingerprinting: %s\n' "${name}" >&2
        exit 1
    fi
    [[ -z "${output}" ]]
    mv "${fixture}/saved-input" "${fixture}/${name}"
done
printf 'Fingerprint checks passed in %s\n' "${fixture}"
