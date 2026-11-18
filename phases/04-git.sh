#!/usr/bin/env bash
# shellcheck shell=bash
#
# Phase 4 - Git and GitHub.
#
# Installs the Fedora git and gh packages, asks for a Git identity only when it
# is unset (never inventing one), applies five global Git defaults, offers the
# interactive GitHub CLI login and the gh git credential helper, offers a global
# ignore file, and merges the verified Git panel settings and Git/GitHub tasks.
#
# Every mutating action is confirmed with ask_yes_no. Declines and already
# satisfied steps record SKIP and return success. The phase never reads, prints
# or stores a GitHub token: gh auth status is used only for its exit status and
# runs with --no-refresh and telemetry disabled so the check stays read-only.

phase_describe() {
  printf '%s\n' "Git and GitHub: git/gh packages, global Git defaults, GitHub CLI login, optional global ignore file, Git panel settings and Git/GitHub tasks"
}

phase_run() {
  local phase_id="${ZF_PHASE_ID:-04-git}"

  phase_git_packages "${phase_id}"
  phase_git_identity "${phase_id}"
  phase_git_defaults "${phase_id}"
  phase_github_auth "${phase_id}"
  phase_git_ignore_file "${phase_id}"
  phase_git_config_fragments "${phase_id}"

  log_info "Phase ${phase_id} finished."
}

phase_git_packages() {
  local phase_id="$1"

  log_step "Git and GitHub CLI packages"

  step_dnf "Install git and the GitHub CLI" git gh

  if rpm_installed git; then
    log_info "git package: $(rpm -q git 2>/dev/null || true)"
    record_result "${phase_id}" "git-package" "PASS"
  else
    log_warn "git is not installed; the remaining Git steps are skipped."
    record_result "${phase_id}" "git-package" "SKIP"
  fi

  if rpm_installed gh; then
    log_info "gh package: $(rpm -q gh 2>/dev/null || true)"
    record_result "${phase_id}" "gh-package" "PASS"
  else
    log_warn "gh is not installed; the GitHub login step is skipped."
    record_result "${phase_id}" "gh-package" "SKIP"
  fi
}

phase_git_identity_present() {
  local name=""
  local email=""

  name="$(git config --global --get user.name 2>/dev/null || true)"
  email="$(git config --global --get user.email 2>/dev/null || true)"
  [[ -n "${name}" && -n "${email}" ]]
}

# Ask for one identity value only when it is unset. A dry run, --yes, or a
# non-interactive terminal leaves it unset rather than inventing a value.
phase_git_identity_value() {
  local key="$1"
  local prompt="$2"
  local current=""
  local value=""

  current="$(git config --global --get "${key}" 2>/dev/null || true)"
  if [[ -n "${current}" ]]; then
    log_info "SKIP: ${key} is already set; leaving it unchanged."
    return 0
  fi

  if is_dry_run; then
    printf '  $ git config --global %q <interactive value>\n' "${key}"
    log_info "dry-run: ${key} is unset; the phase would ask for it."
    return 0
  fi

  if is_yes || [[ ! -t 0 || ! -t 1 ]]; then
    log_warn "${key} is unset and cannot be prompted for (--yes or no interactive terminal). It is left unset; this phase never invents an identity."
    return 0
  fi

  printf '  %s (%s): ' "${prompt}" "${key}" >&2
  if ! IFS= read -r value; then
    log_warn "Could not read ${key}; leaving it unset."
    return 0
  fi

  # Trim leading and trailing whitespace without changing the value itself.
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ -z "${value}" ]]; then
    log_warn "Empty ${key}; leaving it unset."
    return 0
  fi

  run git config --global "${key}" "${value}"
}

phase_git_identity() {
  local phase_id="$1"
  local name=""
  local email=""

  log_step "Git identity"

  if ! have_cmd git; then
    log_warn "git is not available; skipping the identity step."
    record_result "${phase_id}" "git-identity" "SKIP"
    return 0
  fi

  name="$(git config --global --get user.name 2>/dev/null || true)"
  email="$(git config --global --get user.email 2>/dev/null || true)"

  if [[ -z "${name}" ]]; then
    phase_git_identity_value "user.name" "Your name for git commits"
  fi
  if [[ -z "${email}" ]]; then
    phase_git_identity_value "user.email" "Your email for git commits"
  fi

  if is_dry_run; then
    record_result "${phase_id}" "git-identity" "SKIP"
  elif phase_git_identity_present; then
    log_info "Git identity is set."
    record_result "${phase_id}" "git-identity" "PASS"
  else
    log_warn "Git identity is incomplete; commits will fail until user.name and user.email are set."
    record_result "${phase_id}" "git-identity" "SKIP"
  fi
}

