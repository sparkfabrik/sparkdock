#!/usr/bin/env bash
set -euo pipefail

package_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "${package_dir}"
required_hashes="$(shasum -a 256 Package.swift Info.plist bundle.sh Makefile .swift-minimum-version source-fingerprint.sh check-swift-version.sh)" || exit 1
lock_hash=""
if [[ -f Package.resolved ]]; then
    lock_hash="$(shasum -a 256 Package.resolved)" || exit 1
fi
source_hashes="$(find Sources \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "${file}" || exit 1
done)" || exit 1
printf '%s\n' "${required_hashes}" "${lock_hash}" "${source_hashes}" | shasum -a 256 | awk '{print $1}'
