#!/usr/bin/env bash
# shellcheck shell=bash
#
# Phase 2 - base setup.
#
# Installs native Zed, makes ~/.local/bin available to new shells, installs the
# JetBrainsMono Nerd Font, writes a baseline ~/.editorconfig, applies the
# phase-2 Zed settings and offers an optional GNU Stow dotfiles hookup.
#
# Every mutating action is confirmed with ask_yes_no. Declines and already
# satisfied steps record SKIP and return success.

phase_describe() {
  printf '%s\n' "Base setup: native Zed, JetBrainsMono Nerd Font, .editorconfig, base settings and optional dotfiles stow"
}

phase_run() {
  local phase_id="${ZF_PHASE_ID:-02-base}"

  phase_zed "${phase_id}"
  phase_local_bin_path "${phase_id}"
  phase_font "${phase_id}"
  phase_editorconfig "${phase_id}"
  phase_apply_config "${phase_id}"
  phase_dotfiles "${phase_id}"

  log_info "Phase ${phase_id} finished."
}

# Print installed Flatpak application IDs without creating a user Flatpak
# repository in a fresh HOME. The user installation is queried only when its
# data directory already exists.
phase_flatpak_apps() {
  local cache_dir=""
  local apps=""

  if cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/zf-flatpak.XXXXXX")"; then
    apps="$(XDG_CACHE_HOME="${cache_dir}" flatpak list --system --app --columns=application 2>/dev/null || true)"
    if [[ -d "${HOME}/.local/share/flatpak" ]]; then
      apps+=$'\n'
      apps+="$(XDG_CACHE_HOME="${cache_dir}" flatpak list --user --app --columns=application 2>/dev/null || true)"
    fi
    rm -rf -- "${cache_dir:?}"
  else
    apps="$(flatpak list --system --app --columns=application 2>/dev/null || true)"
    if [[ -d "${HOME}/.local/share/flatpak" ]]; then
      apps+=$'\n'
      apps+="$(flatpak list --user --app --columns=application 2>/dev/null || true)"
    fi
  fi
  printf '%s\n' "${apps}"
}