phase_git_config_matches() {
  local key="$1"
  local value="$2"
  local current=""

  current="$(git config --global --get "${key}" 2>/dev/null || true)"
  [[ "${current}" == "${value}" ]]
}

phase_git_config_all_set() {
  phase_git_config_matches init.defaultBranch main &&
    phase_git_config_matches pull.rebase true &&
    phase_git_config_matches push.autoSetupRemote true &&
    phase_git_config_matches core.editor "zed --wait" &&
    phase_git_config_matches rerere.enabled true
}

# Show the git config command through run(), skip an identical existing value,
# and ask before setting a new value or replacing a different one.
phase_git_config_set() {
  local key="$1"
  local value="$2"
  local current=""
  local prompt=""

  current="$(git config --global --get "${key}" 2>/dev/null || true)"
  if [[ -n "${current}" && "${current}" == "${value}" ]]; then
    log_info "SKIP: ${key} is already '${value}'"
    return 0
  fi

  if [[ -n "${current}" ]]; then
    log_info "${key} is currently '${current}'"
    prompt="Overwrite ${key} with '${value}'?"
  else
    prompt="Set ${key} to '${value}'?"
  fi

  if ! ask_yes_no "${prompt}"; then
    if [[ -n "${current}" ]]; then
      log_warn "Left ${key} at '${current}'."
    else
      log_warn "Left ${key} unset."
    fi
    return 0
  fi

  run git config --global "${key}" "${value}"
}

phase_git_defaults() {
  local phase_id="$1"

  log_step "Git defaults"

  if ! have_cmd git; then
    log_warn "git is not available; skipping the default settings."
    record_result "${phase_id}" "git-config" "SKIP"
    return 0
  fi

  phase_git_config_set init.defaultBranch main
  phase_git_config_set pull.rebase true
  phase_git_config_set push.autoSetupRemote true
  phase_git_config_set core.editor "zed --wait"
  phase_git_config_set rerere.enabled true

  if is_dry_run; then
    record_result "${phase_id}" "git-config" "SKIP"
  elif phase_git_config_all_set; then
    log_info "The five global Git defaults are set."
    record_result "${phase_id}" "git-config" "PASS"
  else
    log_warn "Some global Git defaults are missing or different; see the prompts above."
    record_result "${phase_id}" "git-config" "SKIP"
  fi
}

# Read-only authentication probe. --no-refresh keeps the check from refreshing a
# token, and GH_TELEMETRY=false keeps gh from writing its device-id under
# ~/.local/state, so a dry run leaves the home directory untouched. Output is
# discarded because it can contain a masked token.
phase_gh_auth_status() {
  GH_TELEMETRY=false gh auth status --no-refresh
}

