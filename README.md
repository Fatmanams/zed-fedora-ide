# zed-fedora-ide

A phased, semi-automatic installer that turns the Zed editor into a full IDE
on Fedora Linux. This repository contains **phase 1: the foundation**,
**phase 2: the base setup**, **phase 3: theme and highlighting** and
**phase 4: Git and GitHub**.

Phase 1 deliberately ships **no** Zed settings, keymaps, tasks, snippets,
extensions, fedora packages or language toolchains. It provides the guarded
installer, the stable helper API for phases, the JSONC-aware configuration
merger, backup/restore, logging, verification and tests. Phase 2 adds a small,
verified set of base configuration. Phase 3 adds a Tokyo Night UI with classic
Monokai syntax colours, rainbow brackets, semantic tokens and a theme-selector
keybinding. Phase 4 adds the Fedora `git` and `gh` packages, global Git
defaults and identity prompts, the GitHub CLI login and credential helper, an
optional global git ignore file, Git panel settings and Git/GitHub tasks. Later
phases add language toolchains, more extensions and the remaining IDE behavior.

## What phase 1 delivers

- Fedora Linux / x86_64 guard and a refusal to run the whole installer as root.
- An installer that asks before every mutating step, logs everything, supports
  dry-run, backs up Zed config before the first write, and can restore it.
- A phase framework: `phases/NN-name.sh`, sourced in order, one prompt per
  phase, with a copyable template.
- `lib/common.sh` with the stable helper API used by every later phase.
- `lib/zed_config.py`, standard-library only: JSONC parser (string-aware
  comment and trailing-comma handling), settings deep merge, keymap
  concatenation with exact-duplicate removal, tasks merge by label, snippet
  copying with overwrite protection, atomic writes and validation.
- `scripts/verify.sh` plus ordered checks and a phase-result table.
- A self-contained test suite and JSONC fixtures under
  `config/templates/test/`.

## What phase 2 delivers

- Native Zed installation through the official `https://zed.dev/install.sh`
  script. The Flatpak app `dev.zed.Zed` is detected and warned about (sandbox
  confinement can hide language servers and toolchains); it is never removed.
- A `~/.local/bin` PATH check, with the exact bash, zsh and fish lines printed
  and appended to rc files only after approval.
