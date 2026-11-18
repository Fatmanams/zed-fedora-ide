#!/usr/bin/env bash
# Verify the phase 2 base setup: native Zed, the Nerd Font, .editorconfig and
# the applied Zed settings.

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

zed_bin=""
if command -v zed >/dev/null 2>&1; then
  zed_bin="$(command -v zed)"
elif [[ -x "${HOME}/.local/bin/zed" ]]; then
  zed_bin="${HOME}/.local/bin/zed"
fi

if [[ -z "${zed_bin}" ]]; then
  flatpak_apps=""
  if command -v flatpak >/dev/null 2>&1; then
    flatpak_cache="$(mktemp -d "${TMPDIR:-/tmp}/zf-flatpak.XXXXXX" 2>/dev/null || true)"
    if [[ -n "${flatpak_cache}" ]]; then
      flatpak_apps="$(XDG_CACHE_HOME="${flatpak_cache}" flatpak list --system --app --columns=application 2>/dev/null || true)"
      if [[ -d "${HOME}/.local/share/flatpak" ]]; then
        flatpak_apps+=$'\n'
        flatpak_apps+="$(XDG_CACHE_HOME="${flatpak_cache}" flatpak list --user --app --columns=application 2>/dev/null || true)"
      fi
      rm -rf -- "${flatpak_cache:?}"
    else
      flatpak_apps="$(flatpak list --system --app --columns=application 2>/dev/null || true)"
      if [[ -d "${HOME}/.local/share/flatpak" ]]; then
        flatpak_apps+=$'\n'
        flatpak_apps+="$(flatpak list --user --app --columns=application 2>/dev/null || true)"
      fi
    fi
  fi
  if [[ "${flatpak_apps}" == *"dev.zed.Zed"* ]]; then
    fail "zed-binary" "native zed not found; Flatpak dev.zed.Zed is installed"
  else
    fail "zed-binary" "native zed was not found in PATH or ${HOME}/.local/bin/zed"
  fi
else
  pass "zed-binary" "${zed_bin}"
  if version_output="$(timeout 20 "${zed_bin}" --version 2>&1)"; then
    version_line="${version_output%%$'\n'*}"
    pass "zed-version" "${version_line}"
  else
    version_line="${version_output%%$'\n'*}"
    fail "zed-version" "${version_line:-${zed_bin} --version failed}"
  fi
fi

case ":${PATH}:" in
  *":${HOME}/.local/bin:"*)
    pass "local-bin-path" "${HOME}/.local/bin is on PATH"
    ;;
  *)
    skip "local-bin-path" "${HOME}/.local/bin is not on PATH in this shell; restart your shell"
    ;;
esac

if ! command -v fc-list >/dev/null 2>&1; then
  fail "nerd-font" "fc-list was not found; fontconfig is required"
else
  font_list="$(fc-list : family 2>/dev/null || true)"
  if [[ "${font_list,,}" == *"jetbrainsmono nerd font"* ]]; then
    pass "nerd-font" "JetBrainsMono Nerd Font is visible to fontconfig"
  else
    fail "nerd-font" "JetBrainsMono Nerd Font is not listed by fc-list"
  fi
fi

settings_file="${HOME}/.config/zed/settings.json"
settings_ok=0

if [[ ! -f "${settings_file}" ]]; then
  fail "settings-json" "missing ${settings_file}"
else
  settings_detail=""
  if settings_detail="$(python3 - "${settings_file}" "${REPO_ROOT}/lib" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[2])
from zed_config import ConfigError, read_jsonc

try:
    data, _ = read_jsonc(Path(sys.argv[1]))
except ConfigError as exc:
    print(str(exc).replace("\n", " "))
    raise SystemExit(1)

if not isinstance(data, dict):
    print("top level is not a JSON object")
    raise SystemExit(1)

print("valid JSONC object")
PY
  )"; then
    pass "settings-json" "${settings_detail}"
    settings_ok=1
  else
    fail "settings-json" "${settings_detail:-could not parse settings.json}"
  fi
fi

if [[ "${settings_ok}" == "1" ]]; then
  fragment="${REPO_ROOT}/config/settings.d/02-base.json"
  if [[ ! -f "${fragment}" ]]; then
    fail "base-settings" "fragment is missing: ${fragment}"
  else
    settings_detail=""
    if settings_detail="$(python3 - "${settings_file}" "${fragment}" "${REPO_ROOT}/lib" <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[3])
from zed_config import ConfigError, read_jsonc


def missing_paths(existing, overlay, prefix=""):
    if isinstance(overlay, dict):
        if not isinstance(existing, dict):
            return [prefix or "<root>"]
        problems = []
        for key, value in overlay.items():
            child = f"{prefix}.{key}" if prefix else key
            if key not in existing:
                problems.append(child)
            else:
                problems.extend(missing_paths(existing[key], value, child))
        return problems
    return [] if existing == overlay else [prefix or "<root>"]


def count_leaves(value):
    if isinstance(value, dict):
        return sum(count_leaves(child) for child in value.values())
    return 1


try:
    existing, _ = read_jsonc(Path(sys.argv[1]))
    overlay, _ = read_jsonc(Path(sys.argv[2]))
except ConfigError as exc:
    print(str(exc).replace("\n", " "))
    raise SystemExit(1)

problems = missing_paths(existing, overlay)
if problems:
    print("missing or different: " + ", ".join(problems))
    raise SystemExit(1)

print(f"all {count_leaves(overlay)} base settings match")
PY
    )"; then
      pass "base-settings" "${settings_detail}"
    else
      fail "base-settings" "${settings_detail:-base settings do not match}"
    fi
  fi
else
  skip "base-settings" "settings.json is missing or invalid"
fi

editorconfig="${HOME}/.editorconfig"
if [[ ! -f "${editorconfig}" ]]; then
  skip "editorconfig" "not installed; run ./install.sh --phase 2"
else
  required_lines=(
    "root = true"
    "charset = utf-8"
    "end_of_line = lf"
    "insert_final_newline = true"
    "trim_trailing_whitespace = true"
    "indent_style = space"
    "indent_size = 4"
    "[*.{js,ts,json,yaml,yml,md}]"
    "indent_size = 2"
    "[Makefile]"
    "[*.go]"
    "indent_style = tab"
  )
  missing_lines=()
  for line in "${required_lines[@]}"; do
    if ! grep -Fqx -- "${line}" "${editorconfig}"; then
      missing_lines+=("${line}")
    fi
  done
  if [[ ${#missing_lines[@]} -eq 0 ]]; then
    pass "editorconfig" "required EditorConfig properties are present"
  else
    joined="$(printf '%s; ' "${missing_lines[@]}")"
    fail "editorconfig" "missing: ${joined%; }"
  fi
fi

if [[ -L "${settings_file}" ]]; then
  stow_target="$(readlink -f -- "${settings_file}" 2>/dev/null || readlink -- "${settings_file}" 2>/dev/null || true)"
  pass "dotfiles-stow" "settings.json is a symlink to ${stow_target:-an unresolved target}"
else
  skip "dotfiles-stow" "settings.json is a regular file; optional stow hookup not detected"
fi