# Print the native zed binary when it can be found.
phase_zed_binary() {
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

phase_zed_version() {
  local phase_id="$1"
  local zed_bin="$2"
  local version=""

  if version="$(timeout 20 "${zed_bin}" --version 2>&1)"; then
    log_info "Native Zed version: ${version}"
    record_result "${phase_id}" "zed-version" "PASS"
  else
    log_warn "Could not run ${zed_bin} --version: ${version}"
    record_result "${phase_id}" "zed-version" "FAIL"
  fi
}

phase_install_zed() {
  local temp_dir=""
  local installer=""

  if is_dry_run; then
    printf '  $ curl -fL --output <temporary-file> https://zed.dev/install.sh\n'
    printf '  $ sh <temporary-file>\n'
    log_info "dry-run: the official Zed installer would be downloaded and run"
    return 0
  fi

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zed-install.XXXXXX")" || {
    log_error "Could not create a temporary directory for the Zed installer"
    return 1
  }
  installer="${temp_dir}/install.sh"

  if ! run curl -fL --output "${installer}" https://zed.dev/install.sh; then
    log_error "Could not download https://zed.dev/install.sh"
    rm -rf -- "${temp_dir:?}"
    return 1
  fi
  if [[ ! -s "${installer}" ]]; then
    log_error "The downloaded Zed installer is empty: ${installer}"
    rm -rf -- "${temp_dir:?}"
    return 1
  fi
  if ! run sh "${installer}"; then
    log_error "The official Zed installer failed"
    rm -rf -- "${temp_dir:?}"
    return 1
  fi

  rm -rf -- "${temp_dir:?}"
  return 0
}

phase_zed() {
  local phase_id="$1"
  local zed_bin=""
  local flatpak_apps=""

  log_step "Native Zed editor"

  if have_cmd flatpak; then
    flatpak_apps="$(phase_flatpak_apps)"
    if [[ "${flatpak_apps}" == *"dev.zed.Zed"* ]]; then
      log_warn "Flatpak Zed (dev.zed.Zed) is installed. Flatpak confinement can block language servers, toolchains and project paths; this installer uses the native build and will not remove the Flatpak."
      if ! ask_yes_no "Continue with the native Zed setup even though the Flatpak is installed?"; then
        log_warn "Native Zed setup was skipped because the Flatpak is installed."
        record_result "${phase_id}" "zed-native" "SKIP"
        return 0
      fi
    fi
  fi

  zed_bin="$(phase_zed_binary || true)"
  if [[ -n "${zed_bin}" ]]; then
    log_info "SKIP: native Zed is already installed at ${zed_bin}"
    record_result "${phase_id}" "zed-native" "PASS"
    phase_zed_version "${phase_id}" "${zed_bin}"
    return 0
  fi

  log_info "Native Zed was not found. Official installer: https://zed.dev/install.sh"
  if ! ask_yes_no "Download and run the official Zed installer from https://zed.dev/install.sh?"; then
    log_warn "Zed installation skipped."
    record_result "${phase_id}" "zed-native" "SKIP"
    return 0
  fi

  if ! have_cmd curl; then
    step_dnf "Install curl to download the Zed installer" curl
  fi
  if ! have_cmd curl && ! is_dry_run; then
    log_error "curl is required to download https://zed.dev/install.sh but was not found"
    record_result "${phase_id}" "zed-native" "FAIL"
    return 0
  fi

  if ! phase_install_zed; then
    record_result "${phase_id}" "zed-native" "FAIL"
    return 0
  fi
  if is_dry_run; then
    record_result "${phase_id}" "zed-native" "SKIP"
    return 0
  fi

  zed_bin="$(phase_zed_binary || true)"
  if [[ -z "${zed_bin}" ]]; then
    log_error "The Zed installer finished but no zed binary was found in PATH or ${HOME}/.local/bin/zed"
    record_result "${phase_id}" "zed-native" "FAIL"
    return 0
  fi

  record_result "${phase_id}" "zed-native" "PASS"
  phase_zed_version "${phase_id}" "${zed_bin}"
}

# Append a PATH line to one shell rc file after confirmation.
phase_path_edit_rc() {
  local label="$1"
  local rc_file="$2"
  local line="$3"
  local parent=""
  local last_byte=""

  if [[ -f "${rc_file}" ]] && grep -Fqx -- "${line}" "${rc_file}"; then
    log_info "SKIP: the ${label} PATH line is already in ${rc_file}"
    return 0
  fi

  if ! ask_yes_no "Add the ${label} PATH line to ${rc_file}?"; then
    log_warn "The ${label} PATH line was not added."
    return 0
  fi

  printf '  $ printf %%s\\n %q >> %q\n' "${line}" "${rc_file}"
  ZF_PHASE_PATH_ADDED=1

  if is_dry_run; then
    log_info "dry-run: would append the ${label} PATH line to ${rc_file}"
    return 0
  fi

  parent="${rc_file%/*}"
  if [[ "${parent}" == "${rc_file}" ]]; then
    parent="."
  fi
  if [[ ! -d "${parent}" ]]; then
    if ! run mkdir -p -- "${parent}"; then
      log_error "Could not create ${parent}"
      return 1
    fi
  fi
  if [[ -s "${rc_file}" ]]; then
    last_byte="$(tail -c 1 -- "${rc_file}" 2>/dev/null | od -An -t x1 | tr -d ' \n' || true)"
    if [[ "${last_byte}" != "0a" ]]; then
      if ! printf '\n' >>"${rc_file}"; then
        log_error "Could not append a newline to ${rc_file}"
        return 1
      fi
    fi
  fi
  if ! printf '%s\n' "${line}" >>"${rc_file}"; then
    log_error "Could not append the ${label} PATH line to ${rc_file}"
    return 1
  fi

  log_info "Added the ${label} PATH line to ${rc_file}; restart ${label} to use it."
  return 0
}

phase_path_line_configured() {
  local posix_line="$1"
  local fish_line="$2"
  local file=""

  for file in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.config/fish/config.fish"; do
    if [[ -f "${file}" ]]; then
      if grep -Fqx -- "${posix_line}" "${file}" || grep -Fqx -- "${fish_line}" "${file}"; then
        return 0
      fi
    fi
  done
  return 1
}

phase_local_bin_path() {
  local phase_id="$1"
  local local_bin="${HOME}/.local/bin"
  local posix_line=""
  local fish_line=""

  log_step "${HOME}/.local/bin on PATH"

  if [[ ":${PATH}:" == *":${local_bin}:"* ]]; then
    log_info "SKIP: ${local_bin} is already on PATH"
    record_result "${phase_id}" "local-bin-path" "PASS"
    return 0
  fi

  posix_line="export PATH=\"\$HOME/.local/bin:\$PATH\""
  fish_line="fish_add_path \"\$HOME/.local/bin\""

  log_info "Add ${local_bin} to PATH so zed, language servers and formatters installed there are found."
  printf '  bash/zsh: %s\n' "${posix_line}"
  printf '  fish    : %s\n' "${fish_line}"

  ZF_PHASE_PATH_ADDED=0
  if have_cmd bash; then
    if ! phase_path_edit_rc "bash" "${HOME}/.bashrc" "${posix_line}"; then
      log_warn "The bash PATH line could not be added."
    fi
  fi
  if have_cmd zsh; then
    if ! phase_path_edit_rc "zsh" "${HOME}/.zshrc" "${posix_line}"; then
      log_warn "The zsh PATH line could not be added."
    fi
  else
    log_info "zsh is not installed; no ~/.zshrc edit is proposed."
  fi
  if have_cmd fish; then
    if ! phase_path_edit_rc "fish" "${HOME}/.config/fish/config.fish" "${fish_line}"; then
      log_warn "The fish PATH line could not be added."
    fi
  else
    log_info "fish is not installed; no fish config edit is proposed."
  fi

  if is_dry_run; then
    record_result "${phase_id}" "local-bin-path" "SKIP"
  elif [[ "${ZF_PHASE_PATH_ADDED}" == "1" ]] || phase_path_line_configured "${posix_line}" "${fish_line}"; then
    record_result "${phase_id}" "local-bin-path" "PASS"
  else
    record_result "${phase_id}" "local-bin-path" "SKIP"
  fi
}

phase_font_dir_has_files() {
  local directory="$1"
  local file=""

  for file in "${directory}"/*.ttf; do
    if [[ -e "${file}" ]]; then
      return 0
    fi
  done
  return 1
}

# Reject archive members that would escape the extraction directory.
phase_archive_paths_safe() {
  local listing="$1"
  local entry=""

  while IFS= read -r entry; do
    case "${entry}" in
      /* | ../* | */../* | .. | */..)
        return 1
        ;;
    esac
  done <<<"${listing}"
  return 0
}

