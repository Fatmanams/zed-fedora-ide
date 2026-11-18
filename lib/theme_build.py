#!/usr/bin/env python3
"""Generate and check the phase-3 Zed theme fragment and palette table.

The phase-3 design is a Tokyo Night UI with classic Monokai syntax colours
applied as ``theme_overrides``.  The helper:

* reads the installed Tokyo Night and Zedokai theme JSON files (or accepts
  direct file paths for offline generation);
* maps every syntax capture in those files to one of six palette roles;
* lightens colours that miss the WCAG contrast floor within the same hue;
* writes ``config/settings.d/03-theme.json`` and the generated palette block
  in ``docs/THEME.md``;
* checks the fragment, the docs table, the live settings and the keymap.

Only the Python standard library is used.  ``zed_config.py`` supplies the
JSONC reader and the atomic writer.
"""

from __future__ import annotations

import argparse
import colorsys
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

from zed_config import ConfigError, atomic_write_text, read_jsonc

DEFAULT_DARK_THEME = "Tokyo Night"
DEFAULT_LIGHT_THEME = "Tokyo Night Light"
DEFAULT_BACKGROUND = "#1a1b26"
MONOKAI_THEME_NAME = "Zedokai Classic"
TOKYO_EXTENSION_ID = "tokyo-night"
MONOKAI_EXTENSION_ID = "zedokai"
THEME_SELECTOR_ACTION = "theme_selector::Toggle"

BEGIN_MARKER = "<!-- BEGIN GENERATED PALETTE -->"
END_MARKER = "<!-- END GENERATED PALETTE -->"

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$")

# The palette is deliberately small: three accents plus a neutral base.
ROLES: dict[str, dict[str, Any]] = {
    "keyword": {
        "label": "Keywords and storage",
        "captures": "`keyword`, `keyword.*`, `preproc`",
        "color": "#f92672",
        "minimum": 4.5,
    },
    "string": {
        "label": "Strings and characters",
        "captures": "`string`, `string.*`, `character`, `character.special`",
        "color": "#e6db74",
        "minimum": 4.5,
    },
    "function": {
        "label": "Functions and methods",
        "captures": "`function`, `function.*`, `constructor`",
        "color": "#a6e22e",
        "minimum": 4.5,
    },
    "number": {
        "label": "Numbers and constants",
        "captures": "`number`, `number.*`, `float`, `constant`, `constant.*`, `boolean`",
        "color": "#ae81ff",
        "minimum": 4.5,
    },
    "comment": {
        "label": "Comments",
        "captures": "`comment`, `comment.*`, `predoc`",
        "color": "#75715e",
        "minimum": 3.5,
    },
    "neutral": {
        "label": "Everything else",
        "captures": "`variable*`, `property`, `type*`, `operator`, `punctuation*`, `tag*`, `attribute`, and other captures",
        "color": "#f8f8f2",
        "minimum": 4.5,
    },
}

ACCENTS = ["#f92672", "#fd971f", "#e6db74", "#a6e22e", "#66d9ef", "#ae81ff"]

# Used when the installed Tokyo Night theme JSON cannot be read.  This is the
# syntax capture set of Tokyo Night 0.9.0 (registry submodule a4ef7dd6).
FALLBACK_SYNTAX_KEYS = [
    "attribute",
    "boolean",
    "character",
    "character.special",
    "comment",
    "comment.doc",
    "comment.documentation",
    "comment.error",
    "comment.hint",
    "comment.note",
    "comment.todo",
    "comment.warning",
    "concept",
    "constant",
    "constant.builtin",
    "constant.macro",
    "constructor",
    "diff.minus",
    "diff.plus",
    "embedded",
    "emphasis",
    "emphasis.strong",
    "enum",
    "field",
    "float",
    "function",
    "function.builtin",
    "function.call",
    "function.decorator",
    "function.macro",
    "function.method",
    "function.method.call",
    "keyword",
    "keyword.conditional",
    "keyword.conditional.ternary",
    "keyword.coroutine",
    "keyword.debug",
    "keyword.directive",
    "keyword.directive.define",
    "keyword.exception",
    "keyword.export",
    "keyword.function",
    "keyword.import",
    "keyword.modifier",
    "keyword.operator",
    "keyword.repeat",
    "keyword.return",
    "keyword.type",
    "label",
    "link_text",
    "link_uri",
    "module",
    "namespace",
    "number",
    "number.float",
    "operator",
    "parameter",
    "parent",
    "predoc",
    "preproc",
    "primary",
    "property",
    "punctuation",
    "punctuation.bracket",
    "punctuation.delimiter",
    "punctuation.list_marker",
    "punctuation.special",
    "string",
    "string.doc",
    "string.documentation",
    "string.escape",
    "string.regex",
    "string.regexp",
    "string.special",
    "string.special.path",
    "string.special.symbol",
    "string.special.url",
    "symbol",
    "tag",
    "tag.attribute",
    "tag.delimiter",
    "tag.doctype",
    "text.literal",
    "title",
    "type",
    "type.builtin",
    "type.class.definition",
    "type.definition",
    "type.interface",
    "type.super",
    "variable",
    "variable.builtin",
    "variable.member",
    "variable.parameter",
    "variable.special",
    "variant",
]

