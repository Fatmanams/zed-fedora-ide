#!/usr/bin/env bash
# Verify the base tooling required by the foundation.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)}"

pass() {
  printf 'PASS %s %s\n' "$1" "$2"
}

fail() {
  printf 'FAIL %s %s\n' "$1" "$2"
}

skip() {
  printf 'SKIP %s %s\n' "$1" "$2"
}

if [[ "${BASH_VERSINFO[0]}" -ge 5 ]]; then
  pass "bash-version" "${BASH_VERSION}"
else
  fail "bash-version" "bash 5 or newer is required (found ${BASH_VERSION})"
fi

if [[ -r /etc/os-release ]]; then
  os_id=""
  while IFS='=' read -r key value; do
    if [[ "${key}" == "ID" ]]; then
      os_id="${value//\"/}"
      break
    fi
  done < /etc/os-release
  if [[ "${os_id}" == "fedora" ]]; then
    pass "fedora" "ID=fedora"
  else
    fail "fedora" "expected ID=fedora (found ${os_id:-unknown})"
  fi
else
  fail "fedora" "/etc/os-release is not readable"
fi

machine="$(uname -m)"
if [[ "${machine}" == "x86_64" ]]; then
  pass "x86_64" "architecture is x86_64"
else
  fail "x86_64" "expected x86_64 (found ${machine})"
fi

if command -v python3 >/dev/null 2>&1; then
  python_version="$(python3 --version 2>&1)" || python_version="python3 (unknown version)"
  if python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
    pass "python3" "${python_version}"
  else
    fail "python3" "python 3.8 or newer is required (found ${python_version})"
  fi
else
  fail "python3" "python3 was not found in PATH"
fi

if command -v dnf >/dev/null 2>&1; then
  pass "dnf" "$(command -v dnf)"
else
  fail "dnf" "dnf was not found in PATH"
fi

if command -v rpm >/dev/null 2>&1; then
  pass "rpm" "$(command -v rpm)"
else
  fail "rpm" "rpm was not found in PATH"
fi

if command -v sudo >/dev/null 2>&1; then
  pass "sudo" "$(command -v sudo)"
else
  skip "sudo" "not found; dnf steps in later phases will not be able to install packages"
fi

if command -v shellcheck >/dev/null 2>&1; then
  pass "shellcheck" "$(command -v shellcheck)"
else
  skip "shellcheck" "not installed; make lint still runs bash -n"
fi

if [[ -d "${REPO_ROOT}" ]]; then
  pass "repo-root" "${REPO_ROOT}"
else
  fail "repo-root" "repository root does not exist: ${REPO_ROOT}"
fi