phase_font() {
  local phase_id="$1"
  local font_dir="${HOME}/.local/share/fonts/JetBrainsMonoNerdFont"
  local font_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz"
  local font_list=""
  local temp_dir=""
  local archive=""
  local listing=""
  local -a missing_tools=()
  local tool=""

  log_step "JetBrainsMono Nerd Font"

  if ! have_cmd fc-list || ! have_cmd fc-cache; then
    step_dnf "Install fontconfig for fc-list and fc-cache" fontconfig
  fi
  if ! have_cmd fc-list && ! is_dry_run; then
    log_error "fc-list is required to verify the font but was not found"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi

  if have_cmd fc-list; then
    font_list="$(fc-list : family 2>/dev/null || true)"
    if [[ "${font_list,,}" == *"jetbrainsmono nerd font"* ]]; then
      log_info "SKIP: JetBrainsMono Nerd Font is already visible to fontconfig"
      record_result "${phase_id}" "nerd-font" "PASS"
      return 0
    fi
  fi

  if [[ -d "${font_dir}" ]] && phase_font_dir_has_files "${font_dir}"; then
    log_warn "Font files exist in ${font_dir} but fc-list does not list JetBrainsMono Nerd Font."
    if ! ask_yes_no "Run fc-cache -f to refresh the font cache?"; then
      log_warn "Font cache refresh skipped."
      record_result "${phase_id}" "nerd-font" "SKIP"
      return 0
    fi
    if is_dry_run; then
      printf '  $ fc-cache -f\n'
      record_result "${phase_id}" "nerd-font" "SKIP"
      return 0
    fi
    if ! run fc-cache -f; then
      log_error "fc-cache -f failed"
      record_result "${phase_id}" "nerd-font" "FAIL"
      return 0
    fi
    font_list="$(fc-list : family 2>/dev/null || true)"
    if [[ "${font_list,,}" == *"jetbrainsmono nerd font"* ]]; then
      record_result "${phase_id}" "nerd-font" "PASS"
    else
      log_warn "fc-list still does not show JetBrainsMono Nerd Font after fc-cache -f"
      record_result "${phase_id}" "nerd-font" "FAIL"
    fi
    return 0
  fi

  log_info "Font source: ${font_url}"
  log_info "Install directory: ${font_dir}"
  if ! ask_yes_no "Download and install the JetBrainsMono Nerd Font from the latest Nerd Fonts release?"; then
    log_warn "Nerd Font installation skipped."
    record_result "${phase_id}" "nerd-font" "SKIP"
    return 0
  fi

  if ! have_cmd curl; then
    step_dnf "Install curl to download the Nerd Font archive" curl
  fi
  if ! have_cmd tar; then
    step_dnf "Install tar to unpack the Nerd Font archive" tar
  fi
  if ! have_cmd xz; then
    step_dnf "Install xz to unpack the Nerd Font archive" xz
  fi

  if ! is_dry_run; then
    for tool in curl tar xz fc-cache; do
      if ! have_cmd "${tool}"; then
        missing_tools+=("${tool}")
      fi
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
      log_error "The Nerd Font step needs these commands: ${missing_tools[*]}"
      record_result "${phase_id}" "nerd-font" "FAIL"
      return 0
    fi
  fi

  if is_dry_run; then
    printf '  $ curl -fL --output <temporary>/JetBrainsMono.tar.xz %s\n' "${font_url}"
    printf '  $ tar -tJf <temporary>/JetBrainsMono.tar.xz\n'
    printf '  $ mkdir -p %q\n' "${font_dir}"
    printf '  $ tar -xJf <temporary>/JetBrainsMono.tar.xz -C %q\n' "${font_dir}"
    printf '  $ fc-cache -f\n'
    log_info "dry-run: the Nerd Font archive would be downloaded, checked and unpacked"
    record_result "${phase_id}" "nerd-font" "SKIP"
    return 0
  fi

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zed-font.XXXXXX")" || {
    log_error "Could not create a temporary directory for the font archive"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  }
  archive="${temp_dir}/JetBrainsMono.tar.xz"

  if ! run curl -fL --output "${archive}" "${font_url}"; then
    log_error "Could not download the Nerd Font archive"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi
  if [[ ! -s "${archive}" ]]; then
    log_error "The downloaded Nerd Font archive is empty"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi
  if ! listing="$(tar -tJf "${archive}" 2>&1)"; then
    log_error "Could not list the Nerd Font archive: ${listing}"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi
  if ! phase_archive_paths_safe "${listing}"; then
    log_error "The Nerd Font archive contains an unsafe path; refusing to extract it"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi
  if [[ "${listing,,}" != *".ttf"* ]]; then
    log_error "The Nerd Font archive contains no .ttf files"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi

  if ! run mkdir -p -- "${font_dir}"; then
    log_error "Could not create ${font_dir}"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi
  if ! run tar -xJf "${archive}" -C "${font_dir}"; then
    log_error "Could not unpack the Nerd Font archive into ${font_dir}"
    rm -rf -- "${temp_dir:?}"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi
  rm -rf -- "${temp_dir:?}"

  if ! run fc-cache -f; then
    log_error "fc-cache -f failed"
    record_result "${phase_id}" "nerd-font" "FAIL"
    return 0
  fi

  font_list="$(fc-list : family 2>/dev/null || true)"
  if [[ "${font_list,,}" == *"jetbrainsmono nerd font"* ]]; then
    log_info "JetBrainsMono Nerd Font is now visible to fontconfig"
    record_result "${phase_id}" "nerd-font" "PASS"
  else
    log_warn "JetBrainsMono Nerd Font was installed but fc-list does not show it"
    record_result "${phase_id}" "nerd-font" "FAIL"
  fi
}

