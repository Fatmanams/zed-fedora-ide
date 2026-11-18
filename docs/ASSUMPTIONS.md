# Assumptions and verification record

This document records what phases 1, 2, 3 and 4 actually verified, what they
assume, and what they intentionally leave out. Later phases must add a line for
every new claim about Zed or Fedora. If a fact is not in the verified list or
the evidence log, treat it as unverified.

Recorded on 2026-11-16; phase 3 added on 2026-11-17; phase 4 added on
2026-11-18.

## Scope

- Target platform: Fedora Linux on x86_64, with Zed configuration under
  `~/.config/zed`.
- Phase 1 ships the installer framework, the helper API, the JSONC/merge engine,
  backups and restore, verification and tests. It ships no Zed settings,
  keymaps, tasks, snippets or extensions, and it installs no packages.
- Phase 2 ships `phases/02-base.sh`, `scripts/verify.d/02-base.sh`,
  `config/settings.d/02-base.json`, an intentionally empty
  `config/keymap.d/02-base.json`, `config/templates/.editorconfig`, and the
  optional GNU Stow dotfiles hookup. It installs native Zed, the JetBrainsMono
  Nerd Font, an `~/.editorconfig` and base settings. It does not install a
  theme, an icon theme, an extension or a language toolchain.
- Phase 3 ships `phases/03-theme.sh`, `scripts/verify.d/03-theme.sh`,
  `config/settings.d/03-theme.json`, `config/keymap.d/03-theme.json`,
  `lib/theme_build.py` and `docs/THEME.md`. It selects Tokyo Night as the dark
  theme, applies classic Monokai syntax colours as `theme_overrides`, enables
  rainbow brackets and semantic tokens, lists the `tokyo-night` and `zedokai`
  extensions for auto-install, and adds a theme-selector keybinding.
- Phase 4 ships `phases/04-git.sh`, `scripts/verify.d/04-git.sh`,
  `config/settings.d/04-git.json`, `config/tasks.d/04-git.json` and
  `config/templates/gitignore`. It installs the Fedora `git` and `gh` packages,
  asks for a missing Git identity, sets five global Git defaults, offers the
  GitHub CLI login and credential helper, offers a global git ignore file, and
  merges Git panel settings and Git/GitHub tasks.
- The only directory this project backs up, merges or restores automatically is
  `~/.config/zed`. The optional dotfiles hookup additionally backs up
  `<dotfiles>/zed` under the repository's `backups/` directory.
- The phase-2 installers were **not executed for real** in the verification
  environment. The environment already had native Zed and the Nerd Font; phase-2
  commands were checked with `--dry-run`, a controlled stow simulation and a
  temporary-`HOME` sandbox. This distinction is repeated where it matters.
- Phase 3 was **not installed into the real `~/.config/zed`**. Its fragment was
  generated from pinned theme JSON downloaded from the exact extension-registry
  commits. `./install.sh --dry-run --phase 3` was checked against the real
  environment, where the theme extensions were not yet installed. A full
  `./install.sh --phase 3 --yes` sandbox run used a temporary `HOME` containing
  the pinned extension JSON; it applied the fragment and keymap, preserved an
  unrelated `agent_servers` key, and recorded `PASS` for the live theme settings
  and keybinding. `scripts/verify.d/03-theme.sh` was exercised against the same
  controlled tree. The real extension download and live theme rendering were
  not observed.
- Phase 4 was **not installed into the real `~/.config/zed`, the real
  `~/.gitconfig` or the real `~/.config/git/ignore`**. It was checked with
  `./install.sh --dry-run --phase 4` under a temporary `HOME`, with a full
  `./install.sh --phase 4 --yes` sandbox run under a temporary `HOME`, and with
  `scripts/verify.d/04-git.sh` against that sandbox. `gh auth login`,
  `gh auth setup-git` and the real GitHub credential-helper change were
  **not** run. No token was read or printed.

## Environment used for verification

| Item | Value | Command used |
| --- | --- | --- |
| Distribution | Fedora Linux 45 (KDE Plasma Desktop Edition), `ID=fedora` | `grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release` |
| Architecture | `x86_64` | `uname -m` |
| bash | 5.3.15 | `bash --version` |
| python3 | 3.15.2 | `python3 --version` |
| shellcheck | not installed system-wide; phases 2, 3 and 4 were checked with 0.11.0 extracted from `ShellCheck-0.11.0-5.fc45.x86_64.rpm` | `command -v shellcheck`; `dnf download shellcheck`; extracted `usr/bin/shellcheck --version` |
| jq package | 1.8.2-5.fc45, repository `fedora` | `dnf info jq` |
| git | 2.56.1-1.fc45, repository `updates` (package name `git`) | `dnf info git`; `git --version` |
| gh | 2.97.0-1.fc45, repository `fedora` (package name `gh`) | `dnf info gh`; `gh --version` |
| Native Zed | 1.27.0, commit `c84af5b99cbc366d675064e52b23664a015b6e35` | `~/.local/bin/zed --version` |
| Native Zed, live dry-run (2026-11-18) | 1.28.1, commit `e8bc16acee5ae1937600d571d441c4b5d7b0d288` | `~/.local/bin/zed --version`; default settings/keymaps fetched at that commit |
| Extension root | `/home/fatman/.local/share/zed/extensions/installed`, containing only the `html` extension during verification | `ls -la ~/.local/share/zed/extensions/installed` |
| Extension root, live dry-run (2026-11-18) | `/home/fatman/.local/share/zed/extensions/installed`, containing `html`, `tokyo-night` 0.9.0 and `zedokai` 1.2.2 | `ls -la`; `grep '^version' extension.toml` |
| Tokyo Night extension | `tokyo-night` 0.9.0, registry commit `a4ef7dd64e146434d4ac289b59abe17ff98ba680`, theme JSON SHA-256 `3ef9e8bf...da07b` | `curl` of the pinned GitHub archive; `extension.toml`; `sha256sum` |
| Zedokai extension | `zedokai` 1.2.2, registry commit `b4c5a0b8b66f1889bd1eabafe5e984372ebff7a5`, theme JSON SHA-256 `e75c06a7...402e` | `curl` of the pinned GitHub archive; `extension.toml`; `sha256sum` |
| Flatpak | installed; `dev.zed.Zed` **not** installed (apps: `com.spotify.Client`, `io.dbeaver.DBeaverCommunity`) | `flatpak list --app --columns=application`; `flatpak search zed` |
| Nerd Fonts release | latest `v3.5.1`; `JetBrainsMono.tar.xz`, 7,284,244 bytes, 98 top-level `.ttf` entries | GitHub releases API; `tar -tJf` |
| Font family | `JetBrainsMono Nerd Font` visible to fontconfig (installed under `~/.local/share/fonts/JetBrainsMonoNerd`, not by this phase) | `fc-list : family` |
| fontconfig | 2.18.3-2.fc45 | `rpm -q fontconfig` |
| GNU Stow | 2.4.1-5.fc45 available from `fedora`; not installed on the verification machine | `dnf info stow`; `command -v stow` |
| curl / tar / xz | 8.21.0-9.fc45 / 1.35-10.fc45 / 5.8.3-2.fc45 | `rpm -q curl tar xz` |
| zsh / fish | zsh not installed; fish installed | `command -v zsh`; `command -v fish` |

The installer accepts any release whose `/etc/os-release` reports `ID=fedora`
and refuses other distributions and non-x86_64 machines. It does not pin a
Fedora release. Fedora 45 is the only release this phase was tested on; older
and newer Fedora releases are unverified.

Only Python 3.15.2 was used. `scripts/verify.d/00-environment.sh` accepts
Python 3.8 or newer, but the suite has not been run on 3.8 through 3.14.
Bash 5.3.15 was used; the installer requires bash 5.

## Verified against Zed documentation

Checked on 2026-11-16 at:

