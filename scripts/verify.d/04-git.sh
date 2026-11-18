#!/usr/bin/env bash
# Verify phase 4: the git and gh CLIs, the global Git defaults, GitHub CLI
# authentication (SKIP when not logged in), the optional global ignore file,
# the live Git panel settings and the Git/GitHub tasks fragment.
#
# Token values are never read or printed. gh auth status is used only for its
# exit status, with --no-refresh and telemetry disabled so the check stays
# read-only.

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

# Read-only check: do not refresh tokens and do not let gh write its device-id.
# Output is discarded because gh auth status can print a masked token.
gh_auth_ok() {
  GH_TELEMETRY=false gh auth status --no-refresh >/dev/null 2>&1
}

git_available=0
gh_available=0

if command -v git >/dev/null 2>&1; then
  git_available=1
  pass "git-cli" "$(git --version 2>&1 | head -n 1)"
else
  fail "git-cli" "git was not found in PATH; run ./install.sh --phase 4"
fi

if command -v gh >/dev/null 2>&1; then
  gh_available=1
  pass "gh-cli" "$(GH_TELEMETRY=false gh --version 2>&1 | head -n 1)"
else
  fail "gh-cli" "gh was not found in PATH; run ./install.sh --phase 4"
fi

if [[ "${gh_available}" == "0" ]]; then
  skip "gh-auth" "gh is not installed"
elif gh_auth_ok; then
  pass "gh-auth" "gh auth status reports a logged-in account"
else
  skip "gh-auth" "not logged in; run ./install.sh --phase 4 or gh auth login"
fi

if [[ "${git_available}" == "0" ]]; then
  skip "git-identity" "git is not installed"
else
  git_name="$(git config --global --get user.name 2>/dev/null || true)"
  git_email="$(git config --global --get user.email 2>/dev/null || true)"
  if [[ -n "${git_name}" && -n "${git_email}" ]]; then
    pass "git-identity" "user.name and user.email are set"
  elif [[ -z "${git_name}" && -z "${git_email}" ]]; then
    fail "git-identity" "user.name and user.email are unset; run ./install.sh --phase 4"
  elif [[ -z "${git_name}" ]]; then
    fail "git-identity" "user.name is unset; run ./install.sh --phase 4"
  else
    fail "git-identity" "user.email is unset; run ./install.sh --phase 4"
  fi
fi

if [[ "${git_available}" == "0" ]]; then
  skip "git-config" "git is not installed"