phase_editorconfig() {
  local phase_id="$1"
  local source="${REPO_ROOT}/config/templates/.editorconfig"
  local target="${HOME}/.editorconfig"

  log_step "EditorConfig baseline"

  if [[ -e "${target}" || -L "${target}" ]]; then
    log_info "SKIP: ${target} already exists"
    record_result "${phase_id}" "editorconfig" "PASS"
    return 0
  fi
  if [[ ! -f "${source}" ]]; then
    log_error "EditorConfig template is missing: ${source}"
    record_result "${phase_id}" "editorconfig" "FAIL"
    return 0
  fi
  if ! ask_yes_no "Install ${target} from ${source}?"; then
    log_warn "EditorConfig installation skipped."
    record_result "${phase_id}" "editorconfig" "SKIP"
    return 0
  fi

  if is_dry_run; then
    printf '  $ install -D -m 0644 %q %q\n' "${source}" "${target}"
    log_info "dry-run: would install ${target}"
    record_result "${phase_id}" "editorconfig" "SKIP"
    return 0
  fi

  if ! run install -D -m 0644 -- "${source}" "${target}"; then
    log_error "Could not install ${target}"
    record_result "${phase_id}" "editorconfig" "FAIL"
    return 0
  fi
  if [[ -s "${target}" ]]; then
    log_info "Installed ${target}"
    record_result "${phase_id}" "editorconfig" "PASS"
  else
    log_error "${target} is empty after installation"
    record_result "${phase_id}" "editorconfig" "FAIL"
  fi
}

