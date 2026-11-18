#!/usr/bin/env bash
# shellcheck shell=bash
#
# lib/common.sh - shared helpers for zed-fedora-ide phases.
#
# The function names in this file are a stable API. Later phases must use these
# helpers instead of calling sudo, prompting, or writing Zed config directly.
#
# The file is meant to be sourced by install.sh after REPO_ROOT and the
# ZF_* state variables below have been set. It has no side effects other than
# defining functions and creating the log file on the first log call.

if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi

if [[ -z "${ZF_RUN_TS:-}" ]]; then
  ZF_RUN_TS="$(date +%Y%m%d-%H%M%S)"
fi
if [[ -z "${ZF_DRY_RUN:-}" ]]; then
  ZF_DRY_RUN=0
fi
if [[ -z "${ZF_ASSUME_YES:-}" ]]; then
  ZF_ASSUME_YES=0
fi
if [[ -z "${ZF_ZED_CONFIG_DIR:-}" ]]; then
  ZF_ZED_CONFIG_DIR="${HOME}/.config/zed"
fi

ZF_LOG_DIR="${REPO_ROOT}/logs"
ZF_LOG_FILE="${ZF_LOG_DIR}/install-${ZF_RUN_TS}.log"
ZF_RESULTS_FILE="${ZF_LOG_DIR}/results-${ZF_RUN_TS}.log"
ZF_BACKUP_PATH=""
_ZF_LOG_READY=0
_ZF_BACKUP_DONE=0

export REPO_ROOT ZF_RUN_TS ZF_DRY_RUN ZF_ASSUME_YES ZF_ZED_CONFIG_DIR
export ZF_LOG_DIR ZF_LOG_FILE ZF_RESULTS_FILE ZF_BACKUP_PATH

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _ZF_C_RESET=$'\033[0m'
  _ZF_C_INFO=$'\033[36m'
  _ZF_C_WARN=$'\033[33m'
  _ZF_C_ERROR=$'\033[31m'
  _ZF_C_STEP=$'\033[1;34m'
  _ZF_C_DIM=$'\033[2m'
else
  _ZF_C_RESET=""
  _ZF_C_INFO=""
  _ZF_C_WARN=""
  _ZF_C_ERROR=""
  _ZF_C_STEP=""
  _ZF_C_DIM=""
fi

_zf_ensure_log() {
  if [[ "${_ZF_LOG_READY}" == "1" ]]; then
    return 0
  fi
  if ! mkdir -p -- "${ZF_LOG_DIR}"; then
    printf 'ERROR: cannot create log directory: %s\n' "${ZF_LOG_DIR}" >&2
    return 1
  fi
  if ! printf '# zed-fedora-ide install log\n# started: %s\n# command: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S %z')" "${ZF_COMMAND:-$0}" >>"${ZF_LOG_FILE}"; then
    printf 'ERROR: cannot write log file: %s\n' "${ZF_LOG_FILE}" >&2
    return 1
  fi
  _ZF_LOG_READY=1
}

_zf_log() {
  local level="$1"
  shift
  if _zf_ensure_log; then
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "$*" >>"${ZF_LOG_FILE}"
  fi
}

log_info() {
  _zf_log INFO "$*"
  printf '%s[INFO]%s %s\n' "${_ZF_C_INFO}" "${_ZF_C_RESET}" "$*"
}

log_warn() {
  _zf_log WARN "$*"
  printf '%s[WARN]%s %s\n' "${_ZF_C_WARN}" "${_ZF_C_RESET}" "$*" >&2
}

log_error() {
  _zf_log ERROR "$*"
  printf '%s[ERROR]%s %s\n' "${_ZF_C_ERROR}" "${_ZF_C_RESET}" "$*" >&2
}

log_step() {
  _zf_log STEP "$*"
  printf '\n%s==>%s %s\n' "${_ZF_C_STEP}" "${_ZF_C_RESET}" "$*"
}

have_cmd() {
  command -v -- "$1" >/dev/null 2>&1
}

rpm_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

is_dry_run() {
  [[ "${ZF_DRY_RUN}" == "1" ]]
}

is_yes() {
  [[ "${ZF_ASSUME_YES}" == "1" ]]
}

