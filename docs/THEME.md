# Theme and syntax highlighting

Phase 3 gives Zed a Tokyo Night user interface with classic Monokai syntax
colors. The design is deliberately split:

- **UI chrome** (tabs, panels, status bar, terminal) comes from the
  [`tokyo-night`](https://github.com/ssaunderss/zed-tokyo-night) extension and
  the exact dark theme **`Tokyo Night`**. Its editor background is `#1a1b26`.
- **Syntax colours** come from `theme_overrides` keyed by the exact theme name
  `Tokyo Night`. The overrides apply classic Monokai capture colours without
  replacing the Tokyo Night chrome.
- **The full Monokai alternative** is the exact theme **`Zedokai Classic`** from
  the [`zedokai`](https://github.com/slymax/zedokai) extension. It keeps its own
  Monokai UI and does not use the Tokyo Night overrides.

The extension choices and capture names were read from the shipped theme JSON
files, not inferred from extension names. The target palette values are fixed
below and every one is contrast-checked against the real Tokyo Night background.

## Generated palette and contrast table

The phase generator (`lib/theme_build.py generate`) rewrites this block from the
installed theme JSON. Comments have a 3.5:1 floor; every other syntax colour has
a 4.5:1 floor. A colour that misses its floor is lightened in the same HSL hue
until it passes. The check step fails if any generated row says `FAIL`.

<!-- BEGIN GENERATED PALETTE -->
Source: the installed theme JSON for `Tokyo Night` (dark) and `Tokyo Night Light` (light); editor background `#1a1b26`. Syntax capture names were read from the Tokyo Night and `Zedokai Classic` theme JSON; the palette values are the fixed target palette verified against that syntax section.

| Role | Captures | Final colour | Contrast | Minimum | Result |
| --- | --- | --- | --- | --- | --- |
| Keywords and storage | `keyword`, `keyword.*`, `preproc` | `#f92672` | 4.52:1 | 4.5:1 | PASS |
| Strings and characters | `string`, `string.*`, `character`, `character.special` | `#e6db74` | 12.00:1 | 4.5:1 | PASS |
| Functions and methods | `function`, `function.*`, `constructor` | `#a6e22e` | 11.02:1 | 4.5:1 | PASS |
| Numbers and constants | `number`, `number.*`, `float`, `constant`, `constant.*`, `boolean` | `#ae81ff` | 6.01:1 | 4.5:1 | PASS |
| Comments | `comment`, `comment.*`, `predoc` | `#76725e` | 3.53:1 | 3.5:1 | PASS |
| Everything else | `variable*`, `property`, `type*`, `operator`, `punctuation*`, `tag*`, `attribute`, and other captures | `#f8f8f2` | 16.03:1 | 4.5:1 | PASS |

Comments: the target `#75715e` measured 3.48:1, below the 3.5:1 floor, so the generator lightened it to `#76725e` (3.53:1) within the same hue.

Rainbow bracket accents (`accents`):

| Accent | Colour | Contrast | Result |
| --- | --- | --- | --- |
| 1 | `#f92672` | 4.52:1 | PASS |
| 2 | `#fd971f` | 7.83:1 | PASS |
| 3 | `#e6db74` | 12.00:1 | PASS |
| 4 | `#a6e22e` | 11.02:1 | PASS |
| 5 | `#66d9ef` | 10.37:1 | PASS |
| 6 | `#ae81ff` | 6.01:1 | PASS |
<!-- END GENERATED PALETTE -->

## Extensions

The IDs below are extension registry IDs, not display names. They were selected
by reading the theme JSON in the extension packages, not by trusting the
extension title or a screenshot.

| Extension ID | Verified version | Registry commit | Exact theme names used | Why this one |
| --- | --- | --- | --- | --- |
| `tokyo-night` | 0.9.0 | `a4ef7dd64e146434d4ac289b59abe17ff98ba680` | `Tokyo Night` (dark, default), `Tokyo Night Light` (light) | The verified Tokyo Night port. The dark theme's own editor background is `#1a1b26`, which is the background used for every contrast calculation. |
| `zedokai` | 1.2.2 | `b4c5a0b8b66f1889bd1eabafe5e984372ebff7a5` | `Zedokai Classic` | Its classic theme JSON contains the original Monokai syntax colours (`#f92672`, `#e6db74`, `#a6e22e`, `#ae81ff`), neutral variables/properties (`#fdfff1`) and the expected `#272822` Monokai background. |

Rejected alternatives, for the record:

| Candidate | Reason |
| --- | --- |
| `Monokai Pro (CE)` | Uses the Monokai Pro palette (`#ff6188`, `#ffd866`, `#a9dc76`, `#ab9df2`), not classic Monokai. |
| `KTRZ Monokai` | Properties are red and comments use `#5C6166`; not the classic mapping. |
| `SuperGreatMonokai` | Variables are blue; not the classic mapping. |
| `Monokai-og` | Properties are green and comments use `#88846f`; it does not match the classic mapping. |

Both extensions are listed under `auto_install_extensions` in
`config/settings.d/03-theme.json`. Zed's command line has no verified
install-extension command, so the actual download happens on the next Zed
startup. Start Zed once, let the extensions finish installing, then run phase 3
again so the generator can read the installed theme JSON. The default extension
root is `${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed`;
`~/.local/share/zed/extensions/installed` is used when `XDG_DATA_HOME` is unset.
Phase 3 also checks the corresponding Flatpak data location; that path is a
best-effort fallback and is listed as an unverified assumption in
[`ASSUMPTIONS.md`](ASSUMPTIONS.md#22-flatpak-extension-data-path).

## What the overrides contain

`config/settings.d/03-theme.json` sets:

```json
{
  "auto_install_extensions": {
    "tokyo-night": true,
    "zedokai": true
  },
  "colorize_brackets": true,
  "semantic_tokens": "combined",
  "theme": {
    "mode": "dark",
    "light": "Tokyo Night Light",
    "dark": "Tokyo Night"
  },
  "theme_overrides": {
    "Tokyo Night": {
      "accents": ["#f92672", "#fd971f", "#e6db74", "#a6e22e", "#66d9ef", "#ae81ff"],
      "syntax": {}
    }
  }
}
```

The real `syntax` object is generated from every capture name found in the
Tokyo Night and Zedokai theme JSON, plus a conservative core set. Captures map
to six roles:

| Role | Captures |
| --- | --- |
| Keywords | `keyword*`, `preproc` |
| Strings | `string*`, `character*` |
| Functions | `function*`, `constructor` |
| Numbers/constants | `number*`, `float*`, `constant*`, `boolean` |
| Comments | `comment*`, `predoc` |
| Neutral | everything else (`variable*`, `property`, `type*`, `operator`, `punctuation*`, `tag*`, ...) |

The six `accents` are the rainbow bracket cycle requested for this phase:
`#f92672`, `#fd971f`, `#e6db74`, `#a6e22e`, `#66d9ef`, `#ae81ff`.
`colorize_brackets: true` enables that cycle.

`semantic_tokens: "combined"` is enabled because Zed 1.27.0 supports the
setting with `off`, `combined` and `full`; Zed 1.28.1's default settings were
re-checked on 2026-11-18 and use the same key and values. `combined` lets
semantic tokens refine tree-sitter captures while keeping the Monokai overrides
as the base.

## Theme selector keybinding

`config/keymap.d/03-theme.json` adds one binding in the `Workspace` context:

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-alt-t": "theme_selector::Toggle"
    }
  }
]
```

`ctrl-alt-t` was checked against Zed 1.27.0's and 1.28.1's default Linux
keymaps and the VSCode base keymap; neither uses it. Zed's existing default
`ctrl-k ctrl-t` binding for `theme_selector::Toggle` is left in place. The
action name itself was verified in the default Linux keymaps.

## Switching to full Monokai

Use the theme selector (`ctrl-alt-t`, or the command palette's "theme selector:
toggle") and choose **`Zedokai Classic`**. Alternatively, edit
`~/.config/zed/settings.json`:

```json
{
  "theme": {
    "mode": "dark",
    "light": "Zedokai Light",
    "dark": "Zedokai Classic"
  }
}
```

Keep or remove `theme_overrides` as you prefer. The overrides are keyed only by
`Tokyo Night`, so `Zedokai Classic` uses its own Monokai syntax and UI without
them. Set the theme back to `Tokyo Night` to return to the Tokyo Night UI with
Monokai syntax. Full Monokai becomes available only after the `zedokai`
extension is installed.

## Fallback behaviour

The phase is safe to run before the extensions exist:

1. It looks for the theme JSON under the installed extensions directory.
2. If `Tokyo Night` JSON is missing or unreadable, it writes a bootstrap
   fragment containing `auto_install_extensions`, `colorize_brackets` and
   `semantic_tokens`, but **no** `theme` or `theme_overrides` key. Zed's current
   default theme therefore stays active, and the log says so.
3. If `Zedokai Classic` JSON is missing or unreadable, it keeps the verified
   fallback Monokai palette and logs that the source theme could not be read.
4. It exits 0 after recording `SKIP`/`PASS` as appropriate. It does not remove
   an existing theme setting or fail the whole installer.

After the next Zed startup installs the extensions, run phase 3 again to write
the full fragment and regenerate the table above.

## Verification

`scripts/verify.d/03-theme.sh` checks:

- the `tokyo-night` and `zedokai` extension directories exist under the
  installed-extension root;
- `theme_overrides` parses and every override colour is a valid
  `#RRGGBB`/`#RRGGBBAA` value;