# Return 0 when the repository fragments would change the Zed config, 1 when
# they are already present, and 2 when the existing config cannot be inspected.
phase_config_pending() {
  local output=""

  if ! output="$(python3 "${REPO_ROOT}/lib/zed_config.py" \
    --dry-run \
    --config-dir "${REPO_ROOT}/config" \
    --zed-dir "${ZF_ZED_CONFIG_DIR}" 2>&1)"; then
    log_error "Could not inspect the existing Zed configuration: ${output}"
    return 2
  fi

  case "${output}" in
    *"No changes."* | *"No config fragments found; nothing to do."*)
      return 1
      ;;
  esac
  return 0
}

phase_apply_config() {
  local phase_id="$1"
  local settings_file="${ZF_ZED_CONFIG_DIR}/settings.json"
  local pending_status=0
  local settings_was_symlink=0

  log_step "Base Zed settings"

  if [[ -L "${ZF_ZED_CONFIG_DIR}" ]]; then
    log_warn "Skipping config apply: ${ZF_ZED_CONFIG_DIR} is a symbolic link and backup_zed_config refuses to back it up. Move the link aside or merge the fragments manually."
    record_result "${phase_id}" "base-settings" "SKIP"
    return 0
  fi

  phase_config_pending || pending_status=$?
  case "${pending_status}" in
    1)
      log_info "SKIP: the existing Zed configuration already contains every repository fragment"
      record_result "${phase_id}" "base-settings" "PASS"
      return 0
      ;;
    2)
      record_result "${phase_id}" "base-settings" "FAIL"
      return 0
      ;;
  esac

  if [[ -L "${settings_file}" ]]; then
    settings_was_symlink=1
    log_warn "${settings_file} is a symbolic link, probably a dotfiles stow link. Applying fragments would replace the link with a regular file."
    if ! ask_yes_no "Replace the symlink with a merged settings.json?"; then
      log_warn "Config apply skipped to preserve the symlink."
      record_result "${phase_id}" "base-settings" "SKIP"
      return 0
    fi
  fi

  if ! apply_zed_config; then
    log_error "Applying the repository config fragments failed"
    record_result "${phase_id}" "base-settings" "FAIL"
    return 0
  fi

  if [[ "${settings_was_symlink}" == "1" ]] && ! is_dry_run; then
    log_warn "The previous settings.json symlink was replaced by a regular file. Update any dotfiles package copy before running the dotfiles hookup again."
  fi

  if is_dry_run; then
    record_result "${phase_id}" "base-settings" "SKIP"
    return 0
  fi

  pending_status=0
  phase_config_pending || pending_status=$?
  case "${pending_status}" in
    1)
      log_info "Base settings applied to ${ZF_ZED_CONFIG_DIR}"
      record_result "${phase_id}" "base-settings" "PASS"
      ;;
    2)
      record_result "${phase_id}" "base-settings" "FAIL"
      ;;
    *)
      log_warn "Configuration changes were not applied (declined or still pending)."
      record_result "${phase_id}" "base-settings" "SKIP"
      ;;
  esac
}