- <https://zed.dev/docs/configuring-zed>
- <https://zed.dev/docs/key-bindings>
- <https://zed.dev/docs/tasks>
- <https://zed.dev/docs/snippets>
- <https://zed.dev/docs/linux>
- <https://zed.dev/docs/languages/json>

Verified facts used by phase 1:

1. On Linux, Zed configuration lives in `~/.config/zed/`, with
   `settings.json`, `keymap.json`, `tasks.json` and a `snippets/` directory.
2. `settings.json`, `keymap.json` and `tasks.json` are JSONC: `//` line
   comments and `/* */` block comments are accepted.
3. `settings.json` is a JSON object. Per-language settings are nested under
   `languages.<language name>`.
4. `keymap.json` is a JSON array of objects with a `bindings` object and an
   optional `context` string.
5. `tasks.json` is a JSON array of task objects with a required `label`, a
   `command`, and optional `args`. Task commands can use variables including
   `$ZED_FILE` and `$ZED_RELATIVE_FILE`.
6. Global snippets are stored in `~/.config/zed/snippets/snippets.json` as a
   JSON object; snippet entries use `prefix`, `body` and `description`.
7. Zed's extension gallery is the supported place to find and install
   extensions. Phase 1 does not install or name any extension ID.

These facts are exercised only by the fixtures under
`config/templates/test/`. Those files are test data and are never installed.
The fixtures use setting names, keymap actions and contexts, task variables and
snippet fields that were checked against the pages above.

The only package name passed to `step_dnf` anywhere in phase 1 is `jq`, in
`phases/00-template.sh.example`. (`git` appears only in a `have_cmd` check and
is never installed by the template.) Phase 2 may additionally pass `curl`,
`tar`, `xz`, `fontconfig` and `stow` only when the corresponding command is
missing. The evidence is:

```text
$ dnf info jq
Installed packages
Name            : jq
Version         : 1.8.2
Release         : 5.fc45
Architecture    : x86_64
From repository : fedora
```

`jq` was already installed in the verification environment. Phase 1 did not run
`sudo dnf install`, so the template's actual installation path is unexercised.
The template is an example, not a shipped phase, and `install.sh` never loads
`.sh.example` files.

Phase 2 package evidence (read-only checks; no `dnf install` was run):

```text
$ dnf info stow
Name        : stow
Version     : 2.4.1
Release     : 5.fc45
Architecture: noarch
Repository  : fedora

$ dnf info fontconfig
Name        : fontconfig
Version     : 2.18.3
Release     : 2.fc45
Architecture: x86_64
Repository  : fedora

$ rpm -q curl tar xz fontconfig
curl-8.21.0-9.fc45.x86_64
tar-1.35-10.fc45.x86_64
xz-5.8.3-2.fc45.x86_64
fontconfig-2.18.3-2.fc45.x86_64
```

`stow` was not installed in the verification environment; the optional dotfiles
hookup therefore installed nothing and its real `stow` invocation was exercised
only with a controlled fake `stow` script in `/tmp`.

## Verified for phase 2

Checked on 2026-11-16 against the pages listed above plus:

- <https://zed.dev/docs/linux>
- <https://zed.dev/docs/installation>
- <https://zed.dev/docs/visual-customization>
- <https://zed.dev/docs/reference/all-settings>
- <https://github.com/zed-industries/zed/blob/c84af5b99cbc366d675064e52b23664a015b6e35/assets/settings/default.json>
- <https://github.com/zed-industries/zed/blob/c84af5b99cbc366d675064e52b23664a015b6e35/assets/keymaps/default-linux.json>
- <https://github.com/zed-industries/zed/blob/c84af5b99cbc366d675064e52b23664a015b6e35/assets/keymaps/linux/vscode.json>

Verified facts used by phase 2:

1. The official Linux install command is `curl -f https://zed.dev/install.sh |
   sh`. The phase downloads the script to a temporary file and runs `sh` on it,
   so nothing is piped directly into a shell.
2. The Flatpak application ID is `dev.zed.Zed` (and the preview is
   `dev.zed.Zed-Preview`). The phase only detects `dev.zed.Zed` in
   `flatpak list --app --columns=application`; it never removes it.
3. The latest Nerd Fonts release at verification time was `v3.5.1`.
   `JetBrainsMono.tar.xz` was 7,284,244 bytes and contained 98 top-level `.ttf`
   files with no directory components. The family reported by fontconfig after
   installation is `JetBrainsMono Nerd Font` (with aliases such as
   `JetBrainsMono NF`).
4. The phase-2 settings keys and their Zed 1.27.0 defaults in
   `assets/settings/default.json` are:

   | Key | Default | Phase-2 value |
   | --- | --- | --- |
   | `buffer_font_family` | `.ZedMono` | `JetBrainsMono Nerd Font` |
   | `buffer_font_features` | `{}` | `{"calt": true}` |
   | `terminal.font_family` | `null` | `JetBrainsMono Nerd Font` |
   | `terminal.dock` | `bottom` | `bottom` |
   | `base_keymap` | `Zed` | `VSCode` |
   | `project_panel.dock` | `right` | `left` |
   | `outline_panel.dock` | `right` | `right` |
   | `agent.dock` | `left` | `right` |
   | `tabs.file_icons` | `false` | `true` |
   | `tabs.git_status` | `false` | `true` |
   | `minimap.show` | `never` | `always` |
   | `indent_guides.enabled` | `true` | `true` |
   | `toolbar.breadcrumbs` | `true` | `true` |
   | `inlay_hints.enabled` | `false` | `true` |
   | `format_on_save` | `off` | `on` |
   | `remove_trailing_whitespace_on_save` | `true` | `true` |
   | `ensure_final_newline_on_save` | `true` | `true` |

   `minimap.show: "always"`, `format_on_save: "on"`, `base_keymap: "VSCode"`
   and the `left`/`right` dock values are documented options, not guesses. The
   setting is written to `~/.config/zed/settings.json` by
   `lib/zed_config.py`, which only validates JSON shape; it does not validate
   Zed's schema.
5. `Ctrl` + backtick is bound to `terminal_panel::Toggle` in the default Linux
   keymap under the `Workspace` context, and `Ctrl+Shift+E` is bound to
   `project_panel::ToggleFocus` under `Workspace` and `AgentPanel`. Neither key
   appears in `assets/keymaps/linux/vscode.json`. `config/keymap.d/02-base.json`
   is therefore `[]`: phase 2 adds no binding and cannot duplicate a default.
6. Zed documents that it reads `.editorconfig` project settings and that the
   EditorConfig `end_of_line` property overrides its own line-ending setting.
   The installed `~/.editorconfig` is a standard editor-independent baseline,
   not a Zed-specific schema.
7. Phase 2 was checked with `bash -n`, shellcheck 0.11.0 (extracted from the
   Fedora RPM), `./install.sh --dry-run --phase 2` with a temporary `HOME`, and
   controlled sandbox runs for the PATH, `.editorconfig`, config-apply and
   dotfiles-stow functions. The sandbox used a fake `stow` and temporary
   directories. No real Zed install, font install, `dnf install`, `stow` run or
   `~/.editorconfig` write was performed during verification.

## Verified for phase 3

Checked on 2026-11-17 against:

- <https://zed.dev/docs/themes>
- <https://zed.dev/docs/extensions/installing-extensions>
- <https://zed.dev/docs/key-bindings>
- <https://zed.dev/docs/reference/all-settings#auto-install-extensions>
- <https://github.com/zed-industries/zed/blob/c84af5b99cbc366d675064e52b23664a015b6e35/assets/settings/default.json>
- <https://github.com/zed-industries/zed/blob/c84af5b99cbc366d675064e52b23664a015b6e35/assets/keymaps/default-linux.json>
- <https://github.com/zed-industries/zed/blob/c84af5b99cbc366d675064e52b23664a015b6e35/assets/keymaps/linux/vscode.json>
- <https://github.com/ssaunderss/zed-tokyo-night/tree/a4ef7dd64e146434d4ac289b59abe17ff98ba680>
- <https://github.com/slymax/zedokai/tree/b4c5a0b8b66f1889bd1eabafe5e984372ebff7a5>