else
  config_keys=(
    init.defaultBranch
    pull.rebase
    push.autoSetupRemote
    core.editor
    rerere.enabled
  )
  config_values=(
    main
    true
    true
    "zed --wait"
    true
  )
  config_problems=()
  for config_index in "${!config_keys[@]}"; do
    config_key="${config_keys[config_index]}"
    config_want="${config_values[config_index]}"
    config_have="$(git config --global --get "${config_key}" 2>/dev/null || true)"
    if [[ "${config_have}" != "${config_want}" ]]; then
      config_problems+=("${config_key}=${config_have:-<unset>} (expected ${config_want})")
    fi
  done

  if [[ ${#config_problems[@]} -eq 0 ]]; then
    pass "git-config" "all five global Git defaults match"
  else
    config_detail="$(printf '%s; ' "${config_problems[@]}")"
    fail "git-config" "${config_detail%; }"
  fi
fi

ignore_file="${XDG_CONFIG_HOME:-${HOME}/.config}/git/ignore"
if [[ ! -f "${ignore_file}" ]]; then
  skip "git-ignore" "missing ${ignore_file}; the optional global ignore was not installed"
elif grep -Fqx -- "*.py[cod]" "${ignore_file}" && grep -Fqx -- ".venv/" "${ignore_file}"; then
  pass "git-ignore" "${ignore_file} contains the expected build and virtualenv patterns"
else
  fail "git-ignore" "${ignore_file} exists but is missing expected patterns; review it by hand"
fi

settings_file="${HOME}/.config/zed/settings.json"
if [[ ! -f "${settings_file}" ]]; then
  skip "git-settings" "missing ${settings_file}; run ./install.sh --phase 4"
elif settings_detail="$(python3 - "${settings_file}" "${REPO_ROOT}/lib" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
from zed_config import ConfigError, read_jsonc

try:
    settings, _ = read_jsonc(Path(sys.argv[1]))
except ConfigError as exc:
    print(str(exc).replace("\n", " "))
    raise SystemExit(1)

if not isinstance(settings, dict):
    print("top level is not a JSON object")
    raise SystemExit(1)

git_panel = settings.get("git_panel")
git = settings.get("git")
dock = git_panel.get("dock") if isinstance(git_panel, dict) else None
inline_blame = git.get("inline_blame") if isinstance(git, dict) else None
inline_enabled = inline_blame.get("enabled") if isinstance(inline_blame, dict) else None
gutter = git.get("git_gutter") if isinstance(git, dict) else None

problems = []
if dock != "left":
    problems.append(f"git_panel.dock={dock!r} (expected 'left')")
if inline_enabled is not True:
    problems.append(f"git.inline_blame.enabled={inline_enabled!r} (expected true)")
if gutter != "tracked_files":
    problems.append(f"git.git_gutter={gutter!r} (expected 'tracked_files')")

if problems:
    print("; ".join(problems))
    raise SystemExit(1)

print("git panel docked left, inline blame on, gutter diff indicators on")
PY
)"; then
  pass "git-settings" "${settings_detail}"
else
  fail "git-settings" "${settings_detail:-settings.json does not contain the phase-4 Git settings}"
fi

tasks_fragment="${REPO_ROOT}/config/tasks.d/04-git.json"
required_tasks=(
  "Git: status"
  "Git: log graph (30)"
  "Git: pull --rebase"
  "Git: push"
  "Git: new branch"
  "GitHub: create PR (web)"
  "GitHub: view PR (web)"
  "GitHub: view repository (web)"
  "GitHub: workflow runs"
)

if [[ ! -f "${tasks_fragment}" ]]; then
  fail "git-tasks-fragment" "missing ${tasks_fragment}"
elif tasks_detail="$(python3 - "${tasks_fragment}" "${REPO_ROOT}/lib" "${required_tasks[@]}" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
from zed_config import ConfigError, read_jsonc

path = Path(sys.argv[1])
required = sys.argv[3:]

try:
    tasks, _ = read_jsonc(path)
except ConfigError as exc:
    print(str(exc).replace("\n", " "))
    raise SystemExit(1)

if not isinstance(tasks, list):
    print("top level is not a JSON array")
    raise SystemExit(1)

by_label = {}
problems = []
for entry in tasks:
    if not isinstance(entry, dict):
        problems.append("a task entry is not a JSON object")
        continue
    label = entry.get("label")
    if not isinstance(label, str) or not label:
        problems.append("a task entry has no non-empty label")
        continue
    by_label[label] = entry
    command = entry.get("command")
    if not isinstance(command, str) or not command:
        problems.append(f"{label}: command is missing")
    args = entry.get("args", [])
    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        problems.append(f"{label}: args is not a list of strings")
    if entry.get("use_new_terminal") is not False:
        problems.append(f"{label}: use_new_terminal is not false")
    if entry.get("reveal") != "always":
        problems.append(f"{label}: reveal is not 'always'")

for label in required:
    if label not in by_label:
        problems.append(f"missing task: {label}")

branch_task = by_label.get("Git: new branch")
if branch_task is not None:
    branch_args = branch_task.get("args", [])
    if not any("read" in arg for arg in branch_args if isinstance(arg, str)):
        problems.append("Git: new branch does not contain a shell read prompt")

if problems:
    print("; ".join(problems))
    raise SystemExit(1)

print(f"{len(required)} required tasks have label, command, args, use_new_terminal=false and reveal=always")
PY
)"; then
  pass "git-tasks-fragment" "${tasks_detail}"
else
  fail "git-tasks-fragment" "${tasks_detail:-tasks fragment is invalid}"
fi

live_tasks="${HOME}/.config/zed/tasks.json"
if [[ ! -f "${live_tasks}" ]]; then
  skip "git-tasks" "missing ${live_tasks}; run ./install.sh --phase 4"
elif tasks_detail="$(python3 - "${live_tasks}" "${REPO_ROOT}/lib" "${required_tasks[@]}" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
from zed_config import ConfigError, read_jsonc

path = Path(sys.argv[1])
required = sys.argv[3:]

try:
    tasks, _ = read_jsonc(path)
except ConfigError as exc:
    print(str(exc).replace("\n", " "))
    raise SystemExit(1)

if not isinstance(tasks, list):
    print("top level is not a JSON array")
    raise SystemExit(1)

by_label = {
    entry.get("label"): entry
    for entry in tasks
    if isinstance(entry, dict) and isinstance(entry.get("label"), str)
}
missing = [label for label in required if label not in by_label]
if missing:
    print("missing: " + ", ".join(missing))
    raise SystemExit(1)

print(f"all {len(required)} required Git/GitHub tasks are present")
PY
)"; then
  pass "git-tasks" "${tasks_detail}"
else
  fail "git-tasks" "${tasks_detail:-tasks.json is missing required phase-4 tasks}"
fi

exit 0