phase_github_auth() {
  local phase_id="$1"
  local logged_in=0

  log_step "GitHub CLI login"

  if ! have_cmd gh; then
    log_warn "gh is not available; skipping the GitHub login step."
    record_result "${phase_id}" "gh-auth" "SKIP"
    return 0
  fi

  if phase_gh_auth_status >/dev/null 2>&1; then
    logged_in=1
    log_info "SKIP: gh is already logged in. Token details are never read or printed by this phase."
  else
    log_info "No GitHub login was detected. gh auth login is interactive; you complete it yourself."
    if is_dry_run; then
      printf '  $ gh auth login\n'
      log_info "dry-run: the interactive login command was not run."
    elif is_yes || [[ ! -t 0 || ! -t 1 ]]; then
      log_info "gh auth login needs an interactive terminal; run it yourself when ready."
    elif ask_yes_no "Run gh auth login now?"; then
      if ! run gh auth login; then
        log_warn "gh auth login did not complete; the login remains unset."
      fi
    else
      log_warn "GitHub login skipped."
    fi
  fi

  if ! is_dry_run && phase_gh_auth_status >/dev/null 2>&1; then
    logged_in=1
  fi

  if [[ "${logged_in}" == "1" ]]; then
    if is_dry_run; then
      printf '  $ gh auth setup-git\n'
      log_info "dry-run: the git credential helper setup was not run."
    elif ask_yes_no "Run gh auth setup-git so git uses the GitHub CLI as its credential helper?"; then
      if ! run gh auth setup-git; then
        log_warn "gh auth setup-git failed; git keeps its current credential configuration."
      fi
    else
      log_warn "Credential helper setup skipped."
    fi
  fi

  if is_dry_run; then
    record_result "${phase_id}" "gh-auth" "SKIP"
  elif [[ "${logged_in}" == "1" ]] && phase_gh_auth_status >/dev/null 2>&1; then
    log_info "GitHub CLI authentication is available (gh auth status succeeds)."
    record_result "${phase_id}" "gh-auth" "PASS"
  else
    log_warn "GitHub CLI is not logged in. gh tasks need a working gh auth login."
    record_result "${phase_id}" "gh-auth" "SKIP"
  fi
}

phase_git_ignore_file() {
  local phase_id="$1"
  local config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
  local target="${config_home}/git/ignore"
  local source="${REPO_ROOT}/config/templates/gitignore"

  log_step "Global git ignore file"
  printf '  target: %s\n' "${target}"

  if [[ -e "${target}" || -L "${target}" ]]; then
    if [[ -f "${target}" ]] &&
      grep -Fqx -- "*.py[cod]" "${target}" &&
      grep -Fqx -- ".venv/" "${target}"; then
      log_info "SKIP: ${target} already exists with the expected patterns; it is never overwritten."
      record_result "${phase_id}" "git-ignore" "PASS"
    else
      log_warn "SKIP: ${target} already exists and was left unchanged. Review it by hand if you expected the phase-4 patterns."
      record_result "${phase_id}" "git-ignore" "SKIP"
    fi
    return 0
  fi

  if [[ ! -f "${source}" ]]; then
    log_error "The gitignore template is missing: ${source}"
    record_result "${phase_id}" "git-ignore" "FAIL"
    return 0
  fi

  log_info "Patterns cover editor files, OS metadata, build output and virtual environments."
  if ! ask_yes_no "Install ${target} from ${source}?"; then
    log_warn "Global git ignore installation skipped."
    record_result "${phase_id}" "git-ignore" "SKIP"
    return 0
  fi

  if is_dry_run; then
    printf '  $ install -D -m 0644 %q %q\n' "${source}" "${target}"
    log_info "dry-run: would install ${target}"
    record_result "${phase_id}" "git-ignore" "SKIP"
    return 0
  fi

  if ! run install -D -m 0644 -- "${source}" "${target}"; then
    log_error "Could not install ${target}"
    record_result "${phase_id}" "git-ignore" "FAIL"
    return 0
  fi

  if [[ -s "${target}" ]]; then
    log_info "Installed ${target}"
    record_result "${phase_id}" "git-ignore" "PASS"
  else
    log_error "${target} is empty after installation"
    record_result "${phase_id}" "git-ignore" "FAIL"
  fi
}

# Print TAB-separated `STATUS<tab>ITEM<tab>DETAIL` lines for the live settings
# and tasks files. The item names match record_result.
phase_git_live_state() {
  local settings_path="$1"
  local tasks_path="$2"
  local tasks_fragment="$3"

  python3 - "${settings_path}" "${tasks_path}" "${tasks_fragment}" "${REPO_ROOT}/lib" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[4])
from zed_config import ConfigError, read_jsonc


def emit(status, item, detail):
    print(f"{status}\t{item}\t{detail}")