Verified facts used by phase 3:

1. The Tokyo Night extension is `tokyo-night` 0.9.0 from
   `ssaunderss/zed-tokyo-night` at registry commit
   `a4ef7dd64e146434d4ac289b59abe17ff98ba680`. Its theme JSON defines
   `Tokyo Night` (dark), `Tokyo Night Light`, `Tokyo Night Storm` and
   `Tokyo Night Moon`; the dark theme's `editor.background` is `#1a1b26`.
2. The Monokai extension is `zedokai` 1.2.2 from `slymax/zedokai` at registry
   commit `b4c5a0b8b66f1889bd1eabafe5e984372ebff7a5`. Its exact dark theme name
   is `Zedokai Classic`; its syntax section has keyword `#f92672`, string
   `#e6db74`, function `#a6e22e`, number/constant `#ae81ff`, variable/property
   `#fdfff1`, and background `#272822`.
3. `Monokai Pro (CE)`, `KTRZ Monokai`, `SuperGreatMonokai` and `Monokai-og`
   use different classic-syntax mappings (Pro palette, red properties, blue
   variables, green properties or a non-classic comment colour). They were
   rejected by reading their theme JSON, not by their names.
4. Zed 1.27.0 stores a dark/light theme pair as
   `{"theme": {"mode": "dark", "light": "Tokyo Night Light", "dark": "Tokyo Night"}}`.
   The default settings use the same shape with `One Light` and `One Dark`.
   Zed 1.28.1's default settings use the same shape.
5. `theme_overrides` is keyed by the exact theme name and accepts `syntax`
   entries plus an `accents` array. Zed's theme documentation shows exactly that
   shape. The `accents` array controls the colours used for different bracket
   indentation levels; `colorize_brackets` defaults to `false`.
6. `semantic_tokens` accepts `off`, `combined` and `full`; the default is `off`.
   Phase 3 uses `combined`, so tree-sitter highlighting remains the base and LSP
   semantic tokens refine it. It writes no `semantic_tokens` key when the
   installed Zed is older than the verified 1.27.0 baseline. Zed 1.28.1's
   default settings were re-checked on 2026-11-18 and still use the same key
   and values.
7. `auto_install_extensions` maps extension IDs to `true` (install) or `false`
   (never install). Zed installs extensions in
   `$XDG_DATA_HOME/zed/extensions` or `~/.local/share/zed/extensions`, with
   source under the `installed/` subdirectory. Phase 3 searches the native root,
   the `~/.local/share` fallback and the Flatpak data root.
8. `theme_selector::Toggle` is the theme selector action. Zed's default Linux
   keymap binds it to `ctrl-k ctrl-t`; the official theme docs also name
   `ctrl-k ctrl-t` (and `cmd-k cmd-t` on macOS). `ctrl-alt-t` appears in neither
   the default Linux keymap nor the VSCode base keymap, so the phase-3 binding
   does not override a documented default. Zed 1.28.1's default Linux keymap
   still binds `theme_selector::Toggle` to `ctrl-k ctrl-t` and still leaves
   `ctrl-alt-t` unused; this was re-checked on 2026-11-18.
9. The WCAG contrast values used in `docs/THEME.md` are computed with the sRGB
   relative-luminance formula. Against `#1a1b26`, the target palette measures:
   keyword `#f92672` 4.52:1, string `#e6db74` 12.00:1, function `#a6e22e`
   11.02:1, number/constant `#ae81ff` 6.01:1, neutral `#f8f8f2` 16.03:1, and
   comment `#75715e` 3.48:1. The comment target fails the 3.5:1 floor, so the
   generator preserves the hue and lightens it to `#76725e` (3.53:1).
10. The six bracket accents `#f92672`, `#fd971f`, `#e6db74`, `#a6e22e`,
    `#66d9ef` and `#ae81ff` all clear 4.5:1 on `#1a1b26` (4.52, 7.83, 12.00,
    11.02, 10.37 and 6.01 respectively).
11. Phase 3 was checked with `bash -n` and shellcheck 0.11.0 (extracted from the
    Fedora RPM, not installed system-wide) on its phase and verify scripts, with
    `./install.sh --dry-run --phase 3` against the real environment, with
    `lib/theme_build.py check` against the generated fragment, with a controlled
    installed-extension tree under a temporary `HOME` for the verify script, and
    with a full `./install.sh --phase 3 --yes` sandbox run against the same
    tree. That sandbox run applied the fragment to the temporary
    `settings.json` and `keymap.json`, preserved an unrelated `agent_servers`
    key, and recorded `PASS` for `theme-settings` and `theme-keybinding`. At the
    time of that check, the theme extensions were not installed on the real
    verification machine, so the real extension download and the live theme
    rendering were not exercised.
12. On 2026-11-18 the real machine had Zed 1.28.1 and both theme extensions
    installed: `tokyo-night` 0.9.0 and `zedokai` 1.2.2, matching the pinned
    versions. `./install.sh --dry-run --phase 3` then found both theme JSON
    files, passed the semantic-token version gate and previewed the full
    fragment with `theme_overrides` keyed by `Tokyo Night`, without writing the
    live config. Zed 1.28.1's default settings and Linux keymap at commit
    `e8bc16acee5ae1937600d571d441c4b5d7b0d288` were re-checked for
    `theme`, `theme_overrides`, `colorize_brackets`, `semantic_tokens`,
    `auto_install_extensions` and `theme_selector::Toggle`; all are unchanged
    from 1.27.0. The live config had not been changed by that dry-run.

## Verified for phase 4

Checked on 2026-11-18 against:

- <https://zed.dev/docs/git>
- <https://zed.dev/docs/tasks>
- <https://zed.dev/docs/reference/all-settings#git-panel>
- <https://zed.dev/docs/reference/all-settings#git-gutter>
- <https://zed.dev/docs/reference/all-settings#inline-git-blame>
- <https://github.com/zed-industries/zed/blob/e8bc16acee5ae1937600d571d441c4b5d7b0d288/assets/settings/default.json>
- <https://github.com/zed-industries/zed/blob/e8bc16acee5ae1937600d571d441c4b5d7b0d288/crates/task/src/task.rs>
- <https://github.com/zed-industries/zed/blob/e8bc16acee5ae1937600d571d441c4b5d7b0d288/crates/task/src/task_template.rs>
- <https://git-scm.com/docs/git-config>
- <https://git-scm.com/docs/gitignore>
- <https://cli.github.com/manual/gh_auth_login>
- <https://cli.github.com/manual/gh_auth_status>
- <https://cli.github.com/manual/gh_auth_setup-git>
- <https://cli.github.com/manual/gh_pr_create>
- <https://cli.github.com/manual/gh_pr_view>
- <https://cli.github.com/manual/gh_repo_view>
- <https://cli.github.com/manual/gh_run_list>
- <https://cli.github.com/manual/gh_help_environment>

Verified facts used by phase 4:

1. The Fedora package names are exactly `git` and `gh`. `dnf info --available`
   reported:

   ```text
   Name           : gh
   Version        : 2.97.0
   Release        : 1.fc45
   Architecture   : x86_64
   Repository     : fedora

   Name           : git
   Version        : 2.56.1
   Release        : 1.fc45
   Architecture   : x86_64
   Repository     : updates
   ```

   The installed commands report `git version 2.56.1` and
   `gh version 2.97.0 (2026-07-31)`. The phase passes `git gh` to `step_dnf`;
   the install path itself was not run because both packages were already
   installed.