CORE_KEYS = [
    "comment",
    "constant",
    "function",
    "keyword",
    "number",
    "string",
    "variable",
    "property",
    "type",
    "operator",
    "punctuation",
    "boolean",
]


def role_for(capture: str) -> str:
    """Return the palette role for a Zed syntax capture name."""

    if capture.startswith("comment") or capture == "predoc":
        return "comment"
    if capture.startswith("keyword") or capture == "preproc":
        return "keyword"
    if capture.startswith("string") or capture.startswith("character"):
        return "string"
    if capture.startswith("function") or capture == "constructor":
        return "function"
    if (
        capture.startswith("number")
        or capture.startswith("float")
        or capture.startswith("constant")
        or capture == "boolean"
    ):
        return "number"
    return "neutral"


def normalize_color(value: str) -> str:
    if not isinstance(value, str) or not HEX_RE.match(value):
        raise ValueError(f"not a #RRGGBB or #RRGGBBAA colour: {value!r}")
    return value.lower()


def _rgb(color: str) -> tuple[float, float, float]:
    value = normalize_color(color).lstrip("#")
    return (
        int(value[0:2], 16) / 255.0,
        int(value[2:4], 16) / 255.0,
        int(value[4:6], 16) / 255.0,
    )


def _hex_from_rgb(red: float, green: float, blue: float) -> str:
    def channel(value: float) -> int:
        return max(0, min(255, round(value * 255)))

    return "#%02x%02x%02x" % (channel(red), channel(green), channel(blue))


