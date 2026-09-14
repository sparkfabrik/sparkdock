#!/usr/bin/env bash
set -euo pipefail

package_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "${package_dir}"
{
    printf '%s\n' Package.swift Info.plist bundle.sh Makefile .swift-version source-fingerprint.sh
    if [[ -f Package.resolved ]]; then
        printf '%s\n' Package.resolved
    fi
    find Sources \( -type f -o -type l \)
} | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "${file}"
done | shasum -a 256 | awk '{print $1}'
