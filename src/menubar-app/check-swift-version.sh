#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../sjust/libs/libshell.sh
source "${package_dir}/../../sjust/libs/libshell.sh"
check_swift_minimum_version "$(cat "${package_dir}/.swift-minimum-version")"