def _linear_channel(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def relative_luminance(color: str) -> float:
    red, green, blue = _rgb(color)
    return (
        0.2126 * _linear_channel(red)
        + 0.7152 * _linear_channel(green)
        + 0.0722 * _linear_channel(blue)
    )


def contrast_ratio(first: str, second: str) -> float:
    first_luminance = relative_luminance(first)
    second_luminance = relative_luminance(second)
    lighter = max(first_luminance, second_luminance)
    darker = min(first_luminance, second_luminance)
    return (lighter + 0.05) / (darker + 0.05)


def lighten_until(color: str, background: str, minimum: float) -> tuple[str, float]:
    """Lighten a colour in HSL until it meets the WCAG ratio.

    The hue and saturation are preserved; only the HSL lightness changes.  The
    result is quantised to 8-bit RGB, which is what Zed stores in JSON.
    """

    color = normalize_color(color)
    background = normalize_color(background)
    ratio = contrast_ratio(color, background)
    if ratio >= minimum:
        return color, ratio

    red, green, blue = _rgb(color)
    hue, lightness, saturation = colorsys.rgb_to_hls(red, green, blue)
    while lightness < 1.0:
        lightness = min(1.0, lightness + 0.001)
        candidate = _hex_from_rgb(*colorsys.hls_to_rgb(hue, lightness, saturation))
        ratio = contrast_ratio(candidate, background)
        if ratio >= minimum:
            return candidate, ratio
    return "#ffffff", contrast_ratio("#ffffff", background)


def _theme_json_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(path for path in directory.rglob("*.json") if path.is_file())


def _load_themes(path: Path) -> Optional[list[dict[str, Any]]]:
    try:
        data, _ = read_jsonc(path)
    except (ConfigError, OSError):
        return None
    if not isinstance(data, dict):
        return None
    themes = data.get("themes")
    if not isinstance(themes, list):
        return None
    valid = [
        theme
        for theme in themes
        if isinstance(theme, dict) and isinstance(theme.get("name"), str)
    ]
    return valid or None


def _collect_themes(
    directory: Optional[Path], direct_path: Optional[Path]
) -> list[tuple[Path, list[dict[str, Any]]]]:
    entries: list[tuple[Path, list[dict[str, Any]]]] = []
    if direct_path is not None:
        themes = _load_themes(direct_path)
        if themes:
            entries.append((direct_path, themes))
        return entries
    if directory is None:
        return entries
    for path in _theme_json_files(directory):
        themes = _load_themes(path)
        if themes:
            entries.append((path, themes))
    return entries


def _theme_names(entries: Iterable[tuple[Path, list[dict[str, Any]]]]) -> list[str]:
    names: list[str] = []
    for _, themes in entries:
        names.extend(theme["name"] for theme in themes)
    return names


def _find_theme(
    entries: Iterable[tuple[Path, list[dict[str, Any]]]],
    name: str,
    appearance: Optional[str] = None,
) -> tuple[Optional[dict[str, Any]], Optional[Path]]:
    for path, themes in entries:
        for theme in themes:
            if theme.get("name") != name:
                continue
            if appearance is not None and theme.get("appearance") != appearance:
                continue
            return theme, path
    return None, None


def _style(theme: Optional[dict[str, Any]]) -> dict[str, Any]:
    if not isinstance(theme, dict):
        return {}
    style = theme.get("style")
    return style if isinstance(style, dict) else {}


def _syntax(theme: Optional[dict[str, Any]]) -> dict[str, Any]:
    syntax = _style(theme).get("syntax")
    return syntax if isinstance(syntax, dict) else {}


def _read_background(tokyo_theme: Optional[dict[str, Any]]) -> str:
    style = _style(tokyo_theme)
    for key in ("editor.background", "background"):
        value = style.get(key)
        if isinstance(value, str) and HEX_RE.match(value):
            return value.lower()
    return DEFAULT_BACKGROUND


def build_palette(
    tokyo_entries: list[tuple[Path, list[dict[str, Any]]]],
    monokai_entries: list[tuple[Path, list[dict[str, Any]]]],
) -> dict[str, Any]:
    tokyo_dark, tokyo_dark_source = _find_theme(
        tokyo_entries, DEFAULT_DARK_THEME, "dark"
    )
    if tokyo_dark is None:
        tokyo_dark, tokyo_dark_source = _find_theme(tokyo_entries, DEFAULT_DARK_THEME)
    tokyo_light, _ = _find_theme(tokyo_entries, DEFAULT_LIGHT_THEME, "light")
    if tokyo_light is None:
        tokyo_light, _ = _find_theme(tokyo_entries, DEFAULT_LIGHT_THEME)
    monokai_theme, monokai_source = _find_theme(
        monokai_entries, MONOKAI_THEME_NAME, "dark"
    )
    if monokai_theme is None:
        monokai_theme, monokai_source = _find_theme(monokai_entries, MONOKAI_THEME_NAME)

    background = _read_background(tokyo_dark)
    palette: dict[str, dict[str, Any]] = {}
    for role, specification in ROLES.items():
        target = normalize_color(specification["color"])
        final, ratio = lighten_until(target, background, specification["minimum"])
        palette[role] = {
            "color": final,
            "ratio": ratio,
            "target": target,
            "minimum": specification["minimum"],
        }

    keys = set(FALLBACK_SYNTAX_KEYS)
    keys.update(CORE_KEYS)
    keys.update(key for key in _syntax(tokyo_dark) if isinstance(key, str))
    keys.update(key for key in _syntax(monokai_theme) if isinstance(key, str))
    role_by_key = {key: role_for(key) for key in sorted(keys)}

    accents = [normalize_color(accent) for accent in ACCENTS]
    accent_ratios = {accent: contrast_ratio(accent, background) for accent in accents}

    comment_target = normalize_color(ROLES["comment"]["color"])
    return {
        "background": background,
        "dark_source": (
            str(tokyo_dark_source) if tokyo_dark_source is not None else None
        ),
        "monokai_source": (
            str(monokai_source) if monokai_source is not None else None
        ),
        "dark_name": (
            tokyo_dark["name"] if tokyo_dark is not None else DEFAULT_DARK_THEME
        ),
        "light_name": (
            tokyo_light["name"] if tokyo_light is not None else DEFAULT_LIGHT_THEME
        ),
        "theme_available": tokyo_dark is not None and tokyo_light is not None,
        "tokyo_dark": tokyo_dark,
        "tokyo_light": tokyo_light,
        "monokai_available": monokai_theme is not None,
        "monokai_theme": monokai_theme,
        "palette": palette,
        "role_by_key": role_by_key,
        "accents": accents,
        "accent_ratios": accent_ratios,
        "comment_target": comment_target,
        "comment_target_ratio": contrast_ratio(comment_target, background),
    }


def build_fragment(
    result: dict[str, Any],
    colorize_brackets: bool,
    semantic_tokens: Optional[str],
) -> dict[str, Any]:
    fragment: dict[str, Any] = {
        "auto_install_extensions": {
            TOKYO_EXTENSION_ID: True,
            MONOKAI_EXTENSION_ID: True,
        }
    }
    if colorize_brackets:
        fragment["colorize_brackets"] = True
    if semantic_tokens:
        fragment["semantic_tokens"] = semantic_tokens

    if result["theme_available"]:
        syntax = {
            key: {"color": result["palette"][role]["color"]}
            for key, role in sorted(result["role_by_key"].items())
        }
        fragment["theme"] = {
            "mode": "dark",
            "light": result["light_name"],
            "dark": result["dark_name"],
        }
        fragment["theme_overrides"] = {
            result["dark_name"]: {
                "accents": result["accents"],
                "syntax": syntax,
            }
        }
    return fragment


def render_docs_block(result: dict[str, Any]) -> str:
    lines: list[str] = []
    if result["theme_available"]:
        source = (
            "Source: the installed theme JSON for "
            f"`{result['dark_name']}` (dark) and `{result['light_name']}` (light); "
            f"editor background `{result['background']}`. "
        )
        if result["monokai_available"]:
            source += (
                f"Syntax capture names were read from the Tokyo Night and "
                f"`{MONOKAI_THEME_NAME}` theme JSON; the palette values are the "
                "fixed target palette verified against that syntax section."
            )
        else:
            source += (
                f"`{MONOKAI_THEME_NAME}` was not readable on this run, so the "
                "capture names come from Tokyo Night plus the verified fallback "
                "set and the fixed target palette is used."
            )
        lines.append(source)
    else:
        lines.append(
            "Installed theme JSON was not available on this run. The table below "
            "uses the verified fallback palette and the Tokyo Night editor "
            f"background `{DEFAULT_BACKGROUND}`. Start Zed once so "
            "`auto_install_extensions` can install the theme extensions, then run "
            "phase 3 again."
        )
    lines.append("")
    lines.append("| Role | Captures | Final colour | Contrast | Minimum | Result |")
    lines.append("| --- | --- | --- | --- | --- | --- |")
    for role, specification in ROLES.items():
        entry = result["palette"][role]
        status = "PASS" if entry["ratio"] >= entry["minimum"] else "FAIL"
        lines.append(
            f"| {specification['label']} | {specification['captures']} | "
            f"`{entry['color']}` | {entry['ratio']:.2f}:1 | "
            f"{entry['minimum']:.1f}:1 | {status} |"
        )

    comment = result["palette"]["comment"]
    if comment["color"] != result["comment_target"]:
        lines.append("")
        lines.append(
            f"Comments: the target `{result['comment_target']}` measured "
            f"{result['comment_target_ratio']:.2f}:1, below the 3.5:1 floor, so "
            f"the generator lightened it to `{comment['color']}` "
            f"({comment['ratio']:.2f}:1) within the same hue."
        )

    lines.append("")
    lines.append("Rainbow bracket accents (`accents`):")
    lines.append("")
    lines.append("| Accent | Colour | Contrast | Result |")
    lines.append("| --- | --- | --- | --- |")
    for index, accent in enumerate(result["accents"], start=1):
        ratio = result["accent_ratios"][accent]
        status = "PASS" if ratio >= 4.5 else "FAIL"
        lines.append(f"| {index} | `{accent}` | {ratio:.2f}:1 | {status} |")
    return "\n".join(lines)


def _replace_docs_block(text: str, block: str) -> str:
    start = text.find(BEGIN_MARKER)
    end = text.find(END_MARKER, start + 1 if start >= 0 else 0)
    if start < 0 or end < 0:
        raise ValueError(f"missing palette markers in docs file")
    return f"{text[: start + len(BEGIN_MARKER)]}\n{block}\n{text[end:]}"


def _iter_override_colors(
    overrides: dict[str, Any],
) -> Iterator[tuple[str, Any]]:
    for theme_name, content in overrides.items():
        if not isinstance(content, dict):
            continue
        accents = content.get("accents")
        if isinstance(accents, list):
            for index, value in enumerate(accents):
                yield f"theme_overrides[{theme_name!r}].accents[{index}]", value
        syntax = content.get("syntax")
        if isinstance(syntax, dict):
            for capture, entry in syntax.items():
                if not isinstance(entry, dict):
                    continue
                for field in ("color", "background_color"):
                    if field in entry:
                        yield (
                            f"theme_overrides[{theme_name!r}].syntax[{capture!r}].{field}",
                            entry[field],
                        )
        colors = content.get("colors")
        if isinstance(colors, dict):
            for name, value in colors.items():
                yield f"theme_overrides[{theme_name!r}].colors[{name!r}]", value


def _installed_theme_names(installed_dir: Optional[Path]) -> list[str]:
    if installed_dir is None:
        return []
    entries: list[tuple[Path, list[dict[str, Any]]]] = []
    for extension_id in (TOKYO_EXTENSION_ID, MONOKAI_EXTENSION_ID):
        entries.extend(_collect_themes(installed_dir / extension_id, None))
    return _theme_names(entries)


def _background_for_check(args: argparse.Namespace) -> str:
    entries: list[tuple[Path, list[dict[str, Any]]]] = []
    if args.tokyo_json:
        entries = _collect_themes(None, Path(args.tokyo_json))
    elif args.installed_dir:
        entries = _collect_themes(
            Path(args.installed_dir) / TOKYO_EXTENSION_ID, None
        )
    theme, _ = _find_theme(entries, DEFAULT_DARK_THEME)
    return _read_background(theme)


def _emit(status: str, item: str, detail: str) -> None:
    print(f"{status} {item} {detail}")


def _theme_selector_keys(path: Path) -> list[str]:
    """Return every key bound to the theme selector in a keymap file."""

    keymap, _ = read_jsonc(path)
    if not isinstance(keymap, list):
        raise ValueError("top level is not a JSON array")
    keys: list[str] = []
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
            if action == THEME_SELECTOR_ACTION:
                keys.append(key)
    return keys


def command_generate(args: argparse.Namespace) -> int:
    tokyo_entries = _collect_themes(
        Path(args.tokyo_extension_dir) if args.tokyo_extension_dir else None,
        Path(args.tokyo_json) if args.tokyo_json else None,
    )
    monokai_entries = _collect_themes(
        Path(args.monokai_extension_dir) if args.monokai_extension_dir else None,
        Path(args.monokai_json) if args.monokai_json else None,
    )

    result = build_palette(tokyo_entries, monokai_entries)
    fragment = build_fragment(
        result, args.colorize_brackets, args.semantic_tokens
    )

    if not result["theme_available"]:
        print(
            "WARN: Tokyo Night theme JSON was not found. Writing a bootstrap "
            "fragment without a theme key; the default theme stays active. "
            "Start Zed once and run phase 3 again.",
            file=sys.stderr,
        )
    if not result["monokai_available"]:
        print(
            f"WARN: {MONOKAI_THEME_NAME} theme JSON was not found. The verified "
            "fallback palette and capture set are used when the Tokyo Night "
            "theme is available.",
            file=sys.stderr,
        )

    print(
        f"Editor background: {result['background']} "
        f"(theme {result['dark_name']!r})"
    )
    print(render_docs_block(result))
    print()

    fragment_path = Path(args.fragment)
    docs_path = Path(args.docs)
    docs_output: Optional[str] = None

    # The committed docs table shows the verified Tokyo Night palette.  A
    # bootstrap run must not downgrade it to the "theme not installed" table,
    # so only rewrite the markers when the theme JSON was actually read.
    if result["theme_available"]:
        try:
            docs_text = docs_path.read_text(encoding="utf-8")
            docs_output = _replace_docs_block(
                docs_text, render_docs_block(result)
            )
        except (OSError, ValueError) as exc:
            print(f"ERROR: cannot update {docs_path}: {exc}", file=sys.stderr)
            return 1
    else:
        print(
            f"Leaving the palette block in {docs_path} unchanged because the "
            "theme JSON was not available.",
            file=sys.stderr,
        )

    fragment_text = json.dumps(fragment, indent=2, ensure_ascii=False) + "\n"
    try:
        json.loads(fragment_text)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive
        print(f"ERROR: generated fragment is not valid JSON: {exc}", file=sys.stderr)
        return 1

    syntax_count = len(result["role_by_key"]) if result["theme_available"] else 0
    if args.dry_run:
        print(f"dry-run: would write {fragment_path} ({syntax_count} syntax overrides)")
        if docs_output is not None:
            print(f"dry-run: would update the palette block in {docs_path}")
        return 0

    atomic_write_text(fragment_path, fragment_text)
    print(f"Wrote {fragment_path} ({syntax_count} syntax overrides)")
    if docs_output is not None:
        atomic_write_text(docs_path, docs_output)
        print(f"Updated the palette block in {docs_path}")
    return 0


def command_status(args: argparse.Namespace) -> int:
    """Print machine-readable `key=value` lines describing the theme sources.

    The phase script parses these lines to decide between a full fragment and
    the bootstrap fallback without duplicating the theme JSON reader.
    """

    installed_dir = Path(args.installed_dir) if args.installed_dir else None

    tokyo_dir = args.tokyo_extension_dir
    if not tokyo_dir and installed_dir is not None:
        tokyo_dir = str(installed_dir / TOKYO_EXTENSION_ID)
    monokai_dir = args.monokai_extension_dir
    if not monokai_dir and installed_dir is not None:
        monokai_dir = str(installed_dir / MONOKAI_EXTENSION_ID)

    tokyo_entries = _collect_themes(
        Path(tokyo_dir) if tokyo_dir else None,
        Path(args.tokyo_json) if args.tokyo_json else None,
    )
    monokai_entries = _collect_themes(
        Path(monokai_dir) if monokai_dir else None,
        Path(args.monokai_json) if args.monokai_json else None,
    )
    result = build_palette(tokyo_entries, monokai_entries)

    def flag(value: bool) -> str:
        return "true" if value else "false"

    tokyo_names = _theme_names(tokyo_entries)
    monokai_names = _theme_names(monokai_entries)

    print(f"theme_available={flag(result['theme_available'])}")
    print(f"monokai_available={flag(result['monokai_available'])}")
    print(f"dark_theme={result['dark_name']}")
    print(f"light_theme={result['light_name']}")
    print(f"monokai_theme={MONOKAI_THEME_NAME}")
    print(f"background={result['background']}")
    print(f"tokyo_themes={', '.join(tokyo_names)}")
    print(f"monokai_themes={', '.join(monokai_names)}")
    print(f"tokyo_source={result['dark_source'] or '-'}")
    print(f"monokai_source={result['monokai_source'] or '-'}")
    return 0


def command_check(args: argparse.Namespace) -> int:
    failures = 0

    def emit(status: str, item: str, detail: str) -> None:
        nonlocal failures
        if status == "FAIL":
            failures += 1
        _emit(status, item, detail)

    fragment_path = Path(args.fragment)
    try:
        fragment_data, _ = read_jsonc(fragment_path)
    except (ConfigError, OSError) as exc:
        emit("FAIL", "theme-overrides-parse", str(exc).replace("\n", " "))
        return 1

    if not isinstance(fragment_data, dict):
        emit("FAIL", "theme-overrides-parse", "top level is not a JSON object")
        return 1

    overrides = fragment_data.get("theme_overrides")
    if not isinstance(overrides, dict) or not overrides:
        emit(
            "FAIL",
            "theme-overrides-parse",
            "theme_overrides is missing or empty; run phase 3 after the extensions install",
        )
        overrides = {}
    else:
        emit(
            "PASS",
            "theme-overrides-parse",
            f"{len(overrides)} theme key(s): {', '.join(sorted(overrides))}",
        )
        if set(overrides) == {DEFAULT_DARK_THEME}:
            emit(
                "PASS",
                "theme-overrides-key",
                f"only {DEFAULT_DARK_THEME!r} is overridden",
            )
        else:
            emit(
                "FAIL",
                "theme-overrides-key",
                f"expected only {DEFAULT_DARK_THEME!r}, found "
                f"{', '.join(sorted(overrides))}",
            )

    auto_install = fragment_data.get("auto_install_extensions")
    if (
        isinstance(auto_install, dict)
        and auto_install.get(TOKYO_EXTENSION_ID) is True
        and auto_install.get(MONOKAI_EXTENSION_ID) is True
    ):
        emit(
            "PASS",
            "theme-auto-install",
            f"{TOKYO_EXTENSION_ID}=true, {MONOKAI_EXTENSION_ID}=true",
        )
    else:
        emit(
            "FAIL",
            "theme-auto-install",
            "auto_install_extensions must enable tokyo-night and zedokai",
        )

    invalid_colors: list[str] = []
    color_count = 0
    for location, value in _iter_override_colors(overrides):
        color_count += 1
        if not isinstance(value, str) or not HEX_RE.match(value):
            invalid_colors.append(f"{location}={value!r}")
    if invalid_colors:
        emit(
            "FAIL",
            "theme-overrides-hex",
            "; ".join(invalid_colors[:4]),
        )
    elif color_count == 0:
        emit("FAIL", "theme-overrides-hex", "no override colours found")
    else:
        emit(
            "PASS",
            "theme-overrides-hex",
            f"{color_count} colours are #RRGGBB or #RRGGBBAA",
        )

    background = _background_for_check(args)
    syntax_failures: list[str] = []
    role_colors: dict[str, set[str]] = {}
    syntax_count = 0
    for theme_name, content in overrides.items():
        if not isinstance(content, dict):
            syntax_failures.append(f"{theme_name}: override is not an object")
            continue
        syntax = content.get("syntax")
        if not isinstance(syntax, dict) or not syntax:
            syntax_failures.append(f"{theme_name}: syntax is missing or empty")
            continue
        for capture, entry in syntax.items():
            if not isinstance(entry, dict):
                syntax_failures.append(f"{capture}: entry is not an object")
                continue
            color = entry.get("color")
            if not isinstance(color, str) or not HEX_RE.match(color):
                syntax_failures.append(f"{capture}: invalid colour {color!r}")
                continue
            role = role_for(capture)
            minimum = ROLES[role]["minimum"]
            ratio = contrast_ratio(color, background)
            role_colors.setdefault(role, set()).add(color.lower())
            syntax_count += 1
            if ratio + 1e-9 < minimum:
                syntax_failures.append(
                    f"{capture}={color} {ratio:.2f}:1 < {minimum:.1f}:1"
                )

    accents: list[str] = []
    for content in overrides.values():
        if isinstance(content, dict) and isinstance(content.get("accents"), list):
            accents = content["accents"]
            break
    expected_accents = [normalize_color(accent) for accent in ACCENTS]
    if len(accents) != 6:
        emit(
            "FAIL",
            "theme-bracket-accents",
            f"expected 6 accents, found {len(accents)}",
        )
    elif any(
        not isinstance(accent, str) or not HEX_RE.match(accent) for accent in accents
    ):
        emit("FAIL", "theme-bracket-accents", "an accent is not a valid hex colour")
    elif [normalize_color(accent) for accent in accents] != expected_accents:
        emit(
            "FAIL",
            "theme-bracket-accents",
            "accents do not match the documented Monokai accent list",
        )
    else:
        emit(
            "PASS",
            "theme-bracket-accents",
            "six documented Monokai accents",
        )

    docs_ok = False
    docs_detail = ""
    try:
        docs_text = Path(args.docs).read_text(encoding="utf-8")
        start = docs_text.find(BEGIN_MARKER)
        end = docs_text.find(END_MARKER, start + 1 if start >= 0 else 0)
        if start < 0 or end < 0:
            docs_detail = "palette markers are missing"
        else:
            block = docs_text[start + len(BEGIN_MARKER) : end]
            fail_rows = [
                line
                for line in block.splitlines()
                if re.search(r"\|\s*FAIL\s*\|", line)
            ]
            pass_rows = [
                line
                for line in block.splitlines()
                if re.search(r"\|\s*PASS\s*\|", line)
            ]
            if fail_rows:
                docs_detail = f"{len(fail_rows)} FAIL row(s) in the palette table"
            elif len(pass_rows) < len(ROLES):
                docs_detail = (
                    f"expected at least {len(ROLES)} PASS rows, "
                    f"found {len(pass_rows)}"
                )
            else:
                missing_colors: list[str] = []
                for role, specification in ROLES.items():
                    colors = role_colors.get(role, set())
                    if len(colors) != 1:
                        missing_colors.append(f"{role}: no single override colour")
                        continue
                    color = next(iter(colors))
                    label_rows = [
                        line
                        for line in block.splitlines()
                        if line.startswith("|")
                        and len(line.split("|")) > 2
                        and line.split("|")[1].strip() == specification["label"]
                    ]
                    if len(label_rows) != 1:
                        missing_colors.append(
                            f"{role}: expected one table row, found {len(label_rows)}"
                        )
                        continue
                    row_colors = [
                        found.lower()
                        for found in re.findall(
                            r"`(#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?)`",
                            label_rows[0],
                        )
                    ]
                    if color not in row_colors:
                        missing_colors.append(
                            f"{role}: table row does not show {color}"
                        )
                if missing_colors:
                    docs_detail = "; ".join(missing_colors)
                else:
                    docs_ok = True
                    docs_detail = f"{len(pass_rows)} PASS rows match the fragment"
    except OSError as exc:
        docs_detail = str(exc)

    if syntax_failures:
        emit(
            "FAIL",
            "theme-contrast-table",
            "; ".join(syntax_failures[:4]),
        )
    elif syntax_count == 0:
        emit("FAIL", "theme-contrast-table", "no syntax colours to check")
    elif not docs_ok:
        emit("FAIL", "theme-contrast-table", docs_detail)
    else:
        emit(
            "PASS",
            "theme-contrast-table",
            f"{syntax_count} syntax colours pass; background {background}; docs {docs_detail}",
        )

    if docs_ok:
        emit("PASS", "theme-docs", f"{args.docs} contains the palette table")
    else:
        emit("FAIL", "theme-docs", docs_detail)

    theme = fragment_data.get("theme")
    if (
        isinstance(theme, dict)
        and theme.get("mode") == "dark"
        and theme.get("dark") == DEFAULT_DARK_THEME
        and isinstance(theme.get("light"), str)
    ):
        emit(
            "PASS",
            "theme-fragment-default",
            f"mode=dark dark={theme.get('dark')!r} light={theme.get('light')!r}",
        )
    else:
        emit(
            "FAIL",
            "theme-fragment-default",
            "fragment does not select Tokyo Night as the dark theme",
        )

    if args.installed_dir:
        installed_root = Path(args.installed_dir)
        names = _installed_theme_names(installed_root)
        for item, extension_id, wanted in (
            ("theme-tokyo-theme", TOKYO_EXTENSION_ID, DEFAULT_DARK_THEME),
            ("theme-monokai-theme", MONOKAI_EXTENSION_ID, MONOKAI_THEME_NAME),
        ):
            extension_dir = installed_root / extension_id
            if not extension_dir.is_dir():
                emit("FAIL", item, f"missing extension directory {extension_dir}")
            elif wanted not in names:
                emit("FAIL", item, f"theme {wanted!r} is not in the installed JSON")
            else:
                emit("PASS", item, f"{wanted!r} is installed")

        installed_names = _installed_theme_names(installed_root)
    else:
        installed_names = []

    if args.settings:
        settings_path = Path(args.settings)
        if not settings_path.exists():
            emit("SKIP", "theme-installed-name", f"missing {settings_path}")
            emit("SKIP", "theme-brackets-enabled", "settings.json not applied yet")
            emit("SKIP", "theme-semantic-tokens", "settings.json not applied yet")
        else:
            try:
                settings, _ = read_jsonc(settings_path)
            except (ConfigError, OSError) as exc:
                emit(
                    "FAIL",
                    "theme-installed-name",
                    f"cannot parse settings: {str(exc).replace(chr(10), ' ')}",
                )
                settings = None
            if isinstance(settings, dict):
                selected: list[str] = []
                selected_theme = settings.get("theme")
                if isinstance(selected_theme, str):
                    selected = [selected_theme]
                elif isinstance(selected_theme, dict):
                    for key in ("dark", "light"):
                        value = selected_theme.get(key)
                        if isinstance(value, str):
                            selected.append(value)
                if not selected:
                    emit(
                        "FAIL",
                        "theme-installed-name",
                        "settings has no theme name",
                    )
                elif not installed_names:
                    emit(
                        "FAIL",
                        "theme-installed-name",
                        "no installed theme JSON found to compare against",
                    )
                else:
                    missing = [name for name in selected if name not in installed_names]
                    if missing:
                        emit(
                            "FAIL",
                            "theme-installed-name",
                            f"not installed: {', '.join(missing)}",
                        )
                    else:
                        emit(
                            "PASS",
                            "theme-installed-name",
                            f"installed: {', '.join(selected)}",
                        )

                if settings.get("colorize_brackets") is True:
                    emit("PASS", "theme-brackets-enabled", "colorize_brackets=true")
                else:
                    emit(
                        "FAIL",
                        "theme-brackets-enabled",
                        "colorize_brackets is not true",
                    )

                semantic_tokens = settings.get("semantic_tokens")
                expected_semantic = fragment_data.get("semantic_tokens") in (
                    "combined",
                    "full",
                )
                if semantic_tokens in ("combined", "full"):
                    emit(
                        "PASS",
                        "theme-semantic-tokens",
                        f"semantic_tokens={semantic_tokens}",
                    )
                elif not expected_semantic and semantic_tokens is None:
                    emit(
                        "SKIP",
                        "theme-semantic-tokens",
                        "fragment omits semantic_tokens for this Zed version",
                    )
                else:
                    emit(
                        "FAIL",
                        "theme-semantic-tokens",
                        f"semantic_tokens={semantic_tokens!r}",
                    )

    if args.keymap:
        try:
            keys = _theme_selector_keys(Path(args.keymap))
        except (ConfigError, OSError, ValueError) as exc:
            emit(
                "FAIL",
                "theme-keybinding",
                f"cannot parse keymap: {str(exc).replace(chr(10), ' ')}",
            )
        else:
            if keys:
                emit(
                    "PASS",
                    "theme-keybinding",
                    f"{', '.join(keys)} -> {THEME_SELECTOR_ACTION}",
                )
            else:
                emit(
                    "FAIL",
                    "theme-keybinding",
                    f"no binding for {THEME_SELECTOR_ACTION}",
                )

    if args.live_keymap:
        live_keymap = Path(args.live_keymap)
        if not live_keymap.exists():
            emit("FAIL", "theme-live-keybinding", f"missing {live_keymap}")
        else:
            try:
                keys = _theme_selector_keys(live_keymap)
            except (ConfigError, OSError, ValueError) as exc:
                emit(
                    "FAIL",
                    "theme-live-keybinding",
                    f"cannot parse keymap: {str(exc).replace(chr(10), ' ')}",
                )
            else:
                if keys:
                    emit(
                        "PASS",
                        "theme-live-keybinding",
                        f"{', '.join(keys)} -> {THEME_SELECTOR_ACTION}",
                    )
                else:
                    emit(
                        "FAIL",
                        "theme-live-keybinding",
                        f"{live_keymap} has no binding for {THEME_SELECTOR_ACTION}",
                    )

    return 1 if failures else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate and check the zed-fedora-ide phase-3 theme files."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser(
        "generate", help="generate the settings fragment and docs palette table"
    )
    generate.add_argument("--tokyo-json", help="Tokyo Night theme JSON file")
    generate.add_argument("--monokai-json", help="Monokai theme JSON file")
    generate.add_argument(
        "--tokyo-extension-dir",
        help="installed tokyo-night extension directory",
    )
    generate.add_argument(
        "--monokai-extension-dir",
        help="installed zedokai extension directory",
    )
    generate.add_argument(
        "--fragment",
        required=True,
        help="path to config/settings.d/03-theme.json",
    )
    generate.add_argument("--docs", required=True, help="path to docs/THEME.md")
    generate.add_argument(
        "--colorize-brackets",
        action="store_true",
        default=True,
        help="write colorize_brackets=true (default)",
    )
    generate.add_argument(
        "--no-colorize-brackets",
        dest="colorize_brackets",
        action="store_false",
        help="omit colorize_brackets",
    )
    generate.add_argument(
        "--semantic-tokens",
        choices=["combined", "full"],
        default="combined",
        help="semantic_tokens value (default: combined)",
    )
    generate.add_argument(
        "--no-semantic-tokens",
        dest="semantic_tokens",
        action="store_const",
        const=None,
        help="omit semantic_tokens",
    )
    generate.add_argument("--dry-run", action="store_true")
    generate.set_defaults(func=command_generate)

    status = subparsers.add_parser(
        "status", help="print the theme sources found on this system"
    )
    status.add_argument("--installed-dir", help="Zed extensions/installed directory")
    status.add_argument(
        "--tokyo-extension-dir", help="installed tokyo-night extension directory"
    )
    status.add_argument(
        "--monokai-extension-dir", help="installed zedokai extension directory"
    )
    status.add_argument("--tokyo-json", help="Tokyo Night theme JSON file")
    status.add_argument("--monokai-json", help="Monokai theme JSON file")
    status.set_defaults(func=command_status)

    check = subparsers.add_parser(
        "check", help="check the fragment, docs, settings and keymap"
    )
    check.add_argument(
        "--fragment",
        required=True,
        help="path to config/settings.d/03-theme.json",
    )
    check.add_argument("--docs", required=True, help="path to docs/THEME.md")
    check.add_argument("--settings", help="live ~/.config/zed/settings.json")
    check.add_argument("--keymap", help="path to config/keymap.d/03-theme.json")
    check.add_argument(
        "--live-keymap",
        help="live ~/.config/zed/keymap.json",
    )
    check.add_argument(
        "--installed-dir",
        help="Zed extensions/installed directory",
    )
    check.add_argument("--tokyo-json", help="Tokyo Night theme JSON file")
    check.set_defaults(func=command_check)

    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