- the generated contrast table has no `FAIL` rows, and every syntax override
  passes its role's minimum against `#1a1b26`;
- the fragment selects `Tokyo Night` as the dark theme, and the live
  `settings.json` selects a theme that is actually installed;
- the bracket accents are exactly the documented six, `colorize_brackets` is
  true, `semantic_tokens` is enabled, and the keymap contains
  `theme_selector::Toggle`.

Manual check of the current files:

```bash
python3 lib/theme_build.py check \
  --fragment config/settings.d/03-theme.json \
  --docs docs/THEME.md \
  --keymap config/keymap.d/03-theme.json
```

Add `--settings ~/.config/zed/settings.json --live-keymap ~/.config/zed/keymap.json --installed-dir "${XDG_DATA_HOME:-$HOME/.local/share}/zed/extensions/installed"`
after phase 3 has been applied and the extensions are installed.

## Re-checking the extension facts

The pinned JSON used to generate the table is read-only evidence, not a file
shipped to users. The version list comes from the extension API; the registry
commit is the `extensions/<id>` submodule commit in
`zed-industries/extensions`. To re-check:

```bash
for id in tokyo-night zedokai; do
  curl -fsSL "https://api.zed.dev/extensions/${id}" |
    python3 -c 'import json,sys; [print(i["id"], i["version"], i["repository"]) for i in json.load(sys.stdin)["data"]]'
  curl -fsSL "https://api.github.com/repos/zed-industries/extensions/contents/extensions/${id}" |
    python3 -c 'import json,sys; print("registry commit:", json.load(sys.stdin)["sha"])'
done
```

Confirm that the newest returned version and the submodule commit still match
the table before updating the pinned JSON. The theme names are read from the
downloaded theme JSON under each extension directory.