- [JetBrainsMono Nerd Font](https://www.nerdfonts.com/) from the latest
  `ryanoasis/nerd-fonts` release, installed under
  `~/.local/share/fonts/JetBrainsMonoNerdFont`, refreshed with `fc-cache -f`
  and verified with `fc-list`. A font that fontconfig already sees is skipped.
- A baseline `~/.editorconfig` (UTF-8, LF, final newline, trimmed trailing
  whitespace, 4-space default, 2 spaces for JS/TS/JSON/YAML/Markdown, tabs for
  Makefile and Go) installed only when the file does not exist.
- Verified base Zed settings: the Nerd Font buffer and terminal font, VSCode
  base keymap, panel docks, tab icons and git status, minimap, indent guides,
  breadcrumbs, inlay hints and save hygiene.
- An optional GNU Stow dotfiles hookup: point the installer at a dotfiles
  repository, it copies the generated Zed files into `<dotfiles>/zed/` and runs
  `stow zed`. Existing dotfiles files are never overwritten.
- `scripts/verify.d/02-base.sh` checks the installed binary and version, the
  font, the applied settings and the optional stow link.

Phase 2 does **not** change themes or syntax colors, install an icon theme or
extension, install language toolchains, or add keybindings that the VSCode base
keymap already provides. Those belong to later phases; phase 3 now owns the
theme and highlighting work.

## What phase 3 delivers

- A Tokyo Night user interface from the `tokyo-night` extension, with **`Tokyo
  Night`** selected as the default dark theme and **`Tokyo Night Light`** as the
  light theme.
- Classic Monokai syntax colours applied as `theme_overrides` keyed by the exact
  theme name `Tokyo Night`: keywords and storage `#f92672`, strings `#e6db74`,
  functions and methods `#a6e22e`, numbers and constants `#ae81ff`, comments a
  contrast-safe muted `#76725e`, and everything else `#f8f8f2`.
- A second, full Monokai theme from the `zedokai` extension: **`Zedokai
  Classic`**, one theme-selector keystroke away.
- Both extensions listed in `auto_install_extensions`, with their registry IDs,
  versions, exact theme names and selection evidence recorded in
  [`docs/THEME.md`](docs/THEME.md).
- A Python WCAG contrast check against the Tokyo Night editor background
  `#1a1b26`. Every syntax colour must reach 4.5:1 except comments, which use a
  3.5:1 floor; failing colours are lightened in the same hue. The final table is
  generated into `docs/THEME.md`.
- Rainbow bracket colourisation with the six documented Monokai accents, and
  `semantic_tokens: "combined"` when the installed Zed is at least the verified
  1.27.0 baseline. The same keys and action were re-checked in Zed 1.28.1 on
  2026-11-18.
- A verified `ctrl-alt-t` binding for `theme_selector::Toggle`, plus the
  documented way to switch to full Monokai.
- A bootstrap fallback: if the theme JSON is unavailable, the phase writes only
  `auto_install_extensions` and the highlighting settings, leaves the current
  theme active, logs the reason and exits 0.
- `scripts/verify.d/03-theme.sh` checks the extension directories, the parsed
  overrides, every override colour, the contrast table and the live theme name.

## What phase 4 delivers

- The Fedora `git` and `gh` packages. Both names were verified with
  `dnf info`; the phase offers `dnf install` only when an RPM is missing.
- Global Git defaults: `init.defaultBranch main`, `pull.rebase true`,
  `push.autoSetupRemote true`, `core.editor "zed --wait"` and
  `rerere.enabled true`. An identical existing value is skipped; a different
  value is replaced only after a separate overwrite prompt.
- A Git identity that is **never invented**. If `user.name` or `user.email` is
  unset, the phase asks for it. `--yes`, `--dry-run` and a non-interactive
  terminal leave it unset.
- An optional, interactive `gh auth login` that you complete yourself, followed
  by an optional `gh auth setup-git` so Git uses the GitHub CLI as its
  credential helper. The phase uses `gh auth status --no-refresh` only for its
  exit status, with telemetry disabled for the probe, and never reads, prints or
  stores a token.
- An optional global git ignore file at
  `${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore` with common editor, OS, build
  and virtualenv patterns. An existing file is never overwritten.
- Verified Git panel settings: the panel docked left, inline blame on and gutter
  diff indicators on.
- Nine verified Git/GitHub tasks: status, a 30-commit log graph, pull
  `--rebase`, push, a prompted new branch, `gh pr create --web`,
  `gh pr view --web`, `gh repo view --web` and `gh run list`.
- `scripts/verify.d/04-git.sh` checks both CLIs, the global Git configuration,
  the optional ignore file, the live Git settings, the tasks fragment and the
  GitHub login state. A missing login is reported as `SKIP`, not `FAIL`.

Phase 4 does **not** create an SSH key, sign commits, initialise a repository,
configure a credential helper other than through `gh auth setup-git`, or store
any credential itself.


- Fedora Linux, x86_64. Other distributions and architectures are refused
  politely (checked through `/etc/os-release` and `uname -m`).
- bash 5, python3, dnf, rpm and sudo. These are Fedora defaults and are already
  present on a normal install; no extra dependency is required by phase 1.
- Zed itself is **not** required by phase 1. Phase 2 installs the native build
  when it is missing; an existing native install is reused.
- Phase 2 uses `curl`, `tar`, `xz`, `fontconfig` (`fc-cache`/`fc-list`) and,
  only for the optional dotfiles hookup, GNU Stow. It offers a `dnf install` for
  a missing tool, with a confirmation prompt.
- Phase 3 uses the installed native Zed and its extension mechanism. Zed
  downloads the `tokyo-night` and `zedokai` extensions on its next start, so
  network access is needed then; no additional Fedora package is required.
  `semantic_tokens` is skipped when the installed Zed is older than the verified
  1.27.0 baseline.
- Phase 4 uses `git` and `gh` from Fedora's `fedora` repository and offers to
  install whichever RPM is missing. The GitHub login is interactive and needs
  network access; it is optional, and verification reports `SKIP` when you are
  not logged in.

## Quick start

```bash
cd zed-fedora-ide
make lint
make test
./install.sh --list
./install.sh --dry-run
```

`--list` shows the shipped phases. Files in `phases/*.sh` are executed in
filename order; the `.sh.example` template is ignored. `--dry-run` previews
every step and command without installing or writing anything outside `logs/`.

When phase scripts exist:

```bash
./install.sh             # interactive, asks before each phase and step
./install.sh --dry-run   # show commands and config diffs, change nothing
./install.sh --yes       # approve all prompts
./install.sh --phase 2   # run only phase 02-*.sh
make verify
```

## Flags

| Flag | Meaning |
| --- | --- |
| `--dry-run` | Print planned commands and config diffs. Every mutating helper skips its action. Prompts are auto-approved so this can run unattended. |
| `--yes`, `-y` | Approve every prompt, including overwriting a changed snippet file. |
| `--phase N[,M]` | Run only phases whose filename starts with one of these numbers. `--phase 2` matches `phases/02-anything.sh`. |
| `--list` | List available `phases/NN-*.sh` files and their descriptions, then exit. Cannot be combined with `--phase` or `--restore`. |
| `--restore [BACKUP_DIR]` | Restore a backup. Without a directory, restore the newest `backups/zed-*`. Combine with `--dry-run` to preview. |
| `--help`, `-h` | Print usage. |

`--dry-run` still writes its own log under `logs/`. It does not install
packages, create backups, write Zed config, copy snippets or move/restore files.

Set `ZF_DOTFILES_REPO=/path/to/dotfiles` to select the optional dotfiles hookup
without an interactive path prompt. Leaving it unset and pressing Enter at the
prompt skips the hookup.

## Phase table

| Phase | Scope | Status |
| --- | --- | --- |
| 1 | Foundation: installer, helper API, config engine, backups/restore, verification, tests, docs | **Delivered in this repository** |
| 2 | Base setup: native Zed, JetBrainsMono Nerd Font, `.editorconfig`, base settings, optional dotfiles stow | **Delivered in this repository** |
| 3 | Theme and highlighting: Tokyo Night UI, Monokai syntax overrides, contrast-checked palette, rainbow brackets, semantic tokens, theme-selector keybinding | **Delivered in this repository** |
| 4 | Git and GitHub: `git`/`gh` packages, global Git defaults, GitHub CLI login, optional global ignore file, Git panel settings, Git/GitHub tasks | **Delivered in this repository** |
| 5 | Language toolchains, formatters and LSP setup; every package name verified first | Pending |
| 6 | Additional extensions, settings, keymaps and snippets; every ID/key/action verified first | Pending |
| 7 | End-to-end validation, hardening and final documentation | Pending |

Phase 5+ names are provisional. This repository makes no claim about a package,
extension ID or Zed action that it does not ship. New phases must follow the
truthfulness rules below.

## Repository layout

```text
zed-fedora-ide/
  Makefile
  install.sh
  README.md
  .gitignore
  lib/
    common.sh
    zed_config.py
    theme_build.py       # phase-3 palette generator and checker
  phases/
    00-template.sh.example
    02-base.sh
    03-theme.sh
    04-git.sh
  config/
    settings.d/          # *.json fragments, merged into settings.json
      02-base.json
      03-theme.json
      04-git.json
    keymap.d/            # *.json arrays, concatenated into keymap.json
      02-base.json
      03-theme.json
    tasks.d/             # *.json arrays, merged by task label
      04-git.json
    snippets/            # *.json files copied to ~/.config/zed/snippets/
    templates/
      .editorconfig      # baseline installed as ~/.editorconfig
      gitignore          # optional template for ~/.config/git/ignore
      test/              # JSONC fixtures and the zed_config.py test suite
  scripts/
    verify.sh
    verify.d/            # ordered checks; each prints PASS/FAIL/SKIP lines
      02-base.sh
      03-theme.sh
      04-git.sh
  docs/
    ASSUMPTIONS.md
    THEME.md             # extension evidence, generated palette table, fallbacks
  logs/                  # gitignored runtime logs
  backups/               # gitignored Zed config backups
```

## Conventions

### Phase contract

- Name phases `phases/NN-name.sh` with a two-digit numeric prefix. Only files
  matching `phases/[0-9][0-9]-*.sh` are loaded, in filename order.
- Each phase defines exactly two entry points:
  - `phase_describe` prints one line describing the phase.
  - `phase_run` performs the work.
- Phase files are sourced. Do not perform work at source time, do not call
  `exit`, and do not change shell options. `phase_describe` is also called by
  `--list`, so it must be side-effect free.
- Use `${ZF_PHASE_ID}` (exported by the installer) as the phase name passed to
  `record_result`.
- Return non-zero only for a real failure. Declining a prompt or skipping an
  already-satisfied item returns success; record it as `SKIP`.
- Use only the helper API below for prompts, installs, backups, config writes
  and results. Do not call `sudo`, `dnf`, `cp` or write `~/.config/zed`
  directly.
- Put configuration in fragments under `config/` and call
  `apply_zed_config`; never rewrite Zed files by hand.
- Add a check to `scripts/verify.d/` for every phase that changes the system.
- Test with `./install.sh --dry-run --yes` before running for real.

To start a phase:

```bash
cp phases/00-template.sh.example phases/05-toolchains.sh
chmod +x phases/05-toolchains.sh
./install.sh --list
./install.sh --dry-run --phase 5
```

### Stable helper API

`install.sh` sources `lib/common.sh`; phases inherit these functions. Keep these
names and signatures stable.

| Helper | Behaviour |
| --- | --- |
| `log_info`, `log_warn`, `log_error`, `log_step` | Print to the terminal and append to `logs/install-<timestamp>.log`. |
| `have_cmd NAME` | Success if the command is in `PATH`. |
| `rpm_installed PKG` | Success if `rpm -q PKG` reports the package installed. |
| `is_dry_run` | Success when `--dry-run` is active. |
| `is_yes` | Success when `--yes` is active. |
| `run CMD...` | Print the exact command, log it, and execute it unless dry-run. |
| `ask_yes_no 'question'` | Ask with default No. `--yes` returns success. Dry-run returns success. No interactive TTY returns failure (No). |
| `step_dnf 'description' PKG...` | Skip if every package is installed; otherwise show `sudo dnf install -y ...`, ask, then run it with sudo. A decline is a successful skip. |
| `step_cmd 'description' 'check command' ACTION_FUNCTION` | Skip if the check command succeeds; otherwise show the check/action, ask, then call the function. Dry-run never calls the action. |
| `backup_zed_config` | Copy `~/.config/zed` to `backups/zed-<timestamp>/zed/`, at most once per run. Does nothing if no config exists. |
| `apply_zed_config` | Back up first, ask, then call `lib/zed_config.py` to merge the repository fragments into `~/.config/zed`. |
| `record_result PHASE ITEM STATUS` | Record `PASS`, `FAIL` or `SKIP` in `logs/results-<timestamp>.log` for `verify.sh`. |

Helper behaviour in dry-run: `step_dnf` prints the dnf command but does not run
it, `step_cmd` prints the check/action but does not call the action, and
`apply_zed_config` calls the Python engine with `--dry-run` so it prints diffs.

### Truthfulness rules

These rules apply to every phase:

- **Never guess** Zed setting keys, action names, extension IDs or Fedora
  package names.
- Verify settings, actions and extension IDs against
  [zed.dev/docs](https://zed.dev/docs) and
  [zed.dev/extensions](https://zed.dev/extensions). Verify Fedora package
  names with `dnf info <pkg>` (and `rpm -q <pkg>` for what is installed).
- If something cannot be verified, **skip it**, log it as `SKIPPED`, and add a
  line to [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) saying what is
  unverified, why, and how the user can check it.
- Zed changes often. Prefer the behaviour of the installed Zed version over
  memory: use the Settings Editor/autocomplete, the command palette, the
  installed default keymap and the current extension gallery.
- Do not add an unverified setting "just in case". A smaller verified phase is
  correct; a larger guessed one is not.

Phase 1 itself ships no Zed behavior beyond parsing and writing standard JSON.
The test fixtures use setting names, keymap actions, task variables and snippet
fields that were checked against the official docs on 2026-11-16. The template's
only Fedora package example is `jq`; replace it with verified phase work.

### How settings fragments merge

The sources are:

| Source | Target | Rule |
| --- | --- | --- |
| `config/settings.d/*.json` | `~/.config/zed/settings.json` | Deep merge in filename order. Objects merge recursively; lists and scalars from later fragments win. Keys already in your file but absent from all fragments are preserved. |
| `config/keymap.d/*.json` | `~/.config/zed/keymap.json` | Arrays are concatenated in filename order. Exact duplicate entries are skipped. Existing user entries are kept and fragment entries are appended. |
| `config/tasks.d/*.json` | `~/.config/zed/tasks.json` | Arrays merge by `label`. A later fragment with the same label wins; existing tasks with other labels are preserved. |
| `config/snippets/*.json` | `~/.config/zed/snippets/` | Files are copied. If a destination file differs, the engine asks before overwriting; no TTY means no overwrite unless `--yes`. |

Details:

- Existing `settings.json`, `keymap.json` and `tasks.json` may contain JSONC
  comments and trailing commas; they are parsed correctly. Generated files are
  plain JSON, so comments in a file that is rewritten are lost. The installer
  backs up the config first and the Python engine prints a warning.
- Every rewritten file is written atomically (temporary file in the same
  directory, `fsync`, then `os.replace`), and the generated JSON is parsed
  before it is installed.
- A category is touched only when it has at least one source file. Empty
  fragment directories do not create or rewrite anything.
- `--check` parses and validates the fragments in a category and, when that
  category has fragments, the corresponding existing Zed file. It creates no
  target directory. Categories with no fragments are ignored, so an empty
  repository does not inspect `~/.config/zed`. `--dry-run` prints unified diffs
  and writes nothing.
- When a settings merge changes an existing value, the engine prints
  `CONFLICT <key>: old=... new=...` to stderr. New keys are added without a
  conflict line. A rerun with no semantic changes does not rewrite the file, so
  comments survive.
- The target is fixed to `~/.config/zed` by this repository. See
  `docs/ASSUMPTIONS.md` about `XDG_CONFIG_HOME`.

Example fragment (illustration only):

```jsonc
// config/settings.d/10-editor.json
{
  "buffer_font_size": 15,
  "format_on_save": "on",
}
```

## Phase 2: base setup

Preview it without changing anything, then run it:

```bash
./install.sh --dry-run --phase 2
./install.sh --phase 2
```

Every step is a separate yes/no prompt. Declining a step records `SKIP` and
continues with the next one.

### Order of work

1. Detect a native Zed (either `zed` in `PATH` or `~/.local/bin/zed`).
2. Warn if the Flatpak `dev.zed.Zed` is installed, then install or reuse the
   native build.
3. Check `~/.local/bin` on `PATH`; offer exact bash, zsh and fish rc edits.
4. Check for the JetBrainsMono Nerd Font; download and install it if absent.
5. Install `~/.editorconfig` when the file does not exist.
6. Merge the repository settings fragment into `~/.config/zed/settings.json`.
7. Offer the optional dotfiles/stow hookup.

### Native Zed and Flatpak

The phase uses the official installer at <https://zed.dev/install.sh>. The
script is downloaded to a temporary file and passed to `sh`; it is not piped
into a shell. An existing native install is never reinstalled.

If `flatpak list` reports `dev.zed.Zed`, the phase prints a warning about
sandbox confinement and asks whether to continue. It never removes or modifies
the Flatpak. On current Zed versions the Flatpak integration may itself exit the
sandbox; the warning is deliberately conservative. See
`docs/ASSUMPTIONS.md` for the version caveat.

For `~/.local/bin`, the printed lines are:

```bash
# bash (~/.bashrc) and zsh (~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# fish (~/.config/fish/config.fish)
fish_add_path "$HOME/.local/bin"
```

The installer appends a line only after approval and only when that exact line
is missing. It does not edit an rc file for a shell that is not installed. Run
`exec "$SHELL"` or open a new terminal to pick up the change.

### Nerd Font

Source:
<https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz>.
The archive is downloaded to a temporary directory, its member paths are
checked, and it is extracted into
`~/.local/share/fonts/JetBrainsMonoNerdFont`. The phase then runs `fc-cache -f`
and confirms the family with `fc-list`. If fontconfig already lists
`JetBrainsMono Nerd Font` anywhere on the system, the download is skipped.

### `.editorconfig`

The template is `config/templates/.editorconfig`. It is copied with mode `0644`
only when `~/.editorconfig` does not exist (including as a symlink). It sets
UTF-8, LF, final newline, trailing-whitespace trimming, a 4-space default, 2
spaces for JS/TS/JSON/YAML/Markdown, and tabs for Makefile and Go.

### Base settings

`config/settings.d/02-base.json` contains only keys verified against the Zed
1.27.0 default settings and current documentation:

| Key | Value |
| --- | --- |
| `buffer_font_family` | `JetBrainsMono Nerd Font` |
| `buffer_font_features.calt` | `true` |
| `terminal.font_family` | `JetBrainsMono Nerd Font` |
| `terminal.dock` | `bottom` |
| `base_keymap` | `VSCode` |
| `project_panel.dock` | `left` |
| `outline_panel.dock` | `right` |
| `agent.dock` | `right` |
| `tabs.file_icons`, `tabs.git_status` | `true` |
| `minimap.show` | `always` |
| `indent_guides.enabled` | `true` |
| `toolbar.breadcrumbs` | `true` |
| `inlay_hints.enabled` | `true` |
| `format_on_save` | `on` |
| `remove_trailing_whitespace_on_save` | `true` |
| `ensure_final_newline_on_save` | `true` |

`config/keymap.d/02-base.json` is intentionally an empty array. On Linux,
`Ctrl` + backtick already toggles the terminal panel and `Ctrl+Shift+E` already
focuses the project panel; both are in Zed's default Linux keymap, and the
VSCode base keymap does not redefine them. Phase 2 therefore adds no keybinding
and cannot create a duplicate. See `docs/ASSUMPTIONS.md`.

No theme, syntax color, icon theme or extension setting is written. Zed keeps
its default outline icon set.

If the existing configuration already contains every fragment value, the engine
leaves it untouched. If `settings.json` is a symlink (for example from stow),
the phase does not replace it when no changes are pending; when changes are
pending it asks before replacing the link.

### Optional dotfiles hookup

The hookup is opt-in. Enter a dotfiles repository path at the prompt, or set
`ZF_DOTFILES_REPO`:

```bash
ZF_DOTFILES_REPO="$HOME/dotfiles" ./install.sh --phase 2
```

The phase then:

1. Refuses to continue if any target file (`<dotfiles>/zed/.config/zed/settings.json`
   or `keymap.json`) already exists, unless the live file is already a symlink
   to that exact target. It never overwrites a dotfiles file.
2. Backs up the live Zed config with `backup_zed_config` and copies an existing
   `<dotfiles>/zed` tree to `backups/dotfiles-<timestamp>/zed/`.
3. Copies the generated `settings.json` (and `keymap.json` when it exists) into
   the package.
4. Moves the live copies to `backups/pre-stow-<timestamp>/zed/`.
5. Runs `stow --no-folding --dir "<dotfiles>" --target "$HOME" zed`.
6. Verifies that the live files are symlinks into the package.

If `stow` is missing, the phase offers to install the Fedora `stow` package. A
stow failure restores the moved live files. Files not managed by the package,
such as `tasks.json` or `snippets/`, are left in place. A rerun detects
already-stowed links and records `PASS` without touching anything.

### What phase 2 leaves alone

- No theme or syntax-color settings; those belong to phase 3.
- No icon theme extension; Zed's default outline icons stay.
- No language servers, formatters, debuggers or toolchains.
- No keybindings beyond the VSCode base keymap.
- No Flatpak removal.
- No zsh or fish installation; their rc files are only offered when the shell
  is already installed.

## Phase 3: theme and highlighting

Preview it without changing anything, then run it after phase 2:

```bash
./install.sh --dry-run --phase 3
./install.sh --phase 3
```

Phase 3 writes only theme and highlighting keys; unrelated settings are
preserved by the normal fragment merge. Every write is a separate yes/no prompt.
Declining records `SKIP` and returns success.

The full research record, including the rejected theme candidates and the
generated contrast table, is in [`docs/THEME.md`](docs/THEME.md).

### Order of work

1. Find the native Zed binary and read `zed --version`. Semantic highlighting is
   only written when the version is at least the verified 1.27.0 baseline.
2. Locate the installed extension root dynamically (native XDG data location,
   the `~/.local/share` fallback, or the Flatpak data location) and read the
   theme JSON inside `tokyo-night/` and `zedokai/`.
3. Generate `config/settings.d/03-theme.json` and refresh the palette table in
   `docs/THEME.md` after confirmation.
4. Merge the repository fragments into `~/.config/zed` after confirmation.
5. Check what actually landed in `settings.json` and `keymap.json`, record
   `PASS`/`SKIP`, and explain the next step if an extension is not installed yet.

### Extensions

| Extension ID | Version | Exact themes used | Reason |
| --- | --- | --- | --- |
| `tokyo-night` | 0.9.0 | `Tokyo Night` (dark), `Tokyo Night Light` (light) | Verified Tokyo Night port; its dark editor background is `#1a1b26`, the background used for every contrast check. |
| `zedokai` | 1.2.2 | `Zedokai Classic` | Its classic theme JSON contains the original Monokai keyword/string/function/number colours and neutral `#fdfff1` on `#272822`, so the target palette matches its syntax section. |

Both IDs are added to `auto_install_extensions`. Zed has no verified CLI
command for installing extensions, so the download happens on Zed's next start.
Run phase 3 again after that start to generate the full overrides. The phase
looks under these roots in order and uses the first one that contains either
extension:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed
$HOME/.local/share/zed/extensions/installed
$HOME/.var/app/dev.zed.Zed/data/zed/extensions/installed
```

`Monokai Pro (CE)`, `KTRZ Monokai`, `SuperGreatMonokai` and `Monokai-og` were
rejected because their theme JSON does not use the requested classic mapping;
details are in `docs/THEME.md`.

### Generated settings

`config/settings.d/03-theme.json` is generated by `lib/theme_build.py`:

| Key | Value |
| --- | --- |
| `auto_install_extensions` | `tokyo-night: true`, `zedokai: true` |
| `colorize_brackets` | `true` |
| `semantic_tokens` | `combined` when Zed is at least 1.27.0; omitted otherwise |
| `theme` | `mode: dark`, `dark: Tokyo Night`, `light: Tokyo Night Light` |
| `theme_overrides` | keyed only by the exact name `Tokyo Night` |

The override reads the syntax capture names from the Tokyo Night and Zedokai
theme JSON, maps them to six roles, and applies the fixed target palette:
keywords `#f92672`, strings `#e6db74`, functions `#a6e22e`, numbers and constants
`#ae81ff`, comments the contrast-safe `#76725e`, and everything else `#f8f8f2`.
The six bracket accents are `#f92672`, `#fd971f`, `#e6db74`, `#a6e22e`,
`#66d9ef` and `#ae81ff`.

Every syntax colour is measured against `#1a1b26`. The non-comment floor is
4.5:1 and the comment floor is 3.5:1. The target comment `#75715e` measures
3.48:1, so the generator lightens it within the same hue to `#76725e` at
3.53:1. The rest of the target palette already passes: keyword 4.52:1, string
12.00:1, function 11.02:1, number/constant 6.01:1 and neutral 16.03:1. The
generated table is saved between the markers in `docs/THEME.md`.

### Theme selector and full Monokai

`config/keymap.d/03-theme.json` binds `ctrl-alt-t` in the `Workspace` context to
`theme_selector::Toggle`. The action name is in Zed 1.27.0's and 1.28.1's
default Linux keymaps; `ctrl-alt-t` is unused there and in the VSCode base
keymap. Zed's default `ctrl-k ctrl-t` binding is left in place.

To switch to full Monokai, press `ctrl-alt-t` and choose **`Zedokai Classic`**,
or set `theme.dark` to `Zedokai Classic` (and `theme.light` to `Zedokai Light`)
in `~/.config/zed/settings.json`. Because the overrides are keyed only by
`Tokyo Night`, `Zedokai Classic` uses its own Monokai UI and syntax. Select
`Tokyo Night` again to return to the Tokyo Night UI with the Monokai syntax
overrides.

### Fallback

If the Tokyo Night JSON is missing or unreadable, the generator writes a
bootstrap fragment with only `auto_install_extensions`, `colorize_brackets` and
(where supported) `semantic_tokens`. It writes no `theme` or `theme_overrides`
key, so Zed's current default theme stays active, logs why, records `SKIP` and
exits 0. If only the Zedokai JSON is missing, the syntax overrides still use the
verified target palette and the log names the missing source. The committed
`docs/THEME.md` table is not downgraded to a fallback table.

## Phase 4: Git and GitHub

Preview it without changing anything, then run it after phase 3:

```bash
./install.sh --dry-run --phase 4
./install.sh --phase 4
```

Every step is a separate yes/no prompt. Declining records `SKIP` and continues
with the next step. Identity values are prompted for only when they are unset;
the phase never invents one.

### Order of work

1. Install `git` and `gh` with `dnf` when either RPM is missing.
2. Read `user.name` and `user.email` from the global Git config. Prompt for any
   missing value. A dry run, `--yes` and a non-interactive terminal leave it
   unset instead of guessing.
3. Apply the five global Git defaults. An identical value is skipped; setting a
   new value or replacing a different one needs a separate confirmation.
4. Offer the interactive `gh auth login` and then `gh auth setup-git`.
5. Offer the optional global git ignore file.
6. Merge the settings and tasks fragments into `~/.config/zed`.

### Git defaults

| Key | Value | Purpose |
| --- | --- | --- |
| `init.defaultBranch` | `main` | New repositories start on `main`. |
| `pull.rebase` | `true` | `git pull` rebases instead of creating a merge commit. |
| `push.autoSetupRemote` | `true` | The first push of a new branch sets its upstream. |
| `core.editor` | `zed --wait` | Git uses Zed for commit messages and waits for it. |
| `rerere.enabled` | `true` | Reuses previously resolved conflict hunks. |

The phase writes only the global scope with `git config --global`. It prints
each command through `run()` immediately before executing it and appends it to
the install log. An unset value needs a yes/no confirmation. If a value differs,
the prompt shows the current and proposed values; answer no to keep yours.
`core.editor` assumes `zed` is on the `PATH` of the shell that runs `git`.

`user.name` and `user.email` are not among the five defaults. They are personal
values: the phase asks only when one is missing, and it never reads them from a
remote service or generates a placeholder. To change an existing identity,
run `git config --global user.name "..."` and
`git config --global user.email "..."` yourself.

### GitHub CLI login

The login is interactive and is completed by you:

```bash
gh auth login
gh auth setup-git
```

The phase checks the login with `gh auth status --no-refresh`, with
`GH_TELEMETRY=false` set for the probe, and discards its output; it never runs
`gh auth token`, never reads a credential file and never prints or stores a
token. `--no-refresh` keeps the probe from refreshing a token, and disabling
telemetry keeps `gh` from writing its device-id under `~/.local/state` during a
dry run. `gh auth login` is not launched by `--yes` or without a TTY; run it
yourself in a terminal. `gh auth setup-git` configures Git's credential helper
for the authenticated GitHub hosts, so HTTPS pushes and pulls use `gh`. If you
decline either command, the phase records `SKIP` and leaves your current Git
and `gh` configuration untouched.

### Optional global git ignore

The target is `${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore`, Git's documented
default global excludes file. The phase asks first and **never overwrites** an
existing file or symlink. An existing file that already contains `*.py[cod]`
and `.venv/` records `PASS`; any other existing file is left untouched and
records `SKIP`. The template `config/templates/gitignore` covers:

- editor files such as `*~`, `*.swp`, `*.swo`, `.idea/` and `.vscode/`;
- OS metadata such as `.DS_Store`, `Thumbs.db` and `desktop.ini`;
- build output such as `build/`, `dist/`, `out/`, `target/`, `*.o`, `*.class`,
  `*.py[cod]` and `__pycache__/`;
- virtual environments such as `.venv/`, `venv/` and `env/`.

If you already set `core.excludesFile`, Git uses that path instead. The phase
does not change `core.excludesFile`.

### Generated settings

`config/settings.d/04-git.json` contains only keys verified in Zed's Git
documentation and default settings:

| Key | Value | Effect |
| --- | --- | --- |
| `git_panel.dock` | `left` | The Git panel shares the left dock with the project panel. |
| `git.inline_blame.enabled` | `true` | Blame for the current line is shown inline. |
| `git.git_gutter` | `tracked_files` | Added/modified/deleted gutter bars are shown for tracked files. |

`git_panel.dock` accepts `left` or `right`; `git.git_gutter` accepts
`tracked_files` or `hide`. They are ordinary settings and merge with the
existing configuration. Reload or restart Zed if the panel does not move.

### Tasks

`config/tasks.d/04-git.json` uses Zed's task syntax (`label`, `command`,
`args`, `use_new_terminal: false`, `reveal: always`):

| Label | Command |
| --- | --- |
| `Git: status` | `git status --short --branch` |
| `Git: log graph (30)` | `git log --graph --oneline --decorate -n 30` |
| `Git: pull --rebase` | `git pull --rebase` |
| `Git: push` | `git push` |
| `Git: new branch` | `bash -c "read -r -p 'New branch name: ' branch && git switch -c \"$branch\""` |
| `GitHub: create PR (web)` | `gh pr create --web` |
| `GitHub: view PR (web)` | `gh pr view --web` |
| `GitHub: view repository (web)` | `gh repo view --web` |
| `GitHub: workflow runs` | `gh run list` |

Every task reuses the current terminal tab (`use_new_terminal: false`) and
reveals it (`reveal: always`). The new-branch task reads the name in the task
terminal, so it needs a terminal with an interactive prompt. The tasks run in
the project root, which is the task default; none of them uses a `ZED_*`
variable. Start them from the command palette's **task: spawn** action.
Existing tasks with the same labels are replaced by the normal tasks merge.

### Verification

```bash
bash scripts/verify.d/04-git.sh
```

It checks `git --version`, `gh --version`, the five global defaults,
`user.name`/`user.email`, the optional ignore file, the live Git settings and
the tasks fragment. `gh auth status --no-refresh` is used only for its exit
status, with telemetry disabled: a missing login prints `SKIP`, never `FAIL`.
Use `make verify` to run it with the other phases.

## Backups, restore and rollback

`apply_zed_config` calls `backup_zed_config` before writing. If
`~/.config/zed` exists, the copy is:

```text
backups/zed-<timestamp>/zed/
```

Only one backup is made per installer run. Logs and backups are gitignored. A
`~/.config/zed` that is itself a symbolic link is refused: `cp -a` would back up
the link rather than the configuration behind it. Move the link aside or back
up its target manually.

Restore:

```bash
./install.sh --restore                    # newest backups/zed-*
./install.sh --restore backups/zed-20261116-101500
./install.sh --dry-run --restore          # preview commands only
```

The restore asks first. It moves the current `~/.config/zed` to
`backups/pre-restore-<timestamp>/zed/` (so nothing is deleted), then copies the
selected backup into place. Close Zed before restoring to avoid confusion, and
start/reload Zed afterward.

Manual rollback if you prefer not to use the script:

```bash
mv ~/.config/zed ~/.config/zed.broken
cp -a backups/zed-<timestamp>/zed ~/.config/zed
```

The backup layout is the one this installer creates. The restore also accepts a
directory that directly contains a Zed config tree (for example a copy of
`settings.json` and `keymap.json`) as long as it is not empty.

## Troubleshooting

- **Prompts answer no by themselves.** A non-interactive terminal is treated as
  No so scripts never hang. Use `--yes` after reviewing `--dry-run`.
- **Dry-run still created a log.** That is expected; dry-run writes only
  `logs/install-<timestamp>.log` and optional phase result logs.
- **`--list` says no phases.** That can only happen in a checkout where the
  `phases/NN-*.sh` files were removed. Copy the template to add one.
- **Unsupported distribution or architecture.** The installer refuses to
  continue; this repository targets Fedora x86_64 only.
- **Zed is only available as a Flatpak.** The phase warns and offers to continue
  with the native build. It never removes the Flatpak. Install the native build
  if you want language servers and toolchains to see the host environment
  without Flatpak permissions.
- **`zed: command not found` after installation.** `~/.local/bin` is not in the
  current shell's `PATH`. Approve the rc edit, then open a new terminal; the
  installer does not mutate the shell that launched it.
- **The Nerd Font is installed but not used.** Confirm `fc-list : family`
  contains `JetBrainsMono Nerd Font`, then restart Zed. Running `fc-cache -f`
  refreshes fontconfig; the phase does this for you.
- **The dotfiles hookup aborted on a conflict.** A file already exists under
  `<dotfiles>/zed/.config/zed/`. The phase never overwrites dotfiles files.
  Move or merge the existing file, then rerun. The live config and the existing
  package were backed up under `backups/`.
- **The dotfiles hookup failed at `stow`.** The phase restores the moved live
  files. Inspect `backups/pre-stow-<timestamp>/zed/` and the stow error, fix the
  conflict, then rerun. Use `command -v stow` to confirm GNU Stow is installed.
- **A stowed `settings.json` was replaced by a regular file.** The config engine
  asked before replacing a symlink. Re-run the dotfiles hookup after updating
  the package, or restore the symlink manually with `stow zed`.
- **The theme stayed on Zed's default.** Phase 3 was run before Zed installed
  the extensions, so it wrote the bootstrap fragment without a `theme` key. Start
  Zed once, let `auto_install_extensions` finish, then run
  `./install.sh --phase 3` again. The log says which theme JSON was missing.
- **`Tokyo Night` or `Zedokai Classic` is not in the theme selector.** Check that
  the extension directories exist under `${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed`
  (or the Flatpak data location). Zed installs extensions on startup; there is
  no verified CLI install command. `./scripts/verify.sh` reports the exact
  missing directory.
- **`ctrl-alt-t` does nothing.** The binding is in the `Workspace` context and
  needs the phase-3 keymap fragment to be merged. Run phase 3 again, or reload
  Zed, then use the command palette's "theme selector: toggle". `ctrl-k ctrl-t`
  remains Zed's default binding.
- **The palette table disappeared or has a `FAIL` row.** Regenerate it with
  `python3 lib/theme_build.py generate` using the installed extension paths, or
  delete nothing and run phase 3 again. `scripts/verify.d/03-theme.sh` fails if
  the docs table does not match the override colours.
- **Comments look too bright or too dim.** The phase deliberately lifts the
  target `#75715e` to `#76725e` to clear the 3.5:1 floor. If you change the
  background, regenerate the table; the helper always measures against the
  Tokyo Night editor background.
- **`git` or `gh` is missing.** Run `./install.sh --phase 4` and approve the
  `dnf` prompt. Both package names are in the Fedora `fedora` repository; the
  installed versions are reported by `rpm -q git gh`.
- **Commits open the wrong editor.** The phase sets
  `git config --global core.editor "zed --wait"`. If you declined the overwrite
  or already had another editor, set it manually. `zed` must be on the `PATH`
  used by `git`.
- **`git push` reports no upstream branch.** `push.autoSetupRemote=true` makes
  the first push set the upstream. If the value is still missing, rerun phase 4
  and approve the overwrite.
- **`gh` commands say you are not logged in.** Run `gh auth login` yourself;
  phase 4 only offers it and does not run it under `--yes`. Then run
  `gh auth setup-git` if you did not accept that step. Verification reports
  `SKIP` for the login, not `FAIL`.
- **`gh auth setup-git` failed.** It needs at least one authenticated GitHub
  host. Run `gh auth login` first, then `gh auth setup-git`. The phase does not
  fall back to storing a token.
- **Verification reports `FAIL git-identity`.** `user.name` or `user.email` is
  unset. Run `./install.sh --phase 4` in an interactive terminal and answer the
  identity prompts, or set both values with `git config --global`. The verifier
  never invents an identity.
- **The Git panel is not on the left or blame is still different.** The fragment
  merge was declined, or an existing value differs and you kept it. Rerun
  `./install.sh --phase 4` and approve the merge/overwrite, then reload Zed.
- **The new-branch task prints the prompt but does not create a branch.** Enter
  a non-empty branch name and press Enter. The task uses `read` in its terminal;
  an empty answer makes the `&&` chain stop without running `git switch`.
- **The global ignore file was not created.** The step is optional and never
  overwrites an existing file. Check
  `${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore`; if you set
  `core.excludesFile`, Git reads that path instead.
- **"Do not run as root".** Run `./install.sh` as your user. Only `step_dnf`
  invokes `sudo`, and only for `dnf install`.
- **JSONC parse error.** The error names the file and line/column. Fix the
  fragment and run `python3 lib/zed_config.py --check --config-dir config` to
  validate without writing.
- **My comments disappeared.** Any rewritten Zed config is plain JSON; the
  comments are lost by design. A backup was made first. Restore it or re-add
  comments in a fragment (fragments may contain comments).
- **Settings did not change.** Either the fragment directories are empty, or
  the merge produced no semantic change; in the latter case the file is left
  untouched so comments survive.
- **A snippet was not overwritten.** The destination differs from the
  repository copy and there was no interactive answer. Review with
  `--dry-run`, then rerun with `--yes` if the overwrite is intended.
- **dnf failed.** The ERR trap prints the failed command, the log path and the
  line. Read `logs/install-<timestamp>.log`.
- **Zed config reload.** If Zed does not pick up the change, restart or reload
  it. Restore never launches Zed.
- **shellcheck is missing.** `make lint` still runs `bash -n` on every shell
  file and reports shellcheck as skipped. Installing shellcheck is optional and
  uses your normal package method.
- **Where are the logs?** `logs/install-<timestamp>.log` and
  `logs/verify-<timestamp>.log`. Phase results are in
  `logs/results-<timestamp>.log`.

## Testing and definition of done

Run from the repository root:

```bash
bash -n install.sh
bash -n lib/common.sh
bash -n phases/00-template.sh.example
bash -n phases/02-base.sh
bash -n phases/03-theme.sh
bash -n phases/04-git.sh
for file in scripts/verify.sh scripts/verify.d/*.sh; do
  bash -n "${file}"
done
python3 config/templates/test/test_zed_config.py
python3 lib/theme_build.py check \
  --fragment config/settings.d/03-theme.json \
  --docs docs/THEME.md \
  --keymap config/keymap.d/03-theme.json
make lint
make test
./install.sh --list
./install.sh --dry-run
./install.sh --dry-run --phase 2
./install.sh --dry-run --phase 3
./install.sh --dry-run --phase 4
bash scripts/verify.d/04-git.sh
make verify
```

`make lint` is the authoritative syntax check: it runs `bash -n` on every
`*.sh` and `*.sh.example` file in the repository, including phases added later,
and runs shellcheck when it is installed.

What the tests cover:

- The JSONC parser against `config/templates/test/sample.jsonc` (line and block
  comments, trailing commas, comment markers inside strings, malformed input).
- Settings deep-merge, conflict output, preservation of existing keys, keymap
  exact-duplicate removal, tasks merge by label, snippet copy and overwrite
  protection.
- `--dry-run` writes nothing; `--check` creates nothing and rejects malformed
  fragments.

To prove a copied template phase runs safely in dry-run:

```bash
tmp="$(mktemp -d)"
mkdir -p "$tmp/home"
cp -a . "$tmp/repo"
cp "$tmp/repo/phases/00-template.sh.example" "$tmp/repo/phases/01-template.sh"
HOME="$tmp/home" "$tmp/repo/install.sh" --dry-run --yes
test ! -e "$tmp/home/.config/zed"
rm -rf "$tmp"
```

Acceptance checks for phase 1:

1. `bash -n` passes for every shell file. shellcheck is run when installed; it
   was not installed in the development environment during phase 1, so no
   shellcheck result is claimed for that phase.
2. `./install.sh --list` and `./install.sh --dry-run` exit 0.
3. A phase copied from the template runs in `--dry-run` without touching
   `~/.config`.
4. The JSONC fixture test suite passes.

Acceptance checks for phase 2:

1. `bash -n` and shellcheck pass for `phases/02-base.sh` and
   `scripts/verify.d/02-base.sh`. The phase was checked with shellcheck 0.11.0
   (extracted from the Fedora `shellcheck` RPM, not installed system-wide).
2. `./install.sh --dry-run --phase 2` exits 0, prints every planned command and
   changes nothing outside `logs/`.
3. The controlled dry-run and sandbox tests create no live Zed config, no
   `~/.editorconfig`, no font files and no dotfiles changes.
4. `python3 lib/zed_config.py --check --config-dir config` accepts the phase-2
   fragments, and the test suite passes.
5. The settings fragment contains only keys verified against the Zed 1.27.0
   default settings and current documentation; see `docs/ASSUMPTIONS.md`.
6. `config/keymap.d/02-base.json` is empty because the intended bindings already
   exist in Zed's default Linux keymap.

Acceptance checks for phase 3:

1. `bash -n` and shellcheck pass for `phases/03-theme.sh` and
   `scripts/verify.d/03-theme.sh`. If shellcheck is not installed, `make lint`
   reports it as skipped; the result is not claimed unless it actually ran.
2. `./install.sh --dry-run --phase 3` exits 0, prints every planned command and
   changes nothing outside `logs/`.
3. `config/settings.d/03-theme.json` selects `Tokyo Night` as the dark theme and
   contains 96 syntax overrides keyed only by `Tokyo Night`; every override
   colour is valid hex and every syntax colour meets its 4.5:1 or 3.5:1 floor.
4. The generated palette block in `docs/THEME.md` has no `FAIL` rows and matches
   the override colours. The full research record names the extension IDs,
   versions, commits, exact theme names and rejected candidates.
5. `scripts/verify.d/03-theme.sh` passes against a controlled installed-theme
   tree (both extension directories plus the pinned theme JSON) and reports the
   missing pieces when the extensions are absent. A full
   `./install.sh --phase 3 --yes` sandbox run against that tree applies the
   fragment and keymap, preserves unrelated settings and records `PASS` for the
   live theme and keybinding.
6. The fallback path writes a bootstrap fragment without `theme` or
   `theme_overrides`, leaves the default theme active, logs the missing theme
   JSON and exits 0; the committed palette table is not overwritten.
7. `python3 lib/zed_config.py --check --config-dir config` accepts the phase-3
   settings and keymap fragments, and the test suite passes.
8. The `ctrl-alt-t` action name was checked in Zed 1.27.0's and 1.28.1's default
   Linux keymaps and its absence in the VSCode base keymap; see
   `docs/ASSUMPTIONS.md`.

Acceptance checks for phase 4:

1. `bash -n` and shellcheck pass for `phases/04-git.sh` and
   `scripts/verify.d/04-git.sh`. If shellcheck is not installed, `make lint`
   reports it as skipped; the result is not claimed unless it actually ran.
2. `./install.sh --dry-run --phase 4` exits 0, prints every planned `dnf`,
   `git config`, `gh` and `install` command, and changes nothing outside
   `logs/`.
3. `config/settings.d/04-git.json` contains only the verified keys
   `git_panel.dock`, `git.inline_blame.enabled` and `git.git_gutter` with the
   values documented in this README.
4. `config/tasks.d/04-git.json` parses as a JSON array with the nine documented
   tasks. Every task has a non-empty `label` and `command`, an `args` list,
   `use_new_terminal: false` and `reveal: always`; the new-branch task contains
   a shell `read`.
5. A sandbox `./install.sh --phase 4 --yes` under a temporary `HOME` writes the
   five global defaults, installs the ignore file, merges the settings and
   tasks, and records `PASS` for packages, configuration, ignore file, settings
   and tasks. A pre-existing unrelated ignore file is left byte-for-byte
   unchanged and records `SKIP`. With no interactive input it leaves `user.name`
   and `user.email` unset and records `SKIP`, never a made-up value.
6. `scripts/verify.d/04-git.sh` reports `PASS` for both CLIs and the five
   defaults, and reports `SKIP` for `gh auth` when the sandbox is not logged in.
   It never prints a token.
7. `python3 lib/zed_config.py --check --config-dir config` accepts the phase-4
   settings and tasks fragments.

## License

No license file is included in this repository. Add one before distributing.
