#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../sjust/libs/libshell.sh
source "${package_dir}/../../sjust/libs/libshell.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/sparkdock-swift-version.XXXXXX")"
cat > "${fixture}/swift" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_SWIFT_VERSION}"
exit "${MOCK_SWIFT_EXIT:-0}"
STUB
chmod +x "${fixture}/swift"
export PATH="${fixture}:${PATH}"

expect_version() {
    local expected="${1}" minimum="${2}" version="${3}" result=0 output
    output="$(MOCK_SWIFT_VERSION="${version}" check_swift_minimum_version "${minimum}" 2>&1)" || result=$?
    if [[ "${result}" -ne "${expected}" ]]; then
        printf 'Unexpected result for %s (minimum %s): %s\n' "${version}" "${minimum}" "${output}" >&2
        return 1
    fi
    if [[ "${expected}" -ne 0 ]]; then
        [[ "${output}" == *"${minimum}"* ]]
    fi
}
expect_version 0 6.1 'Apple Swift version 6.1.2 (swiftlang-6.1.2)'
expect_version 0 6.1 'Apple Swift version 6.2.4'
expect_version 0 6.1 'Apple Swift version 6.3.3'
expect_version 0 6.1 'Swift version 6.1'
expect_version 0 6.1 'Swift version 6.10.0'
expect_version 0 6.1 'Swift version 7.0'
expect_version 1 6.1 'Swift version 6.0'
expect_version 1 6.1 'Swift version 5.99'
expect_version 1 6.1.1 'Swift version 6.1'
expect_version 0 6.1.1 'Swift version 6.1.2'
expect_version 1 6.1 'unrecognized output'
MOCK_SWIFT_EXIT=42 expect_version 1 6.1 'compiler failed to load'
expect_version 1 invalid 'Swift version 6.1'
printf 'Swift version checks passed in %s\n' "${fixture}"