# run CMD... - print the exact command and execute it unless in dry-run mode.
run() {
  if [[ $# -eq 0 ]]; then
    log_error "run: no command was supplied"
    return 2
  fi

  local rendered
  rendered="$(printf '%q ' "$@")"
  rendered="${rendered% }"

  printf '  %s$ %s%s\n' "${_ZF_C_DIM}" "${rendered}" "${_ZF_C_RESET}"
  _zf_log EXEC "${rendered}"

  if is_dry_run; then
    log_info "dry-run: not executing the command above"
    return 0
  fi

  "$@"
}

# ask_yes_no 'question' - default No. --yes and dry-run approve automatically.
# A non-interactive stdin/stdout is treated as No so the installer never hangs.
ask_yes_no() {
  local question="${1:-Continue?}"
  local reply

  if is_yes; then
    _zf_log ANSWER "${question} -> yes (--yes)"
    printf '  %s [auto-yes: --yes]\n' "${question}"
    return 0
  fi

  if is_dry_run; then
    _zf_log ANSWER "${question} -> yes (dry-run)"
    printf '  %s [auto-yes: dry-run]\n' "${question}"
    return 0
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    log_warn "${question} -> no (no interactive terminal; use --yes to approve)"
    return 1
  fi

  printf '%s [y/N] ' "${question}"
  if ! read -r reply; then
    log_warn "Could not read an answer; treating it as no."
    return 1
  fi

  case "${reply}" in
    y | Y | yes | YES | Yes)
      _zf_log ANSWER "${question} -> yes"
      return 0
      ;;
    *)
      _zf_log ANSWER "${question} -> no"
      return 1
      ;;
  esac
}