phase_dotfiles() {
  local phase_id="$1"
  local dotfiles_path="${ZF_DOTFILES_REPO:-}"
  local package_dir=""
  local live_settings="${ZF_ZED_CONFIG_DIR}/settings.json"
  local live_keymap="${ZF_ZED_CONFIG_DIR}/keymap.json"
  local -a live_files=()
  local -a package_files=()
  local -a names=()
  local name=""
  local live=""
  local dest=""
  local resolved=""
  local dest_resolved=""
  local conflict=0
  local found_live=0
  local already_stowed=0
  local dotfiles_backup=""
  local pre_stow=""
  local index=0
  local rollback_index=0
  local all_stowed=1

  log_step "Optional dotfiles hookup (GNU Stow)"

  if [[ -z "${dotfiles_path}" ]]; then
    if is_dry_run; then
      printf '  Set ZF_DOTFILES_REPO=/path/to/dotfiles to preview the real paths.\n'
      printf '  $ install -m 0644 %q <dotfiles>/zed/.config/zed/settings.json\n' "${live_settings}"
      if [[ -e "${live_keymap}" ]]; then
        printf '  $ install -m 0644 %q <dotfiles>/zed/.config/zed/keymap.json\n' "${live_keymap}"
      fi
      printf '  $ stow --no-folding --dir <dotfiles> --target %q zed\n' "${HOME}"
      log_info "dry-run: no dotfiles path was supplied; the hookup was not planned in detail"
      record_result "${phase_id}" "dotfiles-stow" "SKIP"
      return 0
    fi
    if [[ ! -t 0 || ! -t 1 ]]; then
      log_info "SKIP: no dotfiles path was supplied (set ZF_DOTFILES_REPO or run interactively)"
      record_result "${phase_id}" "dotfiles-stow" "SKIP"
      return 0
    fi
    printf '  Dotfiles repository path (empty to skip): '
    if ! read -r dotfiles_path; then
      dotfiles_path=""
    fi
  fi

  if [[ -z "${dotfiles_path}" ]]; then
    log_info "SKIP: dotfiles hookup not requested"
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi

  if [[ "${dotfiles_path}" == "~" ]]; then
    dotfiles_path="${HOME}"
  elif [[ "${dotfiles_path:0:1}" == "~" && "${dotfiles_path:1:1}" == "/" ]]; then
    dotfiles_path="${HOME}/${dotfiles_path:2}"
  fi

  if [[ ! -d "${dotfiles_path}" ]]; then
    if is_dry_run; then
      log_warn "dry-run: ${dotfiles_path} does not exist; planned commands will fail if run as-is"
    else
      log_warn "Dotfiles path does not exist or is not a directory: ${dotfiles_path}"
      record_result "${phase_id}" "dotfiles-stow" "SKIP"
      return 0
    fi
  else
    dotfiles_path="$(cd -- "${dotfiles_path}" && pwd -P)" || {
      log_warn "Could not resolve the dotfiles path: ${dotfiles_path}"
      record_result "${phase_id}" "dotfiles-stow" "SKIP"
      return 0
    }
  fi

  package_dir="${dotfiles_path}/zed"

  for name in settings.json keymap.json; do
    live="${ZF_ZED_CONFIG_DIR}/${name}"
    dest="${package_dir}/.config/zed/${name}"

    if [[ ! -e "${live}" && ! -L "${live}" ]]; then
      continue
    fi
    found_live=1

    if [[ -L "${live}" ]]; then
      resolved="$(readlink -f -- "${live}" 2>/dev/null || true)"
      dest_resolved="$(readlink -f -- "${dest}" 2>/dev/null || true)"
      if [[ -n "${resolved}" && -e "${dest}" && "${resolved}" == "${dest_resolved}" ]]; then
        log_info "SKIP: ${name} is already stowed from ${dest}"
        already_stowed=1
        continue
      fi
      log_warn "Conflict: ${live} is a symlink to ${resolved:-an unresolved target}, not to ${dest}"
      conflict=1
      continue
    fi

    if [[ ! -f "${live}" ]]; then
      log_warn "Conflict: ${live} is not a regular file"
      conflict=1
      continue
    fi
    if [[ -e "${dest}" || -L "${dest}" ]]; then
      log_warn "Conflict: ${dest} already exists; refusing to overwrite it"
      conflict=1
      continue
    fi

    live_files+=("${live}")
    package_files+=("${dest}")
    names+=("${name}")
  done

  if [[ "${conflict}" == "1" ]]; then
    log_warn "Dotfiles hookup aborted without copying or stowing anything."
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi
  if [[ "${found_live}" == "0" ]]; then
    log_warn "No generated settings.json or keymap.json was found in ${ZF_ZED_CONFIG_DIR}; run the config step first."
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi
  if [[ ${#live_files[@]} -eq 0 ]]; then
    if [[ "${already_stowed}" == "1" ]]; then
      log_info "SKIP: the generated Zed files are already stowed from ${package_dir}"
      record_result "${phase_id}" "dotfiles-stow" "PASS"
    else
      record_result "${phase_id}" "dotfiles-stow" "SKIP"
    fi
    return 0
  fi

  if ! ask_yes_no "Copy ${names[*]} into ${package_dir}/.config/zed and run stow zed?"; then
    log_warn "Dotfiles hookup skipped."
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi

  if ! have_cmd stow; then
    step_dnf "Install GNU Stow for the dotfiles hookup" stow
  fi
  if ! have_cmd stow && ! is_dry_run; then
    log_warn "GNU Stow is not installed; the dotfiles hookup was skipped."
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi

  dotfiles_backup="${REPO_ROOT}/backups/dotfiles-${ZF_RUN_TS}"
  if [[ -e "${dotfiles_backup}" ]]; then
    dotfiles_backup="${dotfiles_backup}-$$"
  fi
  pre_stow="${REPO_ROOT}/backups/pre-stow-${ZF_RUN_TS}"
  if [[ -e "${pre_stow}" ]]; then
    pre_stow="${pre_stow}-$$"
  fi

  if is_dry_run; then
    if [[ -d "${ZF_ZED_CONFIG_DIR}" ]]; then
      printf '  $ cp -a %q %q\n' "${ZF_ZED_CONFIG_DIR}" "${REPO_ROOT}/backups/zed-${ZF_RUN_TS}/zed"
    fi
    if [[ -d "${package_dir}" ]]; then
      printf '  $ mkdir -p %q\n' "${dotfiles_backup}"
      printf '  $ cp -a %q %q\n' "${package_dir}" "${dotfiles_backup}/zed"
    fi
    printf '  $ mkdir -p %q\n' "${package_dir}/.config/zed"
    for index in "${!live_files[@]}"; do
      printf '  $ install -m 0644 %q %q\n' "${live_files[index]}" "${package_files[index]}"
    done
    printf '  $ mkdir -p %q\n' "${pre_stow}/zed"
    for index in "${!live_files[@]}"; do
      printf '  $ mv %q %q\n' "${live_files[index]}" "${pre_stow}/zed/${names[index]}"
    done
    printf '  $ stow --no-folding --dir %q --target %q zed\n' "${dotfiles_path}" "${HOME}"
    log_info "dry-run: the dotfiles package would be backed up, populated and stowed"
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi

  if [[ -L "${ZF_ZED_CONFIG_DIR}" ]]; then
    log_warn "The Zed config directory is a symlink; backup_zed_config refuses it. Dotfiles hookup skipped."
    record_result "${phase_id}" "dotfiles-stow" "SKIP"
    return 0
  fi
  if ! backup_zed_config; then
    log_error "The live Zed config could not be backed up; dotfiles hookup aborted."
    record_result "${phase_id}" "dotfiles-stow" "FAIL"
    return 0
  fi

  if [[ -d "${package_dir}" ]]; then
    if ! run mkdir -p -- "${dotfiles_backup}"; then
      log_error "Could not create ${dotfiles_backup}"
      record_result "${phase_id}" "dotfiles-stow" "FAIL"
      return 0
    fi
    if ! run cp -a -- "${package_dir}" "${dotfiles_backup}/zed"; then
      log_error "Could not back up ${package_dir}"
      record_result "${phase_id}" "dotfiles-stow" "FAIL"
      return 0
    fi
  fi

  if ! run mkdir -p -- "${package_dir}/.config/zed"; then
    log_error "Could not create ${package_dir}/.config/zed"
    record_result "${phase_id}" "dotfiles-stow" "FAIL"
    return 0
  fi

  for index in "${!live_files[@]}"; do
    if ! run install -m 0644 -- "${live_files[index]}" "${package_files[index]}"; then
      log_error "Could not copy ${live_files[index]} to ${package_files[index]}"
      record_result "${phase_id}" "dotfiles-stow" "FAIL"
      return 0
    fi
  done

  if ! run mkdir -p -- "${pre_stow}/zed"; then
    log_error "Could not create ${pre_stow}/zed"
    record_result "${phase_id}" "dotfiles-stow" "FAIL"
    return 0
  fi
  for index in "${!live_files[@]}"; do
    if ! run mv -- "${live_files[index]}" "${pre_stow}/zed/${names[index]}"; then
      log_error "Could not move ${live_files[index]} aside; restoring any moved files"
      for rollback_index in "${!live_files[@]}"; do
        if [[ -e "${pre_stow}/zed/${names[rollback_index]}" ]]; then
          run mv -- "${pre_stow}/zed/${names[rollback_index]}" "${live_files[rollback_index]}" || true
        fi
      done
      record_result "${phase_id}" "dotfiles-stow" "FAIL"
      return 0
    fi
  done

  if ! run stow --no-folding --dir "${dotfiles_path}" --target "${HOME}" zed; then
    log_error "stow failed; restoring the generated files from ${pre_stow}/zed"
    for index in "${!live_files[@]}"; do
      if [[ -e "${pre_stow}/zed/${names[index]}" ]]; then
        run mv -- "${pre_stow}/zed/${names[index]}" "${live_files[index]}" || true
      fi
    done
    record_result "${phase_id}" "dotfiles-stow" "FAIL"
    return 0
  fi

  for index in "${!live_files[@]}"; do
    live="${live_files[index]}"
    dest="${package_files[index]}"
    resolved="$(readlink -f -- "${live}" 2>/dev/null || true)"
    dest_resolved="$(readlink -f -- "${dest}" 2>/dev/null || true)"
    if [[ ! -L "${live}" || -z "${resolved}" || "${resolved}" != "${dest_resolved}" ]]; then
      all_stowed=0
    fi
  done

  if [[ "${all_stowed}" == "1" ]]; then
    log_info "Stowed the generated Zed files from ${package_dir}"
    record_result "${phase_id}" "dotfiles-stow" "PASS"
  else
    log_warn "stow reported success but the live files are not all symlinks into ${package_dir}"
    record_result "${phase_id}" "dotfiles-stow" "FAIL"
  fi
}
