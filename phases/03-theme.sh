#!/usr/bin/env bash
# shellcheck shell=bash
#
# Phase 3 - theme and syntax highlighting.
#
# Applies a Tokyo Night UI with classic Monokai syntax colours through
# theme_overrides keyed by the exact Tokyo Night theme name, lists the
# tokyo-night and zedokai extensions under auto_install_extensions, enables
# rainbow brackets and semantic tokens, and adds a theme-selector keybinding.
#
# The phase is safe to run before the extensions are installed: when the theme
# JSON cannot be read, lib/theme_build.py writes a bootstrap fragment without a
# theme key, the current theme stays active, the phase logs the reason and
# returns success.
#
# Every mutating step is confirmed with ask_yes_no. Declines record SKIP and
# return success.

phase_describe() {
  printf '%s\n' "Theme and highlighting: Tokyo Night UI with Monokai syntax overrides, rainbow brackets, semantic tokens and a theme-selector keybinding"
}

# Print the native zed binary when it can be found.
phase_theme_zed_binary() {
  if have_cmd zed; then
    command -v -- zed
    return 0
  fi
  if [[ -x "${HOME}/.local/bin/zed" ]]; then
    printf '%s\n' "${HOME}/.local/bin/zed"
    return 0
  fi
  return 1
}

# phase_theme_version_at_least HAVE WANT - numeric version comparison.
phase_theme_version_at_least() {
  local have="$1"
  local want="$2"
  local lowest=""

  [[ -n "${have}" ]] || return 1
  lowest="$(printf '%s\n%s\n' "${want}" "${have}" | sort -V | head -n 1)" || return 1
  [[ "${lowest}" == "${want}" ]]
}

