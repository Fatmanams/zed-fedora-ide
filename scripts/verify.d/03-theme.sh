#!/usr/bin/env bash
# Verify the phase 3 theme setup: the Tokyo Night and Monokai extensions are
# installed, the theme overrides parse and use valid hex colours, the palette
# table has no contrast failures, and the live settings select an installed
# theme. The colour and JSONC checks live in lib/theme_build.py check.

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

fragment="${REPO_ROOT}/config/settings.d/03-theme.json"
docs="${REPO_ROOT}/docs/THEME.md"
keymap="${REPO_ROOT}/config/keymap.d/03-theme.json"
helper="${REPO_ROOT}/lib/theme_build.py"

settings="${HOME}/.config/zed/settings.json"
live_keymap="${HOME}/.config/zed/keymap.json"

# Look for the installed extension root without hardcoding one guessed path.
native_root="${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed"
extension_root=""
for candidate in \
  "${native_root}" \
  "${HOME}/.local/share/zed/extensions/installed" \
  "${HOME}/.var/app/dev.zed.Zed/data/zed/extensions/installed"; do
  if [[ -d "${candidate}/tokyo-night" || -d "${candidate}/zedokai" ]]; then
    extension_root="${candidate}"
    break
  fi
done

if [[ -n "${extension_root}" ]]; then
  if [[ -d "${extension_root}/tokyo-night" ]]; then
    pass "theme-tokyo-extension" "${extension_root}/tokyo-night"
  else
    fail "theme-tokyo-extension" "missing ${extension_root}/tokyo-night; run phase 3 and start Zed"
  fi
  if [[ -d "${extension_root}/zedokai" ]]; then
    pass "theme-monokai-extension" "${extension_root}/zedokai"
  else
    fail "theme-monokai-extension" "missing ${extension_root}/zedokai; run phase 3 and start Zed"
  fi
else
  fail "theme-tokyo-extension" "missing ${native_root}/tokyo-night; run phase 3 and start Zed"
  fail "theme-monokai-extension" "missing ${native_root}/zedokai; run phase 3 and start Zed"
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "theme-checks" "python3 is required for the theme checks"
  exit 0
fi

helper_args=(check --fragment "${fragment}" --docs "${docs}" --keymap "${keymap}")
if [[ -n "${extension_root}" ]]; then
  helper_args+=(--installed-dir "${extension_root}")
fi

if [[ -f "${settings}" ]]; then
  helper_args+=(--settings "${settings}")
else
  skip "theme-installed-name" "missing ${settings}; run phase 3"
  skip "theme-brackets-enabled" "settings.json not applied yet"
  skip "theme-semantic-tokens" "settings.json not applied yet"
fi

if [[ -f "${live_keymap}" ]]; then
  helper_args+=(--live-keymap "${live_keymap}")
else
  skip "theme-live-keybinding" "missing ${live_keymap}; run phase 3"
fi

python3 "${helper}" "${helper_args[@]}"
exit 0
