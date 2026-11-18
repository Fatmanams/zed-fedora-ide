#!/usr/bin/env bash
# zed-fedora-ide installer.
#
# Fedora Linux x86_64 only. Every mutating step asks first, logs, and supports
# --dry-run. Never run this whole script as root; sudo is used only by dnf.

set -Eeuo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${SCRIPT_DIR}"
ZF_COMMAND="${0} $*"
export REPO_ROOT ZF_COMMAND

DRY_RUN=0
ASSUME_YES=0
DO_LIST=0
DO_RESTORE=0
RESTORE_DIR=""
PHASE_FILTER=""
PHASE_FILTER_SET=0

declare -a PHASE_FILES=()
declare -A PHASE_SELECTED=()

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Fedora Linux x86_64 installer for the zed-fedora-ide foundation.

Options:
  --dry-run              Show planned commands and config diffs; change nothing.
  --yes, -y              Approve every prompt. Also allows changed snippets to
                         be overwritten without a per-file question.
  --phase N[,M]          Run only phases with these numeric prefixes (for
                         example: --phase 2 or --phase 2,4).
  --list                 List available phase scripts and exit.
  --restore [BACKUP_DIR] Restore a backup made by this installer. Without a
                         directory, use the newest backups/zed-* directory.
  --help, -h             Show this help and exit.

Notes:
  - Dry-run auto-approves prompts so it can run unattended, but helpers print
    commands and skip every mutating action.
  - The installer backs up ~/.config/zed before the first config write.
  - Logs: logs/install-<timestamp>.log
EOF
}

die() {
  if declare -F log_error >/dev/null 2>&1; then
    log_error "$*"
  else
    printf 'ERROR: %s\n' "$*" >&2
  fi
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --yes | -y)
      ASSUME_YES=1
      ;;
    --phase)
      if [[ $# -lt 2 ]]; then
        printf 'ERROR: --phase requires an argument\n' >&2
        usage >&2
        exit 2
      fi
      PHASE_FILTER="$2"
      PHASE_FILTER_SET=1
      shift
      ;;
    --phase=*)
      PHASE_FILTER="${1#*=}"
      PHASE_FILTER_SET=1
      ;;
    --list)
      DO_LIST=1
      ;;
    --restore)
      DO_RESTORE=1
      if [[ $# -ge 2 && "$2" != -* ]]; then
        RESTORE_DIR="$2"
        shift
      fi
      ;;
    --restore=*)
      DO_RESTORE=1
      RESTORE_DIR="${1#*=}"
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

ZF_DRY_RUN="${DRY_RUN}"
ZF_ASSUME_YES="${ASSUME_YES}"
export ZF_DRY_RUN ZF_ASSUME_YES

# shellcheck disable=SC1091
source "${REPO_ROOT}/lib/common.sh"

_on_error() {
  local exit_code="$1"
  local line_number="$2"
  local function_name="$3"
  local failed_command="$4"

  trap - ERR
  log_error "Installer failed (exit ${exit_code}) at ${function_name}, line ${line_number}: ${failed_command}"
  log_error "Full log: ${ZF_LOG_FILE}"
  exit "${exit_code}"
}
trap '_on_error "$?" "${BASH_LINENO[0]}" "${FUNCNAME[0]:-main}" "$BASH_COMMAND"' ERR

check_platform() {
  if [[ ! -r /etc/os-release ]]; then
    die "Cannot read /etc/os-release; this installer targets Fedora Linux."
  fi

  local key value
  local os_id=""
  while IFS='=' read -r key value; do
    if [[ "${key}" == "ID" ]]; then
      os_id="${value//\"/}"
      os_id="${os_id//\'/}"
      break
    fi
  done < /etc/os-release

  if [[ "${os_id}" != "fedora" ]]; then
    die "Unsupported distribution (ID=${os_id:-unknown}). This installer only supports Fedora Linux."
  fi

  local machine
  machine="$(uname -m)"
  if [[ "${machine}" != "x86_64" ]]; then
    die "Unsupported architecture (${machine}). This installer only supports x86_64."
  fi
}

check_not_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    die "Do not run this installer as root. Run it as your normal user; it uses sudo only for dnf."
  fi
}