def check_settings(path):
    try:
        settings, _ = read_jsonc(path)
    except (ConfigError, OSError) as exc:
        emit("SKIP", "git-settings", f"cannot read {path}: {exc}")
        return

    if not isinstance(settings, dict):
        emit("SKIP", "git-settings", f"{path} is not a JSON object")
        return

    git_panel = settings.get("git_panel")
    git = settings.get("git")
    dock = git_panel.get("dock") if isinstance(git_panel, dict) else None
    inline_blame = git.get("inline_blame") if isinstance(git, dict) else None
    inline_enabled = (
        inline_blame.get("enabled") if isinstance(inline_blame, dict) else None
    )
    gutter = git.get("git_gutter") if isinstance(git, dict) else None

    problems = []
    if dock != "left":
        problems.append(f"git_panel.dock={dock!r}")
    if inline_enabled is not True:
        problems.append(f"git.inline_blame.enabled={inline_enabled!r}")
    if gutter != "tracked_files":
        problems.append(f"git.git_gutter={gutter!r}")

    if problems:
        emit(
            "SKIP",
            "git-settings",
            "merge declined or pending: " + ", ".join(problems),
        )
    else:
        emit(
            "PASS",
            "git-settings",
            "git panel docked left, inline blame on, gutter diff indicators on",
        )


def check_tasks(fragment_path, live_path):
    try:
        fragment, _ = read_jsonc(fragment_path)
    except (ConfigError, OSError) as exc:
        emit("SKIP", "git-tasks", f"cannot read {fragment_path}: {exc}")
        return

    if not isinstance(fragment, list):
        emit("SKIP", "git-tasks", f"{fragment_path} is not a JSON array")
        return

    required_labels = [
        entry["label"]
        for entry in fragment
        if isinstance(entry, dict) and isinstance(entry.get("label"), str)
    ]
    if not required_labels:
        emit("SKIP", "git-tasks", f"{fragment_path} defines no task labels")
        return

    try:
        tasks, _ = read_jsonc(live_path)
    except (ConfigError, OSError) as exc:
        emit("SKIP", "git-tasks", f"cannot read {live_path}: {exc}")
        return

    if not isinstance(tasks, list):
        emit("SKIP", "git-tasks", f"{live_path} is not a JSON array")
        return

    by_label = {
        entry.get("label"): entry
        for entry in tasks
        if isinstance(entry, dict) and isinstance(entry.get("label"), str)
    }
    missing = [label for label in required_labels if label not in by_label]
    if missing:
        emit(
            "SKIP",
            "git-tasks",
            "merge declined or pending; missing labels: " + ", ".join(missing),
        )
    else:
        emit(
            "PASS",
            "git-tasks",
            f"all {len(required_labels)} Git/GitHub tasks are present",
        )


check_settings(Path(sys.argv[1]))
check_tasks(Path(sys.argv[3]), Path(sys.argv[2]))
PY
}

phase_git_config_fragments() {
  local phase_id="$1"
  local settings_file="${ZF_ZED_CONFIG_DIR}/settings.json"
  local tasks_file="${ZF_ZED_CONFIG_DIR}/tasks.json"
  local state_output=""
  local state=""
  local item=""
  local detail=""

  log_step "Git panel settings and Git/GitHub tasks"

  if [[ -L "${ZF_ZED_CONFIG_DIR}" ]]; then
    log_warn "Skipping config apply: ${ZF_ZED_CONFIG_DIR} is a symbolic link and backup_zed_config refuses to back it up. Move the link aside or merge the fragments manually."
    record_result "${phase_id}" "git-settings" "SKIP"
    record_result "${phase_id}" "git-tasks" "SKIP"
    return 0
  fi

  if ! apply_zed_config; then
    log_error "Applying the repository config fragments failed."
    record_result "${phase_id}" "git-settings" "FAIL"
    record_result "${phase_id}" "git-tasks" "FAIL"
    return 0
  fi

  if is_dry_run; then
    log_info "dry-run: settings.json and tasks.json were not changed."
    record_result "${phase_id}" "git-settings" "SKIP"
    record_result "${phase_id}" "git-tasks" "SKIP"
    return 0
  fi

  state_output="$(phase_git_live_state "${settings_file}" "${tasks_file}" "${REPO_ROOT}/config/tasks.d/04-git.json" 2>&1 || true)"
  while IFS=$'\t' read -r state item detail; do
    if [[ -n "${state}" ]]; then
      log_info "${item}: ${detail}"
      record_result "${phase_id}" "${item}" "${state}"
    fi
  done <<<"${state_output}"
}