# step_dnf 'description' PKG... - install packages with dnf after confirmation.
# It returns 0 when the packages are already installed, when the user declines,
# or when the install succeeds. A dnf failure is returned to the caller.
step_dnf() {
  local description="${1:-Install Fedora packages}"
  if [[ $# -gt 0 ]]; then
    shift
  fi

  if [[ $# -eq 0 ]]; then
    log_error "step_dnf: no package names were supplied"
    return 2
  fi

  local -a installed=()
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    if rpm_installed "${pkg}"; then
      installed+=("${pkg}")
    else
      missing+=("${pkg}")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    log_info "SKIP: ${description} (already installed: ${installed[*]})"
    return 0
  fi

  log_step "${description}"

  local rendered_packages
  rendered_packages="$(printf '%q ' "${missing[@]}")"
  rendered_packages="${rendered_packages% }"
  printf '  %s$ sudo dnf install -y %s%s\n' "${_ZF_C_DIM}" "${rendered_packages}" "${_ZF_C_RESET}"

  if ! ask_yes_no "Install these packages with dnf?"; then
    log_warn "SKIPPED: ${description} (declined)"
    return 0
  fi

  if is_dry_run; then
    log_info "dry-run: dnf install skipped"
    return 0
  fi

  if ! have_cmd sudo; then
    log_error "sudo is required to run dnf but was not found in PATH"
    return 1
  fi

  run sudo dnf install -y "${missing[@]}"
}

# step_cmd 'description' 'check command' ACTION_FUNCTION
# The check command is trusted code from a phase file, not user input.
step_cmd() {
  local description="${1:-Run step}"
  local check="${2:-}"
  local action="${3:-}"

  if [[ -z "${check}" || -z "${action}" ]]; then
    log_error "step_cmd: description, check command and action function are required"
    return 2
  fi

  # shellcheck disable=SC2294
  if eval "${check}" >/dev/null 2>&1; then
    log_info "SKIP: ${description} (check already passes: ${check})"
    return 0
  fi

  if ! declare -F "${action}" >/dev/null 2>&1; then
    log_error "step_cmd: action is not a shell function: ${action}"
    return 2
  fi

  log_step "${description}"
  printf '  check : %s\n  action: %s\n' "${check}" "${action}"

  if ! ask_yes_no "Run this step?"; then
    log_warn "SKIPPED: ${description} (declined)"
    return 0
  fi

  if is_dry_run; then
    log_info "dry-run: would call ${action}"
    return 0
  fi

  "${action}"
}

# backup_zed_config - copy the existing Zed config once per run.
# Layout: backups/zed-<timestamp>/zed/ (the directory contains the old tree).
backup_zed_config() {
  if [[ "${_ZF_BACKUP_DONE}" == "1" ]]; then
    return 0
  fi

  local src="${ZF_ZED_CONFIG_DIR}"
  local dest="${REPO_ROOT}/backups/zed-${ZF_RUN_TS}"

  # cp -a would copy the link itself, not the config behind it, and a later
  # restore would put a stale link back. Refuse instead of faking a backup.
  if [[ -L "${src}" ]]; then
    ZF_BACKUP_PATH=""
    log_error "Zed config is a symbolic link: ${src}. Phase 1 only backs up a real directory; move the link aside or back up its target manually."
    return 1
  fi
  if [[ -e "${src}" && ! -d "${src}" ]]; then
    ZF_BACKUP_PATH=""
    log_error "Zed config path exists but is not a directory: ${src}"
    return 1
  fi
  _ZF_BACKUP_DONE=1

  if [[ ! -d "${src}" ]]; then
    ZF_BACKUP_PATH=""
    log_info "No existing Zed config at ${src}; nothing to back up."
    return 0
  fi

  if [[ -e "${dest}" ]]; then
    dest="${dest}-$$"
  fi
  ZF_BACKUP_PATH="${dest}"

  log_step "Backing up Zed config"
  printf '  %s$ cp -a %q %q%s\n' "${_ZF_C_DIM}" "${src}" "${dest}/zed" "${_ZF_C_RESET}"

  if is_dry_run; then
    log_info "dry-run: would back up ${src} to ${dest}/zed"
    return 0
  fi

  if ! mkdir -p -- "${dest}"; then
    log_error "Could not create backup directory: ${dest}"
    return 1
  fi
  if ! cp -a -- "${src}" "${dest}/zed"; then
    log_error "Could not copy ${src} to ${dest}/zed"
    return 1
  fi

  log_info "Backup written to ${dest}/zed"
}

# apply_zed_config - back up first, ask, then merge config fragments with Python.
apply_zed_config() {
  local found_fragment=0
  local candidate
  for candidate in \
    "${REPO_ROOT}"/config/settings.d/*.json \
    "${REPO_ROOT}"/config/keymap.d/*.json \
    "${REPO_ROOT}"/config/tasks.d/*.json \
    "${REPO_ROOT}"/config/snippets/*.json; do
    if [[ -e "${candidate}" ]]; then
      found_fragment=1
      break
    fi
  done

  if [[ "${found_fragment}" == "0" ]]; then
    log_info "No config fragments found in config/settings.d, keymap.d, tasks.d or snippets; nothing to apply."
    return 0
  fi

  if ! have_cmd python3; then
    log_error "python3 is required to apply Zed configuration"
    return 1
  fi

  if ! backup_zed_config; then
    log_error "Zed config was not applied because the backup failed"
    return 1
  fi

  log_step "Applying Zed configuration"
  if ! ask_yes_no "Merge repository fragments into ${ZF_ZED_CONFIG_DIR}?"; then
    log_warn "Zed configuration was not applied (declined)."
    return 0
  fi

  local -a args=(
    --config-dir "${REPO_ROOT}/config"
    --zed-dir "${ZF_ZED_CONFIG_DIR}"
  )
  if is_dry_run; then
    args+=(--dry-run)
  fi
  if is_yes; then
    args+=(--yes)
  fi

  printf '  %s$ python3 %q %s%s\n' \
    "${_ZF_C_DIM}" "${REPO_ROOT}/lib/zed_config.py" "${args[*]}" "${_ZF_C_RESET}"
  _zf_log EXEC "python3 ${REPO_ROOT}/lib/zed_config.py ${args[*]}"
  python3 "${REPO_ROOT}/lib/zed_config.py" "${args[@]}"
}

# record_result PHASE ITEM STATUS - record PASS, FAIL or SKIP for verify.sh.
record_result() {
  local phase="${1:-unknown}"
  local item="${2:-unnamed}"
  local status="${3:-}"

  status="${status^^}"
  case "${status}" in
    PASS | FAIL | SKIP) ;;
    *)
      log_error "record_result: status must be PASS, FAIL or SKIP (got '${status}')"
      return 2
      ;;
  esac

  phase="${phase//$'\t'/ }"
  phase="${phase//$'\n'/ }"
  item="${item//$'\t'/ }"
  item="${item//$'\n'/ }"

  if ! _zf_ensure_log; then
    return 1
  fi

  if ! printf '%s\t%s\t%s\t%s\n' "${status}" "${phase}" "${item}" \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" >>"${ZF_RESULTS_FILE}"; then
    log_error "Could not write phase result to ${ZF_RESULTS_FILE}"
    return 1
  fi

  _zf_log RESULT "${status} ${phase} ${item}"
  printf '  %sRESULT%s %-4s %s / %s\n' "${_ZF_C_INFO}" "${_ZF_C_RESET}" \
    "${status}" "${phase}" "${item}"
}
