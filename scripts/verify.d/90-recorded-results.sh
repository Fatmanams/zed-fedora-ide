#!/usr/bin/env bash
# Report the newest phase results recorded by record_result during install.sh.

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

restore_nullglob=0
if shopt -q nullglob; then
  restore_nullglob=1
fi
shopt -s nullglob
result_files=("${REPO_ROOT}/logs"/results-*.log)
if [[ "${restore_nullglob}" == "0" ]]; then
  shopt -u nullglob
fi

if [[ ${#result_files[@]} -eq 0 ]]; then
  skip "recorded-phase-results" "no logs/results-*.log files; no phase has recorded a result yet"
  exit 0
fi

latest_index=$((${#result_files[@]} - 1))
latest="${result_files[latest_index]}"
count=0

while IFS=$'\t' read -r status phase item timestamp; do
  case "${status}" in
    PASS | FAIL | SKIP) ;;
    *) continue ;;
  esac

  if [[ -z "${phase}" ]]; then
    phase="unknown-phase"
  fi
  if [[ -z "${item}" ]]; then
    item="unnamed"
  fi

  phase="${phase// /-}"
  item="${item// /-}"
  if [[ -z "${timestamp}" ]]; then
    timestamp="recorded"
  fi

  case "${status}" in
    PASS) pass "${phase}.${item}" "recorded ${timestamp}" ;;
    FAIL) fail "${phase}.${item}" "recorded ${timestamp}" ;;
    SKIP) skip "${phase}.${item}" "recorded ${timestamp}" ;;
  esac
  count=$((count + 1))
done <"${latest}"

if [[ "${count}" -eq 0 ]]; then
  skip "recorded-phase-results" "${latest} contains no result rows"
fi
