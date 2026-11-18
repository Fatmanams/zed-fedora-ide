#!/usr/bin/env bash
# Verify the config engine against its fixtures and a check-only run.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)}"

pass() {
  printf 'PASS %s %s\n' "$1" "$2"
}

fail() {
  printf 'FAIL %s %s\n' "$1" "$2"
}

test_file="${REPO_ROOT}/config/templates/test/test_zed_config.py"
if output="$(python3 "${test_file}" 2>&1)"; then
  pass "config-tests" "all zed_config JSONC, merge and safety tests passed"
else
  printf '%s\n' "${output}" >&2
  detail="$(printf '%s\n' "${output}" | tail -n 1)"
  if [[ -z "${detail}" ]]; then
    detail="test suite failed"
  fi
  fail "config-tests" "${detail}"
fi

temporary_directory="$(mktemp -d)" || {
  fail "config-check" "could not create a temporary directory"
  exit 0
}
check_target="${temporary_directory}/zed"
if python3 "${REPO_ROOT}/lib/zed_config.py" \
  --check \
  --config-dir "${REPO_ROOT}/config" \
  --zed-dir "${check_target}" >/dev/null 2>&1; then
  if [[ ! -e "${check_target}" ]]; then
    pass "config-check" "--check validated the repository fragments and created nothing"
  else
    fail "config-check" "--check created the target directory"
  fi
else
  fail "config-check" "--check failed on the repository config fragments"
fi
rm -rf -- "${temporary_directory}"
