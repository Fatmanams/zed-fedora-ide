#!/usr/bin/env bash
# Verify the required repository layout and static syntax.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)}"

pass() {
  printf 'PASS %s %s\n' "$1" "$2"
}

fail() {
  printf 'FAIL %s %s\n' "$1" "$2"
}

required_paths=(
  "Makefile"
  "README.md"
  ".gitignore"
  "install.sh"
  "lib/common.sh"
  "lib/zed_config.py"
  "phases/00-template.sh.example"
  "config/settings.d"
  "config/keymap.d"
  "config/tasks.d"
  "config/snippets"
  "config/templates"
  "config/templates/test/sample.jsonc"
  "config/templates/test/test_zed_config.py"
  "scripts/verify.sh"
  "scripts/verify.d"
  "docs/ASSUMPTIONS.md"
  "logs"
  "backups"
)

missing=()
for path in "${required_paths[@]}"; do
  if [[ ! -e "${REPO_ROOT}/${path}" ]]; then
    missing+=("${path}")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  pass "repo-layout" "all required files and directories are present"
else
  fail "repo-layout" "missing: ${missing[*]}"
fi

not_executable=()
for path in "install.sh" "scripts/verify.sh"; do
  if [[ ! -x "${REPO_ROOT}/${path}" ]]; then
    not_executable+=("${path}")
  fi
done

if [[ ${#not_executable[@]} -eq 0 ]]; then
  pass "executables" "install.sh and scripts/verify.sh are executable"
else
  fail "executables" "not executable: ${not_executable[*]}"
fi

restore_nullglob=0
if shopt -q nullglob; then
  restore_nullglob=1
fi
shopt -s nullglob
shell_files=(
  "${REPO_ROOT}/install.sh"
  "${REPO_ROOT}/lib"/*.sh
  "${REPO_ROOT}/phases"/*.sh
  "${REPO_ROOT}/phases"/*.sh.example
  "${REPO_ROOT}/scripts"/*.sh
  "${REPO_ROOT}/scripts/verify.d"/*.sh
)
if [[ "${restore_nullglob}" == "0" ]]; then
  shopt -u nullglob
fi

syntax_failures=()
for file in "${shell_files[@]}"; do
  if ! bash -n "${file}" 2>/dev/null; then
    syntax_failures+=("$(basename -- "${file}")")
  fi
done

if [[ ${#syntax_failures[@]} -eq 0 ]]; then
  pass "shell-syntax" "${#shell_files[@]} shell file(s) pass bash -n"
else
  fail "shell-syntax" "bash -n failed: ${syntax_failures[*]}"
fi

if python3 - "${REPO_ROOT}/lib/zed_config.py" "${REPO_ROOT}/config/templates/test/test_zed_config.py" <<'PY' >/dev/null 2>&1
import ast
import sys

for filename in sys.argv[1:]:
    with open(filename, encoding="utf-8") as handle:
        ast.parse(handle.read(), filename=filename)
PY
then
  pass "python-syntax" "lib/zed_config.py and its test parse"
else
  fail "python-syntax" "python syntax check failed"
fi

template="${REPO_ROOT}/phases/00-template.sh.example"
if grep -q '^phase_describe()' "${template}" && grep -q '^phase_run()' "${template}"; then
  pass "phase-template" "defines phase_describe and phase_run"
else
  fail "phase-template" "missing phase_describe or phase_run"
fi

if [[ -f "${REPO_ROOT}/logs/.gitkeep" && -f "${REPO_ROOT}/backups/.gitkeep" ]]; then
  pass "ignored-dirs" "logs/ and backups/ are present and gitignored"
else
  fail "ignored-dirs" "logs/.gitkeep or backups/.gitkeep is missing"
fi