check_requirements() {
  if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
    die "bash 5 or newer is required (found ${BASH_VERSION})."
  fi
  if ! have_cmd python3; then
    die "python3 is required but was not found in PATH."
  fi
  if ! have_cmd dnf; then
    die "dnf is required but was not found in PATH."
  fi
  if ! have_cmd rpm; then
    die "rpm is required but was not found in PATH."
  fi
  if ! have_cmd sudo; then
    log_warn "sudo was not found in PATH; dnf install steps will fail if a phase needs packages."
  fi
}

collect_phase_files() {
  local restore_nullglob=0
  if shopt -q nullglob; then
    restore_nullglob=1
  fi
  shopt -s nullglob
  PHASE_FILES=("${REPO_ROOT}/phases"/[0-9][0-9]-*.sh)
  if [[ "${restore_nullglob}" == "0" ]]; then
    shopt -u nullglob
  fi
}

phase_selected() {
  local file="$1"
  local number

  if [[ "${PHASE_FILTER_SET}" -eq 0 ]]; then
    return 0
  fi

  number="$(basename -- "${file}")"
  number="${number%%-*}"
  [[ "${PHASE_SELECTED[$((10#${number}))]:-0}" == "1" ]]
}

parse_phase_filter() {
  if [[ "${PHASE_FILTER_SET}" -eq 0 ]]; then
    return 0
  fi
  if [[ -z "${PHASE_FILTER}" ]]; then
    die "--phase needs a non-empty comma-separated list of numeric prefixes."
  fi

  local -a tokens=()
  local token number
  IFS=',' read -r -a tokens <<<"${PHASE_FILTER}"
  for token in "${tokens[@]}"; do
    token="${token//[[:space:]]/}"
    if [[ ! "${token}" =~ ^[0-9]{1,3}$ ]]; then
      die "Invalid phase number '${token}'. Use numeric prefixes such as 2 or 2,4."
    fi
    number=$((10#${token}))
    PHASE_SELECTED["${number}"]=1
  done
}

list_phases() {
  collect_phase_files

  if [[ ${#PHASE_FILES[@]} -eq 0 ]]; then
    printf 'No phases found in %s/phases.\n' "${REPO_ROOT}"
    printf 'The foundation is installed; add phases/NN-name.sh files for later phases.\n'
    return 0
  fi

  printf '%-26s %s\n' "PHASE" "DESCRIPTION"
  local file description
  for file in "${PHASE_FILES[@]}"; do
    description="$(
      # shellcheck disable=SC1090
      source "${file}" >/dev/null 2>&1
      if declare -F phase_describe >/dev/null 2>&1; then
        phase_describe
      else
        printf 'ERROR: phase_describe is missing'
      fi
    )" || description="ERROR: could not load phase"
    printf '%-26s %s\n' "$(basename -- "${file}" .sh)" "${description}"
  done
}

run_phases() {
  collect_phase_files

  if [[ ${#PHASE_FILES[@]} -eq 0 ]]; then
    if [[ "${PHASE_FILTER_SET}" -eq 1 ]]; then
      die "No phase scripts exist, so --phase ${PHASE_FILTER} cannot match anything."
    fi
    log_warn "No phase scripts found in ${REPO_ROOT}/phases (foundation only)."
    log_info "Nothing to install. Add phases/NN-name.sh files for later phases."
    return 0
  fi

  local selected=0
  local file phase_id description
  for file in "${PHASE_FILES[@]}"; do
    if ! phase_selected "${file}"; then
      continue
    fi
    selected=$((selected + 1))
    phase_id="$(basename -- "${file}" .sh)"

    # shellcheck disable=SC1090
    source "${file}"
    if ! declare -F phase_describe >/dev/null 2>&1; then
      die "Phase ${phase_id} does not define phase_describe."
    fi
    if ! declare -F phase_run >/dev/null 2>&1; then
      die "Phase ${phase_id} does not define phase_run."
    fi

    description="$(phase_describe)"
    printf '\nPhase %s\n  %s\n' "${phase_id}" "${description}"

    if ! ask_yes_no "Run phase ${phase_id}?"; then
      log_warn "Phase ${phase_id} skipped."
      record_result "${phase_id}" "phase" "SKIP" "declined by user"
      unset -f phase_describe phase_run
      continue
    fi

    export ZF_PHASE_ID="${phase_id}"
    log_step "Running phase ${phase_id}: ${description}"
    phase_run
    unset -f phase_describe phase_run
    unset ZF_PHASE_ID
  done

  if [[ "${selected}" -eq 0 ]]; then
    die "No phases matched --phase ${PHASE_FILTER}."
  fi
}

latest_backup_dir() {
  local restore_nullglob=0
  if shopt -q nullglob; then
    restore_nullglob=1
  fi
  shopt -s nullglob
  local -a candidates=("${REPO_ROOT}/backups"/zed-*)
  if [[ "${restore_nullglob}" == "0" ]]; then
    shopt -u nullglob
  fi

  local latest=""
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "${candidate}" ]]; then
      latest="${candidate}"
    fi
  done

  [[ -n "${latest}" ]] || return 1
  printf '%s\n' "${latest}"
}

restore_zed_config() {
  local backup_dir=""
  local target="${ZF_ZED_CONFIG_DIR}"

  if [[ -n "${RESTORE_DIR}" ]]; then
    if [[ ! -d "${RESTORE_DIR}" ]]; then
      die "Backup directory does not exist: ${RESTORE_DIR}"
    fi
    backup_dir="$(cd -- "${RESTORE_DIR}" && pwd -P)" || die "Cannot access ${RESTORE_DIR}"
  else
    if ! backup_dir="$(latest_backup_dir)"; then
      die "No backups found under ${REPO_ROOT}/backups. Pass --restore BACKUP_DIR or run the installer with config fragments first."
    fi
  fi

  local source_dir
  if [[ -d "${backup_dir}/zed" ]]; then
    source_dir="${backup_dir}/zed"
  else
    source_dir="${backup_dir}"
  fi

  local restore_nullglob=0
  if shopt -q nullglob; then
    restore_nullglob=1
  fi
  shopt -s nullglob
  local -a entries=("${source_dir}"/*)
  if [[ "${restore_nullglob}" == "0" ]]; then
    shopt -u nullglob
  fi
  if [[ ${#entries[@]} -eq 0 ]]; then
    die "Backup looks empty and was not restored: ${source_dir}"
  fi

  log_step "Restoring Zed configuration"
  printf '  backup: %s\n  target: %s\n' "${source_dir}" "${target}"

  if ! ask_yes_no "Restore this backup? The current Zed config will be moved aside first."; then
    log_warn "Restore cancelled."
    return 0
  fi

  local pre_restore="${REPO_ROOT}/backups/pre-restore-${ZF_RUN_TS}"
  if [[ -e "${pre_restore}" ]]; then
    pre_restore="${pre_restore}-$$"
  fi

  local target_parent="."
  if [[ "${target}" == */* ]]; then
    target_parent="${target%/*}"
  fi
  run mkdir -p -- "${target_parent}"

  if [[ -e "${target}" || -L "${target}" ]]; then
    run mkdir -p -- "${pre_restore}"
    run mv -- "${target}" "${pre_restore}/zed"
  fi

  run cp -a -- "${source_dir}" "${target}"

  if is_dry_run; then
    log_info "dry-run: restore was not performed."
  else
    log_info "Restored ${source_dir} to ${target}."
    log_info "Start or reload Zed to pick up the restored configuration."
  fi
}

main() {
  check_platform

  if [[ "${DO_LIST}" -eq 1 ]]; then
    if [[ "${DO_RESTORE}" -eq 1 || "${PHASE_FILTER_SET}" -eq 1 ]]; then
      die "--list cannot be combined with --restore or --phase."
    fi
    list_phases
    return 0
  fi

  if [[ "${DO_RESTORE}" -eq 1 && "${PHASE_FILTER_SET}" -eq 1 ]]; then
    die "--restore cannot be combined with --phase."
  fi

  check_not_root

  log_info "zed-fedora-ide installer"
  log_info "Repository: ${REPO_ROOT}"
  log_info "Zed config: ${ZF_ZED_CONFIG_DIR}"
  if is_dry_run; then
    log_warn "Dry-run mode: no installs, backups, config writes or snippet overwrites will be made."
  fi
  log_info "Log file: ${ZF_LOG_FILE}"

  if [[ "${DO_RESTORE}" -eq 1 ]]; then
    restore_zed_config
    log_info "Done."
    return 0
  fi

  check_requirements
  parse_phase_filter
  run_phases

  if [[ -f "${ZF_RESULTS_FILE}" ]]; then
    log_info "Phase results: ${ZF_RESULTS_FILE}"
    if grep -q '^FAIL' "${ZF_RESULTS_FILE}"; then
      log_warn "One or more phase items recorded FAIL; run ./scripts/verify.sh for the summary."
    fi
  fi
  log_info "Done. Next: ./scripts/verify.sh"
}

main "$@"