# Print the Zed extensions/installed root. The native data location is used
# when it already contains one of the theme extensions; otherwise the first
# candidate is returned so the phase can explain what is missing.
phase_theme_extension_root() {
  local -a candidates=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed"
    "${HOME}/.local/share/zed/extensions/installed"
    "${HOME}/.var/app/dev.zed.Zed/data/zed/extensions/installed"
  )
  local candidate=""

  for candidate in "${candidates[@]}"; do
    if [[ -d "${candidate}/tokyo-night" || -d "${candidate}/zedokai" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  printf '%s\n' "${candidates[0]}"
}

# Read one key from the `key=value` output of `theme_build.py status`.
phase_theme_status_value() {
  local key="$1"
  local output="$2"

  sed -n "s/^${key}=//p" <<<"${output}" | head -n 1
}

# Print TAB-separated `STATUS<tab>ITEM<tab>DETAIL` lines describing the live
# settings.json and keymap.json after the config merge. The item names match
# record_result.
phase_theme_live_state() {
  local settings_path="$1"
  local keymap_path="$2"
  local mode="$3"
  local semantic_expected="$4"

  python3 - "${settings_path}" "${keymap_path}" "${REPO_ROOT}/lib" \
    "${mode}" "${semantic_expected}" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
from zed_config import ConfigError, read_jsonc

settings_path = Path(sys.argv[1])
keymap_path = Path(sys.argv[2])
mode = sys.argv[4]
semantic_expected = sys.argv[5] == "1"


def emit(status, item, detail):
    print(f"{status}\t{item}\t{detail}")


settings = None
try:
    settings, _ = read_jsonc(settings_path)
except (ConfigError, OSError) as exc:
    emit("SKIP", "theme-settings", f"cannot read {settings_path}: {exc}")
if settings is not None and not isinstance(settings, dict):
    settings = None
    emit("SKIP", "theme-settings", f"{settings_path} is not a JSON object")

if settings is not None:
    if mode == "bootstrap":
        emit(
            "SKIP",
            "theme-settings",
            "bootstrap fragment: no theme key was written, the current theme stays active",
        )
    else:
        theme = settings.get("theme")
        dark = theme.get("dark") if isinstance(theme, dict) else None
        overrides = settings.get("theme_overrides")
        overrides_ok = isinstance(overrides, dict) and "Tokyo Night" in overrides
        brackets = settings.get("colorize_brackets") is True
        semantic = settings.get("semantic_tokens")
        semantic_ok = (not semantic_expected) or semantic in ("combined", "full")
        problems = []
        if dark != "Tokyo Night":
            problems.append(f"theme.dark={dark!r}")
        if not overrides_ok:
            problems.append("theme_overrides is missing")
        if not brackets:
            problems.append("colorize_brackets is not true")
        if not semantic_ok:
            problems.append(f"semantic_tokens={semantic!r}")
        if problems:
            emit(
                "SKIP",
                "theme-settings",
                "merge declined or pending: " + ", ".join(problems),
            )
        else:
            emit(
                "PASS",
                "theme-settings",
                "dark=Tokyo Night, overrides present, brackets on, "
                f"semantic={semantic or 'off'}",
            )

keys = []
try:
    keymap, _ = read_jsonc(keymap_path)
except (ConfigError, OSError) as exc:
    emit("SKIP", "theme-keybinding", f"cannot read {keymap_path}: {exc}")
else:
    if isinstance(keymap, list):
        for entry in keymap:
            if not isinstance(entry, dict):
                continue
            bindings = entry.get("bindings")
            if not isinstance(bindings, dict):
                continue
            for key, value in bindings.items():
                if isinstance(value, str):
                    action = value
                elif isinstance(value, list) and value:
                    action = value[0]
                else:
                    action = None
                if action == "theme_selector::Toggle":
                    keys.append(key)
    if keys:
        emit(
            "PASS",
            "theme-keybinding",
            f"{', '.join(keys)} -> theme_selector::Toggle",
        )
    else:
        emit(
            "SKIP",
            "theme-keybinding",
            "merge declined or pending; no theme_selector::Toggle binding",
        )
PY
}

phase_run() {
  local phase_id="${ZF_PHASE_ID:-03-theme}"
  local fragment="${REPO_ROOT}/config/settings.d/03-theme.json"
  local docs="${REPO_ROOT}/docs/THEME.md"
  local extension_root=""
  local status_output=""
  local theme_available="false"
  local monokai_available="false"
  local tokyo_themes=""
  local monokai_themes=""
  local tokyo_source=""
  local monokai_source=""
  local zed_bin=""
  local zed_version=""
  local zed_version_number=""
  local semantic_supported=0
  local generate_state=0
  local live_state=""
  local state=""
  local item=""
  local detail=""
  local -a generate_args=()

  # 1. Zed version gate for semantic_tokens.
  log_step "Theme extensions and Zed support"

  zed_bin="$(phase_theme_zed_binary || true)"
  if [[ -n "${zed_bin}" ]]; then
    if zed_version="$(timeout 20 "${zed_bin}" --version 2>&1)"; then
      zed_version="${zed_version%%$'\n'*}"
      zed_version_number="$(printf '%s\n' "${zed_version}" | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
      log_info "Installed Zed: ${zed_version}"
    else
      log_warn "Could not run ${zed_bin} --version: ${zed_version}"
      zed_version_number=""
    fi
  else
    log_warn "No native zed binary found; semantic token support cannot be verified."
    zed_version_number=""
  fi

  if phase_theme_version_at_least "${zed_version_number}" "1.27.0"; then
    semantic_supported=1
    log_info "Zed ${zed_version_number} is at or above the verified 1.27.0 baseline for semantic_tokens=combined (re-checked in 1.28.1)."
    record_result "${phase_id}" "theme-semantic-tokens" "PASS"
  else
    log_warn "Zed ${zed_version_number:-unknown} does not match the verified 1.27.0 baseline; writing no semantic_tokens key. The rest of the theme is applied unchanged."
    record_result "${phase_id}" "theme-semantic-tokens" "SKIP"
  fi

  # 2. Extension discovery. Read-only; the actual install happens on Zed's
  # next start because Zed has no verified CLI install-extension command.
  extension_root="$(phase_theme_extension_root)"
  log_info "Installed extension root: ${extension_root}"

  if status_output="$(python3 "${REPO_ROOT}/lib/theme_build.py" status \
    --installed-dir "${extension_root}" 2>&1)"; then
    theme_available="$(phase_theme_status_value theme_available "${status_output}")"
    monokai_available="$(phase_theme_status_value monokai_available "${status_output}")"
    tokyo_themes="$(phase_theme_status_value tokyo_themes "${status_output}")"
    monokai_themes="$(phase_theme_status_value monokai_themes "${status_output}")"
    tokyo_source="$(phase_theme_status_value tokyo_source "${status_output}")"
    monokai_source="$(phase_theme_status_value monokai_source "${status_output}")"
  else
    log_error "Could not inspect the installed theme extensions: ${status_output}"
    record_result "${phase_id}" "theme-extensions" "FAIL"
    record_result "${phase_id}" "theme-generate" "FAIL"
    record_result "${phase_id}" "theme-settings" "SKIP"
    record_result "${phase_id}" "theme-keybinding" "SKIP"
    return 0
  fi

  if [[ "${theme_available}" == "true" ]]; then
    log_info "Tokyo Night theme JSON: ${tokyo_source}"
    log_info "Tokyo Night themes found: ${tokyo_themes}"
  fi
  if [[ "${monokai_available}" == "true" ]]; then
    log_info "Monokai theme JSON: ${monokai_source}"
    log_info "Monokai themes found: ${monokai_themes}"
  fi

  if [[ "${theme_available}" == "true" && "${monokai_available}" == "true" ]]; then
    log_info "Both theme extensions are installed; the full fragment can be generated."
    record_result "${phase_id}" "theme-extensions" "PASS"
  else
    log_warn "Theme extension state is incomplete: Tokyo Night available=${theme_available}, Zedokai Classic available=${monokai_available}."
    log_warn "There is no verified Zed CLI command to install extensions; Zed installs auto_install_extensions on its next start."
    record_result "${phase_id}" "theme-extensions" "SKIP"
  fi

  # 3. Generate the settings fragment and the docs palette table.
  log_step "Generate the theme fragment"

  printf '  %s$ python3 lib/theme_build.py generate --fragment %q --docs %q%s\n' \
    "${_ZF_C_DIM}" "${fragment}" "${docs}" "${_ZF_C_RESET}"
  printf '  theme overrides keyed by: Tokyo Night\n'

  if ! ask_yes_no "Generate ${fragment} and refresh the palette table in ${docs}?"; then
    log_warn "Theme fragment generation skipped."
    record_result "${phase_id}" "theme-generate" "SKIP"
    record_result "${phase_id}" "theme-settings" "SKIP"
    record_result "${phase_id}" "theme-keybinding" "SKIP"
    return 0
  fi

  generate_args=(
    "${REPO_ROOT}/lib/theme_build.py" generate
    --tokyo-extension-dir "${extension_root}/tokyo-night"
    --monokai-extension-dir "${extension_root}/zedokai"
    --fragment "${fragment}"
    --docs "${docs}"
  )
  if [[ "${semantic_supported}" == "1" ]]; then
    generate_args+=(--semantic-tokens combined)
  else
    generate_args+=(--no-semantic-tokens)
  fi
  if is_dry_run; then
    generate_args+=(--dry-run)
  fi

  run python3 "${generate_args[@]}" || generate_state=$?
  if [[ "${generate_state}" -ne 0 ]]; then
    log_error "The theme generator failed with exit code ${generate_state}; the existing fragment was left in place."
    record_result "${phase_id}" "theme-generate" "FAIL"
    record_result "${phase_id}" "theme-settings" "SKIP"
    record_result "${phase_id}" "theme-keybinding" "SKIP"
    return 0
  fi
  if is_dry_run; then
    if [[ "${theme_available}" == "true" ]]; then
      log_info "dry-run: would generate the theme fragment with theme_overrides keyed by 'Tokyo Night'."
    else
      log_warn "dry-run: would generate a bootstrap theme fragment without a theme key; the current theme stays active."
    fi
  elif [[ "${theme_available}" == "true" ]]; then
    log_info "Theme fragment generated with theme_overrides keyed by 'Tokyo Night'."
  else
    log_warn "Bootstrap theme fragment generated without a theme key; the current theme stays active."
  fi
  record_result "${phase_id}" "theme-generate" "PASS"

  # 4. Merge the repository fragments into the live Zed config.
  log_step "Apply the theme settings"

  if ! apply_zed_config; then
    log_error "Applying the repository config fragments failed."
    record_result "${phase_id}" "theme-settings" "FAIL"
    record_result "${phase_id}" "theme-keybinding" "FAIL"
    return 0
  fi

  if is_dry_run; then
    log_info "dry-run: settings.json and keymap.json were not changed."
    record_result "${phase_id}" "theme-settings" "SKIP"
    record_result "${phase_id}" "theme-keybinding" "SKIP"
    return 0
  fi

  # 5. Check what actually landed in the live files, independent of whether
  # the user accepted each prompt.
  if [[ "${theme_available}" == "true" ]]; then
    live_state="$(phase_theme_live_state \
      "${ZF_ZED_CONFIG_DIR}/settings.json" \
      "${ZF_ZED_CONFIG_DIR}/keymap.json" \
      "full" "${semantic_supported}" 2>&1 || true)"
  else
    live_state="$(phase_theme_live_state \
      "${ZF_ZED_CONFIG_DIR}/settings.json" \
      "${ZF_ZED_CONFIG_DIR}/keymap.json" \
      "bootstrap" "${semantic_supported}" 2>&1 || true)"
  fi

  while IFS=$'\t' read -r state item detail; do
    if [[ -n "${state}" ]]; then
      log_info "${item}: ${detail}"
      record_result "${phase_id}" "${item}" "${state}"
    fi
  done <<<"${live_state}"

  if [[ "${theme_available}" != "true" ]]; then
    log_warn "Restart Zed so auto_install_extensions installs tokyo-night and zedokai, then run phase 3 again to write the theme_overrides key."
  elif [[ "${monokai_available}" != "true" ]]; then
    log_warn "Restart Zed to finish installing zedokai; 'Zedokai Classic' is the full Monokai alternative behind ctrl-alt-t."
  fi

  log_info "Phase ${phase_id} finished."
}
