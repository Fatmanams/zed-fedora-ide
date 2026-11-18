#!/usr/bin/env bash
# Run scripts/verify.d/*.sh in filename order and print a final summary table.
# Checks print lines in the form: PASS|FAIL|SKIP <item> <detail>

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
VERIFY_DIR="${SCRIPT_DIR}/verify.d"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="${REPO_ROOT}/logs"
LOG_FILE="${LOG_DIR}/verify-${TIMESTAMP}.log"

export REPO_ROOT

if ! mkdir -p -- "${LOG_DIR}"; then
  printf 'ERROR: cannot create log directory: %s\n' "${LOG_DIR}" >&2
  exit 1
fi

TEMP_FILE=""
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  if [[ -n "${TEMP_FILE}" ]]; then
    rm -f -- "${TEMP_FILE}"
  fi
}
trap cleanup EXIT

if ! TEMP_FILE="$(mktemp "${LOG_DIR}/.verify-step.XXXXXX")"; then
  printf 'ERROR: cannot create a temporary file under %s\n' "${LOG_DIR}" >&2
  exit 1
fi

RESULT_STATUS=()
RESULT_ITEM=()
RESULT_DETAIL=()

log_line() {
  printf '%s\n' "$*" | tee -a "${LOG_FILE}"
}

append_result() {
  local status="$1"
  local item="$2"
  local detail="${3:-}"

  case "${status}" in
    PASS | FAIL | SKIP) ;;
    *) return 1 ;;
  esac

  if [[ -z "${item}" ]]; then
    item="unnamed"
  fi

  RESULT_STATUS+=("${status}")
  RESULT_ITEM+=("${item}")
  RESULT_DETAIL+=("${detail}")
}

handle_result_line() {
  local line="$1"
  local status rest item detail

  case "${line}" in
    PASS\ * | FAIL\ * | SKIP\ *) ;;
    *) return 1 ;;
  esac

  status="${line%% *}"
  rest="${line#* }"
  item="${rest%% *}"
  if [[ "${rest}" == *" "* ]]; then
    detail="${rest#* }"
  else
    detail=""
  fi

  append_result "${status}" "${item}" "${detail}"
}

log_line "zed-fedora-ide verify"
log_line "Repository: ${REPO_ROOT}"
log_line "Started: $(date '+%Y-%m-%d %H:%M:%S %z')"
log_line "Log: ${LOG_FILE}"

restore_nullglob=0
if shopt -q nullglob; then
  restore_nullglob=1
fi
shopt -s nullglob
VERIFY_SCRIPTS=("${VERIFY_DIR}"/*.sh)
if [[ "${restore_nullglob}" == "0" ]]; then
  shopt -u nullglob
fi

if [[ ${#VERIFY_SCRIPTS[@]} -eq 0 ]]; then
  log_line ""
  log_line "No checks found in ${VERIFY_DIR}."
  append_result "SKIP" "verify" "no verify.d checks found"
fi

for script in "${VERIFY_SCRIPTS[@]}"; do
  log_line ""
  log_line "==> $(basename -- "${script}")"

  : >"${TEMP_FILE}"
  bash "${script}" >"${TEMP_FILE}" 2>&1
  script_status=$?

  result_count=0
  first_new_result=${#RESULT_STATUS[@]}
  while IFS= read -r line || [[ -n "${line}" ]]; do
    log_line "${line}"
    if handle_result_line "${line}"; then
      result_count=$((result_count + 1))
    fi
  done <"${TEMP_FILE}"

  if [[ "${script_status}" -ne 0 ]]; then
    found_fail=0
    index="${first_new_result}"
    while [[ "${index}" -lt ${#RESULT_STATUS[@]} ]]; do
      if [[ "${RESULT_STATUS[index]}" == "FAIL" ]]; then
        found_fail=1
        break
      fi
      index=$((index + 1))
    done
    if [[ "${found_fail}" -eq 0 ]]; then
      append_result "FAIL" "$(basename -- "${script}" .sh)" "exited with status ${script_status}"
    fi
  fi

  if [[ "${script_status}" -eq 0 && "${result_count}" -eq 0 ]]; then
    append_result "FAIL" "$(basename -- "${script}" .sh)" "printed no PASS/FAIL/SKIP lines"
  fi
done

fail_count=0
pass_count=0
skip_count=0
for status in "${RESULT_STATUS[@]}"; do
  case "${status}" in
    PASS) pass_count=$((pass_count + 1)) ;;
    FAIL) fail_count=$((fail_count + 1)) ;;
    SKIP) skip_count=$((skip_count + 1)) ;;
  esac
done

log_line ""
log_line "VERIFY SUMMARY"
log_line "$(printf '%-6s %-38s %s' 'STATUS' 'ITEM' 'DETAIL')"
index=0
while [[ "${index}" -lt ${#RESULT_STATUS[@]} ]]; do
  log_line "$(printf '%-6s %-38s %s' \
    "${RESULT_STATUS[index]}" "${RESULT_ITEM[index]}" "${RESULT_DETAIL[index]}")"
  index=$((index + 1))
done
log_line ""
log_line "PASS=${pass_count} FAIL=${fail_count} SKIP=${skip_count}"
log_line "Log written to ${LOG_FILE}"

if [[ "${fail_count}" -gt 0 ]]; then
  exit 1
fi
exit 0