2. The five global keys and their documented effects are:

   | Key | Value | Documented effect |
   | --- | --- | --- |
   | `init.defaultBranch` | `main` | Overrides the initial branch name for a new repository. |
   | `pull.rebase` | `true` | Rebases on top of the fetched branch instead of merging. |
   | `push.autoSetupRemote` | `true` | Assumes `--set-upstream` on a default push when no upstream exists. |
   | `core.editor` | `zed --wait` | Editor for commit and tag messages when `GIT_EDITOR` is unset. |
   | `rerere.enabled` | `true` | Records resolved conflicts so identical hunks can be reused. |

   `git config --global` writes one file at a time. It uses `~/.gitconfig`, or
   `$XDG_CONFIG_HOME/git/config` when `~/.gitconfig` does not exist and the XDG
   file does. The phase relies on Git to choose the file; it does not write
   either path directly.

3. Zed's Git page documents the command-line editor setting verbatim as
   `git config --global core.editor "zed --wait"` and also shows
   `export GIT_EDITOR="zed --wait"` for a shell environment. The phase writes
   only the first form.

4. `core.excludesFile` defaults to `$XDG_CONFIG_HOME/git/ignore`; when
   `$XDG_CONFIG_HOME` is unset or empty, Git uses `$HOME/.config/git/ignore`.
   The phase's target `${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore` therefore
   matches Git's documented default. If the user already set
   `core.excludesFile`, Git reads that file instead and the installed ignore
   file has no effect. The phase never changes `core.excludesFile`.

5. Zed 1.28.1's `assets/settings/default.json` at the pinned commit has
   `git_panel.dock: "right"`, `git.git_gutter: "tracked_files"` and
   `git.inline_blame.enabled: true`. The all-settings reference documents
   `git_panel.dock` as `left` or `right`, and `git.git_gutter` as
   `tracked_files` or `hide`. The Git page currently says the panel docks on
   the left by default, while the reference and the pinned `default.json` still
   say `right`; the fragment writes `left` explicitly, so the phase's result
   does not depend on which default is current. `git.inline_blame` also accepts
   `location`, `delay_ms`, `padding`, `show_commit_summary` and `min_column`;
   the fragment sets only `enabled`.

6. Zed's task documentation defines `cwd` as the project root by default,
   `use_new_terminal` as `false` by default, and `reveal` as `always` by default
   with accepted values `always`, `no_focus` and `never`. Every phase-4 task
   sets `use_new_terminal: false` and `reveal: "always"` explicitly. Tasks are
   spawned in the integrated terminal, and a login shell is used.

7. Task arguments are variable-expanded with `shellexpand`. Known
   `$ZED_*` variables are replaced with their task values. An unknown
   `$ZED_*` name without a default is an error, while an unknown non-`ZED_*`
   name is left in place for the spawning shell. `task.rs` comments that
   arguments are "potentially unsubstituted, to let the shell that spawns the
   command do the substitution, if needed." The new-branch task therefore
   passes `$branch` through to its `bash -c` command rather than expecting Zed
   to resolve it.

8. `gh auth status` exits 1 when an account on any checked host has
   authentication issues and writes its details to stderr. `--no-refresh`
   prevents automatic token refresh, and `GH_TELEMETRY=false` prevents the
   device-id write otherwise seen under `$XDG_STATE_HOME/gh` (or
   `~/.local/state/gh`). The phase and verify script use
   `gh auth status --no-refresh` with `GH_TELEMETRY` forced to `false`,
   discard the output, and never pass `--show-token`. The verifier also forces
   telemetry off for `gh --version`, because that command writes the device-id
   as well. A user's configured telemetry setting is overridden only for those
   probe commands.

9. `gh auth setup-git` configures Git's credential helper for every
   authenticated host and fails when no host is authenticated. `gh auth login`
   is an interactive browser flow; it stores the token in the system credential
   store, or falls back to a plain-text file when no store is available. Phase 4
   offers both commands but never reads a credential file or a token.

10. The four GitHub task commands are documented: `gh pr create --web` opens the
    pull-request creation page, `gh pr view --web` opens the current branch's
    pull request, `gh repo view --web` opens the current repository, and
    `gh run list` lists recent workflow runs.

11. Phase 4 was checked with `bash -n` and shellcheck 0.11.0 (extracted from the
    Fedora RPM, not installed system-wide) on `phases/04-git.sh` and
    `scripts/verify.d/04-git.sh`. `python3 lib/zed_config.py --check
    --config-dir config` accepted the settings and tasks fragments and the
    existing test suite passed.

12. `./install.sh --dry-run --yes --phase 4` ran with a temporary `HOME` and
    every relevant `XDG_*`, `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL` and
    `GIT_CONFIG_SYSTEM` variable unset. It exited 0, printed the planned
    commands and config diffs, and created no files in the temporary `HOME`.
    The only file there was the shell redirection used to capture the output.
    Before the `GH_TELEMETRY=false` change, the same check created
    `.local/state/gh/device-id`; that side effect is now gone.

13. A sandbox `./install.sh --yes --phase 4` with the same temporary `HOME`
    wrote `.gitconfig` with all five values, installed
    `.config/git/ignore`, merged the Git settings and all nine tasks, and
    recorded `PASS` for `git-package`, `gh-package`, `git-config`, `git-ignore`,
    `git-settings` and `git-tasks`. With `--yes` and no interactive terminal it
    left `user.name` and `user.email` unset and recorded `SKIP` for
    `git-identity`; `gh auth status` found no login and recorded `SKIP` for
    `gh-auth`. It did not run `dnf install`, `gh auth login`,
    `gh auth setup-git` or any real configuration write. A second identical run
    also exited 0; it skipped identical Git defaults and kept the existing
    ignore file without rewriting it, recording `PASS` because the expected
    patterns were present. A separate sandbox with a pre-existing
    `.config/git/ignore` containing `# my custom ignore` and `*.log` exited 0,
    recorded `SKIP` for `git-ignore`, and left the file byte-for-byte unchanged
    (matching SHA-256 before and after).

14. A controlled fake `gh` (status exit 0, `setup-git` logged its arguments)
    exercised the logged-in branch without real credentials. The phase ran
    `gh auth setup-git`, recorded `PASS` for `gh-auth`, and the verifier
    reported `PASS gh-auth`. Against the sandbox without that fake,
    `scripts/verify.d/04-git.sh` reported `PASS` for `git-cli`, `gh-cli`,
    `git-config`, `git-ignore`, `git-settings`, `git-tasks-fragment` and
    `git-tasks`, and `SKIP` for `gh-auth`. It reported `FAIL git-identity`
    because both identity values were unset. That failure is intentional: the
    verifier does not invent an identity, and a real user must set one. The
    interactive identity prompt itself was not exercised.

## Assumptions that are not verified

### 1. `XDG_CONFIG_HOME`

The target is hard-coded to `${HOME}/.config/zed`, matching the documented Linux
path. Whether Zed follows `XDG_CONFIG_HOME` instead when that variable is set
was **not** verified. If it does, the installer would write a tree that Zed
does not read.

Check before relying on this:

```bash
printf 'XDG_CONFIG_HOME=%s\n' "${XDG_CONFIG_HOME:-<unset>}"
ls -ld ~/.config/zed "${XDG_CONFIG_HOME:-$HOME/.config}/zed" 2>/dev/null
```

If `XDG_CONFIG_HOME` is set, confirm where Zed actually reads and writes its
configuration (for example with Zed's Settings Editor and a test change) before
running a later phase. Phase 1 itself writes no Zed configuration.

### 2. Trailing commas in existing files

Zed's documentation explicitly shows JSONC comments; it was not separately
verified that all three files accept trailing commas in every Zed version. The
parser accepts trailing commas in fragments and in existing files as a
convenience. Generated `settings.json`, `keymap.json` and `tasks.json` are
strict JSON with no trailing commas, so output does not depend on this
assumption. Reading an existing file with trailing commas assumes the installed
Zed already accepted that file. If in doubt, remove the commas first.

### 3. No Zed schema validation

`lib/zed_config.py` validates JSON/JSONC syntax and the top-level type of each
file (object for settings and snippets, array for keymap and tasks). It does not
know Zed's schema. It cannot tell whether a setting key, value, keybinding
action, context, task field or snippet field is valid for the installed Zed
version. A syntactically valid file can still be rejected or ignored by Zed.

Every future fragment must be checked against the current Zed documentation and
the installed Zed's Settings Editor/command palette before it is shipped. A
successful `--check` only means "this is valid JSON of the expected shape".

### 4. Merge semantics

The merge rules are this repository's rules, not necessarily Zed's rules:

- Settings objects merge recursively; later lists and scalars replace earlier
  ones.
- Keymap arrays are concatenated and only **exact** canonical-JSON duplicates
  are removed.
- Task arrays merge by `label`; a later task with the same label replaces the
  earlier task in place.
- Snippets are copied as whole files; there is no per-snippet merge.

If a user already binds the same key to a different action, both keymap entries
remain and Zed's precedence rules decide the winner. That precedence was not
verified. Likewise, duplicate task labels in an existing file have unspecified
handling; the engine indexes the last occurrence it sees. Review `--dry-run`
output before applying fragments to a non-empty configuration.

### 5. Comments and formatting are lost on rewrite

`settings.json`, `keymap.json` and `tasks.json` are parsed as JSONC but
rewritten as plain, indented JSON. Comments and original formatting in a
rewritten file are lost. The engine prints a warning and `install.sh` makes a
backup first. Snippet files are copied byte-for-byte, so comments in a snippet
source are preserved in the destination copy.

### 6. Fragment and snippet file selection

Only regular files ending in `.json` are read from `config/settings.d/`,
`config/keymap.d/`, `config/tasks.d/` and `config/snippets/`. Files in those
directories with other extensions (including `.jsonc`) are ignored. Snippet
collection is not recursive. Fragments are processed in filename sort order.
Input files must be UTF-8 (an optional BOM is accepted); other encodings are
reported as errors.

### 7. Backup scope and symlinks

Only `~/.config/zed` is backed up. Zed data outside that directory is not
covered, and no checksum is taken after copying. `backup_zed_config` refuses a
`~/.config/zed` that is itself a symbolic link: `cp -a` would copy the link
rather than the configuration, and a restore could put back a stale link. It
also refuses a path that exists but is not a directory. Move the link or file
aside or back up its target manually. Symlinks *inside* the config tree
are preserved by `cp -a`, but an atomic write to a path that is a symlink
replaces the link with a regular file rather than writing through it.

### 8. Backups and restore are not transactional

The backup is a `cp -a` copy; a failure partway through leaves a partial backup
directory (the installer then refuses to apply configuration). Restore moves
the current `~/.config/zed` to `backups/pre-restore-<timestamp>/zed` and then
copies the selected backup into place. If that copy fails, the old tree is still
in the pre-restore directory. Restore does not verify checksums or validate the
backup's contents beyond requiring a non-empty source. Inspect a backup before
restoring it if it came from somewhere else.

Restore also accepts any non-empty directory as a direct config tree. It does
not prove that the directory actually is a Zed configuration.

### 9. Filesystem and permissions

Atomic writes use a temporary file in the target directory, `fsync` the file,
then `os.replace`. This protects against a process crash leaving a half-written
file; it does not guarantee durability after a power loss because the directory
itself is not fsynced. The target is assumed to be a local filesystem with
normal `rename` semantics; NFS, FUSE and other unusual mounts were not tested.

An existing file's permission bits are preserved; new files are created with
mode `0644`. Ownership (assumed to be the same user), ACLs, extended attributes
and SELinux labels are not explicitly preserved. Backups and restores use
`cp -a`, which preserves the metadata it supports.

### 10. Restore selection and timestamps

`--restore` without a directory picks the last `backups/zed-*` entry in
lexicographic order. Timestamps use the local clock in
`YYYYMMDD-HHMMSS` form, so they normally sort chronologically. A clock change
or several runs in the same second (which get a `-PID` suffix) can make the
"newest" choice ambiguous. Pass the backup directory explicitly when it
matters.

### 11. Concurrency and trusted input

There is no lock. Do not run two installer instances at once against the same
repository or Zed config. Phase scripts are sourced shell code and `step_cmd`
evaluates a check string; both are trusted repository code, not untrusted user
input. Review phase files before running them. Logging assumes `logs/` is
writable; if it is not, terminal output still works but results cannot be
recorded and `record_result` fails.

### 12. No uninstaller

There is no automatic uninstall. Restore the Zed config from a backup and remove
packages or files manually if a later phase installed them. Phase 2 installs
native Zed and a font; neither is removed by this repository. The dotfiles
hookup can be undone with `stow -D zed` from the dotfiles repository, but the
phase does not provide that command or run it automatically.

### 13. Flatpak warning is conservative

Phase 2 warns that Flatpak confinement can hide language servers, toolchains and
project paths, and never removes `dev.zed.Zed`. Current Zed documentation also
says the Flatpak integration exits the sandbox on startup, so the exact effect
depends on the Zed and Flatpak versions and the granted permissions. No Flatpak
Zed was run in the verification environment, so the warning is intentionally
conservative rather than a measured statement about the current Flatpak build.
The probe queries the system installation, and the user installation only when
`~/.local/share/flatpak` already exists, with an isolated `XDG_CACHE_HOME`; it
does not create a user Flatpak repository merely to check. Check it with:

```bash
flatpak run dev.zed.Zed --version
```

Then open a project in the Flatpak build and confirm that its language servers
and toolchains are visible. Native Zed is the supported path for this
repository.

### 14. `buffer_font_features` on Linux

The Zed settings reference marks `buffer_font_features` as macOS and Windows.
Phase 2 sets `{"calt": true}` to request contextual alternates (the usual
ligature switch), and sets the same family for the terminal. Whether Linux Zed
honors this OpenType feature, and whether the terminal inherits buffer ligature
settings, was not verified. If ligatures do not appear, check the Settings
Editor autocomplete and test with a sequence such as `->` or `!=`. The font
family itself is verified through `fc-list`; rendering is not.

### 15. Font archive source and checksum

The font URL is the mutable `releases/latest/download` URL. The phase verifies
that the archive is non-empty, contains at least one `.ttf`, and has no absolute
or parent-traversal member paths, but it does **not** verify a checksum or a
signature. A compromised upstream release or a changed "latest" asset would be
trusted. For reproducible installs, replace the URL with a versioned asset and
add a checksum check. The archive was 98 top-level `.ttf` files on 2026-11-16;
that count is not enforced.

If a different JetBrainsMono Nerd Font version is already installed elsewhere,
`fc-list` reports it and phase 2 skips the download. The phase does not compare
versions or remove older font files from
`~/.local/share/fonts/JetBrainsMonoNerdFont`.

### 16. Zed installer source and checksum

The Zed installer is downloaded from `https://zed.dev/install.sh` over HTTPS and
run with `sh`. No checksum or signature is checked. The installer may change
outside this repository's control and may write outside `~/.config/zed` (for
example `~/.local/zed.app` and `~/.local/bin/zed`); those files are not covered
by the repository's Zed config backups or `--restore`. Review the downloaded
script before approving the step if this matters.

### 17. PATH edits are append-only and shell-specific

Phase 2 appends the exact line it prints to `~/.bashrc`, `~/.zshrc` or
`~/.config/fish/config.fish`. It only edits a shell's file when the shell binary
is installed, and it only skips when the exact line is already present. It does
not update the current shell, does not edit `.profile` or `.bash_profile`, and
does not recognize every alternative way of adding `~/.local/bin`. A duplicate
line is possible if another form already exists but the current shell still
lacks the directory. Restart the shell or source the rc file to apply the
change.

### 18. Dotfiles hookup and GNU Stow semantics

The optional hookup manages only `settings.json` and `keymap.json`; it does not
copy `tasks.json` or `snippets/`. It refuses to continue when a target file
already exists, even if the contents are identical, and it treats a live
symlink that points somewhere else as a conflict. A live symlink that already
points at the package file is recognized as already stowed.

The phase backs up the live Zed directory to
`backups/zed-<timestamp>/zed/` and an existing package directory to
`backups/dotfiles-<timestamp>/zed/`, then copies the generated files, moves the
live copies to `backups/pre-stow-<timestamp>/zed/`, and runs:

```bash
stow --no-folding --dir "<dotfiles>" --target "$HOME" zed
```

Stow 2.4.1 is the Fedora package version checked. If stow fails, the phase moves
the generated live files back from the pre-stow backup, but the copies already
written into the dotfiles package remain, and stow may have created some links
before failing. Inspect both backup directories and the dotfiles package before
rerunning. The phase does not run `stow -D` automatically.

The package layout is `<dotfiles>/zed/.config/zed/...`. A dotfiles repository
that uses a different layout, a stow target other than `$HOME`, or a package
name other than `zed` is not supported by this hookup. Folding is disabled
deliberately so stow links individual files inside `~/.config/zed`; the behavior
of `stow --no-folding` is taken from GNU Stow's documented options.

### 19. Symlinked settings and atomic writes

If `settings.json` is a symlink and the repository fragments introduce no
changes, phase 2 leaves the symlink and the file untouched. If changes are
pending, it asks before applying them; an approved apply uses the config
engine's atomic write, which replaces the symlink with a regular file rather
than writing through it. The stowed copy is not updated by that write.

If the dotfiles hookup then finds an existing package file, it aborts on the
conflict instead of overwriting it. To recover, update or remove the old package
file, rerun the hookup, or restore the symlink with `stow zed`. This interaction
is a consequence of the safe-write and no-overwrite rules, not a supported
automatic migration.

`backup_zed_config` refuses a `~/.config/zed` that is itself a symlink, for the
same reason described in section 7. The phase skips config apply or the dotfiles
hookup in that case rather than faking a backup.

### 20. Verification scope

`scripts/verify.d/02-base.sh` proves that:

- a native `zed` binary exists and `zed --version` exits successfully;
- `fc-list` reports the `JetBrainsMono Nerd Font` family;
- `~/.config/zed/settings.json` is parseable JSONC with an object at the top
  level;
- every leaf in `config/settings.d/02-base.json` is present with the same value;
- `~/.editorconfig` contains the expected lines;
- `settings.json` is a symlink when the optional stow hookup is present.

It does not launch a GUI, prove that Zed renders the font, prove that Zed
accepts every setting key at runtime (the config engine checks JSON shape, not
Zed's schema), or prove that a stow package is complete. Those require an
interactive Zed session.

### 21. Extension auto-install timing

Zed documents `auto_install_extensions`, and phase 3 writes both theme IDs to it.
The phase assumes Zed performs that install on its next start, before or while it
loads the theme list. The verification machine did not have either theme
extension installed, so the actual download timing and any failure mode were not
observed. The phase therefore treats a missing extension as a fallback, not a
failure: it writes a bootstrap fragment, leaves the default theme active and
exits 0.

Check with:

```bash
./install.sh --phase 3
# start Zed once, wait for the extension download, then:
ls -la "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed/tokyo-night" \
       "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed/zedokai"
./install.sh --phase 3
```

### 22. Flatpak extension data path

The native extension root is documented as `$XDG_DATA_HOME/zed/extensions` or
`~/.local/share/zed/extensions`. Phase 3 also checks
`~/.var/app/dev.zed.Zed/data/zed/extensions/installed` as a Flatpak fallback.
That path follows the Flatpak per-app data convention but was **not** verified
with a Flatpak Zed installation; `dev.zed.Zed` was not installed on the
verification machine. Phase 2 already warns that Flatpak confinement can hide
language servers and toolchains.

Check with:

```bash
flatpak run --command=sh dev.zed.Zed -c 'printf "%s\n" "$XDG_DATA_HOME"'
ls -la ~/.var/app/dev.zed.Zed/data/zed/extensions/installed 2>/dev/null
```

### 23. Theme overrides on extension themes

Zed documents `theme_overrides` keyed by a theme name, and the generated shape
matches the documented `syntax` and `accents` example. The verification did not
launch Zed, so it did not observe an extension theme being overridden at runtime,
nor how Zed resolves a conflict between an override and a theme's own syntax
block. The exact key `Tokyo Night` was read from the installed theme JSON.

Check with the Settings Editor or a test buffer after the extensions install;
the keyword/string/function/comment colours in `docs/THEME.md` are the expected
result.

### 24. Capture coverage

The overrides cover 96 capture names found in the two theme JSON files plus a
verified core set. Tree-sitter languages can introduce capture names that are
not in those files. Such a capture keeps the Tokyo Night theme's own colour
rather than the neutral `#f8f8f2`; it is not an error, but it can show a
non-Monokai accent. Add a capture to `ROLES`/`FALLBACK_SYNTAX_KEYS` in
`lib/theme_build.py` and regenerate if a language needs it.

Check which captures a theme defines with:

```bash
python3 - <<'PY'
import json
from pathlib import Path
for path in [Path.home() / ".local/share/zed/extensions/installed/tokyo-night",
             Path.home() / ".local/share/zed/extensions/installed/zedokai"]:
    for file in path.rglob("*.json"):
        data = json.loads(file.read_text())
        for theme in data.get("themes", []):
            syntax = theme.get("style", {}).get("syntax", {})
            print(file, theme.get("name"), len(syntax))
PY
```

### 25. Semantic token version gate

`semantic_tokens` and its `off`/`combined`/`full` values were verified against
Zed 1.27.0 and re-checked in Zed 1.28.1. Phase 3 writes the key only for Zed
1.27.0 or newer. Older Zed releases may support it, and a future release may
rename it; the phase deliberately skips rather than guessing. The version
comparison extracts the first numeric dotted version from `zed --version`
(for example `1.28.1` from `Zed 1.28.1 <commit>`) and compares it with
`sort -V`, which assumes a numeric semantic version.

Check with:

```bash
zed --version
python3 lib/theme_build.py check \
  --fragment config/settings.d/03-theme.json \
  --docs docs/THEME.md \
  --keymap config/keymap.d/03-theme.json \
  --settings ~/.config/zed/settings.json
```

### 26. No GUI verification

`scripts/verify.d/03-theme.sh` proves the files, extension directories, JSONC
shape, hex colours, contrast table and selected theme names. It does not prove
that Zed renders the Tokyo Night chrome, that the theme selector opens, that
`ctrl-alt-t` is free of a user keybinding, or that every language renders every
capture. Those require an interactive Zed session.

### 27. GitHub CLI login and credential helper

`gh auth login` and `gh auth setup-git` were **not** run against a real GitHub
account. The phase knows from the manual that login is interactive and that
`setup-git` writes credential-helper configuration for authenticated hosts, but
it did not observe the browser flow, the credential-store choice, an enterprise
host, or a successful HTTPS push through the helper. It also did not test the
plain-text fallback that `gh` uses when no credential store exists.

The phase never runs `gh auth token`, never reads a credential file and never
prints a token. It checks only the exit status of
`gh auth status --no-refresh`, with `GH_TELEMETRY` forced to `false` for that
command. Starting `gh auth login` or `gh auth setup-git` still requires a
separate yes/no answer and a terminal.

`GH_TOKEN` and `GITHUB_TOKEN` are not unset or inspected. A token in the
environment can change which account `gh` uses or whether a command works, and
the phase cannot tell that from a stored login. If login or pushes behave
unexpectedly, check the environment first without printing the value:

```bash
printenv GH_TOKEN >/dev/null && echo "GH_TOKEN is set" || echo "GH_TOKEN is unset"
printenv GITHUB_TOKEN >/dev/null && echo "GITHUB_TOKEN is set" || echo "GITHUB_TOKEN is unset"
GH_TELEMETRY=false gh auth status --no-refresh
git config --global --get-all credential.helper
git config --global --get-regexp '^credential\.'
```

Do not use `gh auth status --show-token` in a shared terminal or a log.

### 28. Git identity is user-supplied

The phase asks for `user.name` and `user.email` only when the global value is
empty, and it never generates a placeholder. The interactive prompt was not
exercised in the sandbox because `--yes` disables it. The value is read as one
line, leading and trailing whitespace is trimmed, and the remaining text is
stored verbatim. No email syntax check is performed; Git accepts most strings,
and a wrong but syntactically valid address will be used in commits.

If either value is missing, `scripts/verify.d/04-git.sh` reports
`FAIL git-identity` (and the phase itself records `SKIP`). That is deliberate:
the verifier should not pretend an identity exists. Set the values in a real
terminal, then rerun the verifier:

```bash
./install.sh --phase 4
git config --global --get user.name
git config --global --get user.email
bash scripts/verify.d/04-git.sh
```

Changing an existing identity is intentionally not offered; edit it yourself
with `git config --global user.name "..."` and
`git config --global user.email "..."`.

### 29. Global Git configuration file location

`git config --global` does not always write `~/.gitconfig`. Git writes
`$XDG_CONFIG_HOME/git/config` when `~/.gitconfig` does not exist and that XDG
file does; it can also be redirected by `GIT_CONFIG_GLOBAL`, and `include.path`
or `includeIf` entries can change the values Git reports. The phase lets Git
choose the file and reads values back through `git config`, so it does not
assume a particular path. It does **not** back up `~/.gitconfig`,
`$XDG_CONFIG_HOME/git/config` or the global ignore file. Only `~/.config/zed` is
covered by the repository's backup and restore.

Review and back up these files yourself before approving an overwrite,
especially if the existing value comes from an included file:

```bash
printf 'GIT_CONFIG_GLOBAL=%s\n' "${GIT_CONFIG_GLOBAL:-<unset>}"
git config --global --show-origin --get init.defaultBranch
git config --global --show-origin --get user.name
git config --global --list --show-origin
ls -l ~/.gitconfig "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" 2>/dev/null
```

The `--show-origin` output names the file Git actually used.

### 30. `core.editor "zed --wait"` depends on `PATH`

Zed documents the command, but the phase does not verify that the `git` process
can find `zed` or that `--wait` keeps the editor open until the commit message
is written. Phase 2 appends `~/.local/bin` to shell rc files, but an already
running terminal, a desktop launcher, an IDE terminal or a non-login shell may
not have that directory on `PATH`. In that case `git commit` fails to launch the
editor.

Check in the same environment that runs Git:

```bash
command -v zed || ls -l ~/.local/bin/zed
git config --global --get core.editor
git var GIT_EDITOR
```

If `zed` is not found, add `~/.local/bin` to the environment that launches Git,
or set `core.editor` to an absolute path.

### 31. `gh auth status` is a coarse, multi-host check

The manual says `gh auth status` exits 1 if an account on **any** checked host
has authentication issues. The phase treats any non-zero exit as "not logged
in". With a healthy `github.com` login and a broken enterprise or secondary
host, the phase may therefore offer `gh auth login` even though GitHub.com is
usable. Conversely, it never inspects which account is active, so a login for
the wrong account still reports `PASS`.

The check uses `--no-refresh`, so an expired or near-expiry token is **not**
refreshed by the phase or by the verifier. That keeps the check read-only, but
it also means a token that would refresh successfully can still show as logged
out. Run `gh auth status` yourself (without `--no-refresh`) if you want the
manual's refresh behavior:

```bash
GH_TELEMETRY=false gh auth status --no-refresh
printf 'exit=%s\n' "$?"
gh auth status
```

### 32. Global ignore patterns are opinionated

The template applies to every repository on the machine, not only this project.
`build/`, `dist/`, `out/`, `target/`, `.idea/`, `.vscode/`, `venv/` and similar
entries are common conventions, but a repository may intentionally track one of
those paths. Git ignore rules only affect untracked files; already tracked
files are not removed. The phase never overwrites an existing
`${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore` and never merges new patterns
into it. An existing file that already contains `*.py[cod]` and `.venv/` is
recorded as `PASS`; any other existing file is recorded as `SKIP`.

The file is used only when `core.excludesFile` is unset. If it is set, the
phase's file is inert. Check which path Git uses and test a pattern in a scratch
repository:

```bash
git config --global --get core.excludesFile || echo "using the default path"
ls -l "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
tmp="$(mktemp -d)"; git -C "$tmp" init -q
mkdir -p "$tmp/build" "$tmp/.venv"
git -C "$tmp" check-ignore -v build/ .venv/
rm -rf "$tmp"
```

Delete or edit the file by hand if the patterns are too broad; there is no
automatic uninstall.

### 33. Task terminal interactivity

The task docs say tasks run in the integrated terminal with the project root as
the default `cwd`, but the phase did not launch Zed and observe the tasks. The
new-branch task runs
`bash -c "read -r -p 'New branch name: ' branch && git switch -c \"$branch\""`,
so it needs an interactive stdin and `bash` on `PATH`. If the terminal is not
interactive, the task is cancelled or the shell closes stdin, the `read` fails
and no branch is created. `use_new_terminal: false` reuses the current task tab
and `reveal: always` focuses it; with the default `allow_concurrent_runs: false`,
a second run waits for the first to finish.

Task labels are merged by exact label. A user task with the same label is
replaced by the phase-4 task. Spawn each task once from **task: spawn** and
confirm the prompt, working directory and output:

```bash
command -v bash
sed -n '1,80p' config/tasks.d/04-git.json
```

## Intentional phase 1 omissions

These describe phase 1 itself; phases 2, 3 and 4 add some of the items below.

- Phase 1 itself adds no `phases/NN-name.sh` files; only
  `phases/00-template.sh.example` belongs to phase 1.
- No Zed installation, no Zed launch and no minimum Zed version claim in
  phase 1.
- No live settings, keymap, tasks or snippet fragments in phase 1. The
  `config/*.d` directories contained only `.gitkeep`; `config/snippets` was
  empty.
- No extension IDs, language servers, formatters, debuggers or toolchains.
- No Fedora package installation in phase 1. `jq` appears only in the template
  example.
- No shellcheck result in phase 1: shellcheck was not installed, and phase 1
  does not install it. `make lint` runs `bash -n` and reports shellcheck as
  skipped.
- No license file.
- No CI configuration and no release packaging.
- No automatic check that Zed accepts the generated files; that requires Zed
  and belongs to a later phase.

## Intentional phase 2 omissions

- No theme, syntax colors or theme overrides. Phase 3 owns those.
- No icon theme extension and no change to Zed's default outline icon set.
- No extensions, language servers, formatters, debuggers or toolchains.
- No keybinding additions: `config/keymap.d/02-base.json` is `[]`.
- No shell installation. zsh and fish rc files are offered only when those
  shells are already installed.
- No Flatpak removal or Flatpak configuration changes.
- No checksum or signature verification for the Zed installer or the Nerd Font
  archive.
- No automatic uninstaller for Zed, the font, the `.editorconfig`, or a stow
  package.
- No per-project `.editorconfig`; only `~/.editorconfig` is installed.
- No `XDG_CONFIG_HOME` support; the target remains `~/.config/zed`.
- No terminal font features or font-size changes; only the terminal font family
  and dock are set.
- No automatic GUI check that Zed renders the font or accepts the settings.

## Intentional phase 3 omissions

- No light-mode Monokai overrides. `theme_overrides` is keyed only by
  `Tokyo Night`, so `Tokyo Night Light` keeps its own syntax colours. The phase
  selects it only as the light theme.
- No overrides for UI chrome beyond the Tokyo Night theme itself. Only syntax
  captures and the six bracket `accents` are overridden; panels, tabs, borders
  and selection keep the Tokyo Night theme's values.
- No language-specific syntax overrides. The capture mapping is global.
- No icon theme extension and no icon changes.
- No language servers, formatters, debuggers or toolchains.
- No CLI extension installation. Zed has no verified install-extension command,
  so the phase uses `auto_install_extensions` and waits for Zed's next start.
- No checksum or signature check of the extension download; Zed's extension
  manager performs the download.
- No GUI check that the theme selector opens, that `ctrl-alt-t` has no
  user-specific conflict, or that the rendered palette matches the table.
- No per-project theme configuration; only user settings are changed.
- No update of the committed `docs/THEME.md` table on a bootstrap run. The
  generator leaves the verified table in place when the theme JSON is missing.
- No system-wide shellcheck installation. Phase 3 used the 0.11.0 binary
  extracted from the Fedora RPM, matching the phase-2 method; `make lint` still
  reports shellcheck as skipped when it is not on `PATH`.

## Intentional phase 4 omissions

- No SSH key generation, upload, commit signing or GPG/SSH signing setup. The
  phase only configures Git and offers the GitHub CLI login.
- No repository initialisation, clone, remote creation or first commit.
- No token creation, `gh auth token`, credential-file read, `GH_TOKEN`/
  `GITHUB_TOKEN` management or secret storage. `gh auth login` is left to the
  user and its token is never inspected.
- No change to `core.excludesFile`. The optional global ignore file is installed
  only at Git's documented default path and is never merged or overwritten.
- No backup of `~/.gitconfig`, `$XDG_CONFIG_HOME/git/config`, the global ignore
  file, the `gh` configuration or a credential store. Only `~/.config/zed` is
  covered by `--restore`.
- No Git LFS, hooks, aliases, submodules, worktrees, rerere autoupdate, signing,
  credential-cache settings, `includeIf`, per-repository configuration or
  advanced merge/push strategy beyond the five listed defaults.
- No global `gh` extensions, aliases, configuration edits or upgrades.
- No Git or GitHub keybindings. Phase 4 ships settings and tasks only; the
  keymap fragments are untouched.
- No graphical verification that the Git panel moves, inline blame appears,
  gutter indicators render or a task's terminal accepts input.
- No `dnf install` in the verification environment, no real `gh auth login`, no
  real `gh auth setup-git`, and no live write to the real `~/.gitconfig`,
  `~/.config/git/ignore` or `~/.config/zed`. The package-install branch is
  exercised only when a package is missing, which was not the case here.
- No macOS or Windows support; the paths and shell behaviour are Linux-specific.

## How to re-check the unverified items

```bash
# Platform and tools
grep -E '^(ID|VERSION_ID|PRETTY_NAME)=' /etc/os-release
uname -m
bash --version
python3 --version
command -v shellcheck || echo "shellcheck absent"

# Fedora package names (read-only)
dnf info jq stow fontconfig
rpm -q jq curl tar xz fontconfig
command -v stow || echo "stow not installed"

# Native Zed and Flatpak detection
zed --version
command -v zed || ls -l ~/.local/bin/zed
flatpak list --app --columns=application

# Nerd Font release and installed family
curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["tag_name"]); [print(a["name"], a["size"], a["browser_download_url"]) for a in d["assets"] if a["name"] == "JetBrainsMono.tar.xz"]'
fc-list : family | grep -i 'JetBrainsMono Nerd Font' || echo "family not listed"
fc-cache -f
fc-list : family | grep -i 'JetBrainsMono Nerd Font' || echo "family still not listed"

# JSONC and merge engine, without writing Zed config
python3 lib/zed_config.py --check --config-dir config --zed-dir ~/.config/zed
python3 config/templates/test/test_zed_config.py

# Preview phase 2; writes only logs
./install.sh --dry-run --phase 2

# Optional dotfiles hookup preview
ZF_DOTFILES_REPO="$HOME/dotfiles" ./install.sh --dry-run --phase 2

# Phase 3: extension discovery, fragment and docs checks, then a safe preview
ls -la "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed"
python3 lib/theme_build.py status \
  --installed-dir "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed"
python3 lib/theme_build.py check \
  --fragment config/settings.d/03-theme.json \
  --docs docs/THEME.md \
  --keymap config/keymap.d/03-theme.json
./install.sh --dry-run --phase 3
bash scripts/verify.d/03-theme.sh

# After phase 3 has been applied, check the live theme and keybinding
python3 lib/theme_build.py check \
  --fragment config/settings.d/03-theme.json \
  --docs docs/THEME.md \
  --keymap config/keymap.d/03-theme.json \
  --live-keymap ~/.config/zed/keymap.json \
  --settings ~/.config/zed/settings.json \
  --installed-dir "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed"
grep -n 'theme_selector::Toggle\|Tokyo Night' ~/.config/zed/settings.json \
  ~/.config/zed/keymap.json 2>/dev/null

# Re-check the pinned extension evidence
curl -fsSL https://api.zed.dev/extensions/tokyo-night | python3 -m json.tool | head -40
curl -fsSL https://api.zed.dev/extensions/zedokai | python3 -m json.tool | head -40

# Phase 4: package, Git and gh evidence (read-only)
dnf info git gh
git --version
gh --version
git config --global --list --show-origin --show-scope |
  grep -E '(init\.defaultBranch|pull\.rebase|push\.autoSetupRemote|core\.editor|rerere\.enabled|user\.name|user\.email|core\.excludesFile)='
GH_TELEMETRY=false gh auth status --no-refresh >/dev/null 2>&1
printf 'gh auth status exit: %s\n' "$?"
git config --global --get-all credential.helper
command -v zed || ls -l ~/.local/bin/zed

# Phase 4: fragments, dry run and sandbox verification
python3 lib/zed_config.py --check --config-dir config
./install.sh --dry-run --phase 4
bash scripts/verify.d/04-git.sh

# Phase 4 global ignore: inspect and test in a scratch repository
git config --global --get core.excludesFile || echo "using the default path"
ls -l "${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
tmp="$(mktemp -d)"; git -C "$tmp" init -q
mkdir -p "$tmp/build" "$tmp/.venv"
git -C "$tmp" check-ignore -v build/ .venv/
rm -rf "$tmp"

# After phase 4 has been applied, confirm the live Zed settings and tasks
grep -n 'git_panel\|inline_blame\|git_gutter' ~/.config/zed/settings.json
grep -n '"label": "Git:\|"label": "GitHub:' ~/.config/zed/tasks.json

# Inspect the applied settings and stow links
python3 -c 'import sys; from pathlib import Path; sys.path.insert(0, "lib"); from zed_config import read_jsonc; read_jsonc(Path.home() / ".config/zed/settings.json"); print("settings.json is valid JSONC")'
ls -l ~/.config/zed/settings.json ~/.config/zed/keymap.json 2>/dev/null
readlink -f ~/.config/zed/settings.json 2>/dev/null
stow --version 2>/dev/null || true

# Compare a backup with the live config
diff -ru ~/.config/zed backups/zed-<timestamp>/zed
diff -ru ~/dotfiles/zed backups/dotfiles-<timestamp>/zed
```

For Zed settings, actions, contexts and extension IDs, use the current
documentation and the installed Zed's Settings Editor and command palette. If a
fact cannot be checked there, leave it out and add a line here explaining what
is missing and how to verify it.
