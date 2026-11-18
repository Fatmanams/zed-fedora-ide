#!/usr/bin/env python3
"""Merge zed-fedora-ide configuration fragments into a Zed config directory.

Standard library only. Reads JSONC (comments and trailing commas), merges the
fragments under ``config/`` and writes the results atomically.

Modes:
  default    merge and write (snippet overwrites ask first)
  --dry-run  print unified diffs, write nothing
  --check    parse and validate only, write nothing
"""

from __future__ import annotations

import argparse
import copy
import difflib
import json
import os
import stat
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


class ConfigError(Exception):
    """An input configuration could not be parsed or merged safely."""


@dataclass
class Conflict:
    path: str
    old: Any
    new: Any


@dataclass
class FilePlan:
    label: str
    path: Path
    old_text: str | None
    new_text: str
    changed: bool
    comments_lost: bool


@dataclass
class SnippetPlan:
    source: Path
    dest: Path
    old_bytes: bytes | None
    new_bytes: bytes
    changed: bool


def _line_col(text: str, index: int) -> tuple[int, int]:
    line = text.count("\n", 0, index) + 1
    last_newline = text.rfind("\n", 0, index)
    column = index + 1 if last_newline == -1 else index - last_newline
    return line, column


def strip_comments(text: str) -> str:
    """Remove // and /* */ comments while preserving strings and offsets.

    Comment characters are replaced with spaces (newlines are kept) so that
    JSONDecodeError line/column numbers still point at the original file.
    """
    chars = list(text)
    index = 0
    length = len(text)
    in_string = False
    string_start = 0

    while index < length:
        char = text[index]

        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            string_start = index
            index += 1
            continue

        if char == "/" and index + 1 < length:
            next_char = text[index + 1]
            if next_char == "/":
                chars[index] = " "
                chars[index + 1] = " "
                index += 2
                while index < length and text[index] not in "\r\n":
                    chars[index] = " "
                    index += 1
                continue
            if next_char == "*":
                comment_start = index
                chars[index] = " "
                chars[index + 1] = " "
                index += 2
                closed = False
                while index < length:
                    if (
                        text[index] == "*"
                        and index + 1 < length
                        and text[index + 1] == "/"
                    ):
                        chars[index] = " "
                        chars[index + 1] = " "
                        index += 2
                        closed = True
                        break
                    if text[index] not in "\r\n":
                        chars[index] = " "
                    index += 1
                if not closed:
                    line, column = _line_col(text, comment_start)
                    raise ConfigError(
                        f"unterminated block comment at line {line}, column {column}"
                    )
                continue

        index += 1

    if in_string:
        line, column = _line_col(text, string_start)
        raise ConfigError(f"unterminated string at line {line}, column {column}")

    return "".join(chars)


def strip_trailing_commas(text: str) -> str:
    """Remove commas immediately before } or ], outside strings."""
    chars = list(text)
    length = len(text)
    index = 0
    in_string = False

    while index < length:
        char = text[index]

        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            index += 1
            continue

        if char == ",":
            lookahead = index + 1
            while lookahead < length and text[lookahead] in " \t\r\n":
                lookahead += 1
            if lookahead < length and text[lookahead] in "}]":
                chars[index] = " "

        index += 1

    if in_string:
        line, column = _line_col(text, index)
        raise ConfigError(f"unterminated string at line {line}, column {column}")

    return "".join(chars)


def parse_jsonc(text: str, label: str = "<string>") -> Any:
    cleaned = strip_trailing_commas(strip_comments(text))
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise ConfigError(
            f"{label}: invalid JSONC at line {exc.lineno}, "
            f"column {exc.colno}: {exc.msg}"
        ) from exc


def read_jsonc(path: Path) -> tuple[Any, str]:
    try:
        text = path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise ConfigError(f"{path}: cannot read file: {exc}") from exc
    except UnicodeDecodeError as exc:
        raise ConfigError(f"{path}: file is not valid UTF-8: {exc}") from exc
    return parse_jsonc(text, str(path)), text


def has_comments(text: str) -> bool:
    return strip_comments(text) != text


def fragment_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(
        (path for path in directory.iterdir() if path.is_file() and path.suffix == ".json"),
        key=lambda path: path.name,
    )


def load_existing(
    path: Path, expected_type: type, kind: str
) -> tuple[Any | None, str | None]:
    if not path.exists():
        return None, None
    if not path.is_file():
        raise ConfigError(f"{path}: expected a regular file")
    data, text = read_jsonc(path)
    if not isinstance(data, expected_type):
        raise ConfigError(f"{path}: top level must be a JSON {kind}")
    return data, text


def canonical_json(value: Any) -> str:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )


def serialize_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def validate_generated_json(text: str, label: str) -> None:
    try:
        json.loads(text)
    except json.JSONDecodeError as exc:
        raise ConfigError(
            f"{label}: generated invalid JSON at line {exc.lineno}, "
            f"column {exc.colno}: {exc.msg}"
        ) from exc


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> None:
    for key, value in overlay.items():
        if (
            key in base
            and isinstance(base[key], dict)
            and isinstance(value, dict)
        ):
            deep_merge(base[key], value)
        else:
            base[key] = copy.deepcopy(value)


def collect_conflicts(
    old: Any, new: Any, prefix: str, conflicts: list[Conflict]
) -> None:
    if isinstance(old, dict) and isinstance(new, dict):
        for key, new_value in new.items():
            if key in old:
                child = f"{prefix}.{key}" if prefix else key
                collect_conflicts(old[key], new_value, child, conflicts)
        return
    if old != new:
        conflicts.append(Conflict(prefix or "<root>", old, new))


def format_value(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def print_conflicts(conflicts: list[Conflict]) -> None:
    for conflict in conflicts:
        print(
            f"CONFLICT {conflict.path}: "
            f"old={format_value(conflict.old)} new={format_value(conflict.new)}",
            file=sys.stderr,
        )


def plan_settings(
    config_dir: Path, zed_dir: Path, conflicts: list[Conflict]
) -> FilePlan | None:
    files = fragment_files(config_dir / "settings.d")
    if not files:
        return None

    path = zed_dir / "settings.json"
    existing, existing_text = load_existing(path, dict, "object")
    merged: dict[str, Any] = copy.deepcopy(existing) if existing is not None else {}

    for fragment_path in files:
        fragment, _ = read_jsonc(fragment_path)
        if not isinstance(fragment, dict):
            raise ConfigError(f"{fragment_path}: top level must be a JSON object")
        deep_merge(merged, fragment)

    if existing is not None:
        collect_conflicts(existing, merged, "", conflicts)

    if existing is None and not merged:
        return None

    new_text = serialize_json(merged)
    validate_generated_json(new_text, str(path))
    changed = existing is None or merged != existing
    old_text = serialize_json(existing) if existing is not None else None
    comments_lost = bool(existing_text and has_comments(existing_text))

    return FilePlan(
        label="settings.json",
        path=path,
        old_text=old_text,
        new_text=new_text,
        changed=changed,
        comments_lost=comments_lost,
    )


def plan_keymap(config_dir: Path, zed_dir: Path) -> FilePlan | None:
    files = fragment_files(config_dir / "keymap.d")
    if not files:
        return None

    path = zed_dir / "keymap.json"
    existing, existing_text = load_existing(path, list, "array")
    items: list[Any] = copy.deepcopy(existing) if existing is not None else []
    seen = {canonical_json(entry) for entry in items}

    for fragment_path in files:
        fragment, _ = read_jsonc(fragment_path)
        if not isinstance(fragment, list):
            raise ConfigError(f"{fragment_path}: top level must be a JSON array")
        for entry in fragment:
            if not isinstance(entry, dict):
                raise ConfigError(
                    f"{fragment_path}: every keymap entry must be a JSON object"
                )
            key = canonical_json(entry)
            if key in seen:
                continue
            seen.add(key)
            items.append(copy.deepcopy(entry))

    if existing is None and not items:
        return None

    new_text = serialize_json(items)
    validate_generated_json(new_text, str(path))
    changed = existing is None or items != existing
    old_text = serialize_json(existing) if existing is not None else None
    comments_lost = bool(existing_text and has_comments(existing_text))

    return FilePlan(
        label="keymap.json",
        path=path,
        old_text=old_text,
        new_text=new_text,
        changed=changed,
        comments_lost=comments_lost,
    )


def plan_tasks(
    config_dir: Path, zed_dir: Path, conflicts: list[Conflict]
) -> FilePlan | None:
    files = fragment_files(config_dir / "tasks.d")
    if not files:
        return None

    path = zed_dir / "tasks.json"
    existing, existing_text = load_existing(path, list, "array")
    items: list[Any] = copy.deepcopy(existing) if existing is not None else []

    indexes: dict[str, int] = {}
    for index, item in enumerate(items):
        if isinstance(item, dict):
            label = item.get("label")
            if isinstance(label, str) and label:
                indexes[label] = index

    for fragment_path in files:
        fragment, _ = read_jsonc(fragment_path)
        if not isinstance(fragment, list):
            raise ConfigError(f"{fragment_path}: top level must be a JSON array")
        for entry in fragment:
            if not isinstance(entry, dict):
                raise ConfigError(
                    f"{fragment_path}: every task entry must be a JSON object"
                )
            label = entry.get("label")
            if not isinstance(label, str) or not label:
                raise ConfigError(
                    f"{fragment_path}: every task needs a non-empty string 'label'"
                )
            if label in indexes:
                index = indexes[label]
                if items[index] != entry:
                    conflicts.append(
                        Conflict(f"tasks[{label}]", items[index], entry)
                    )
                items[index] = copy.deepcopy(entry)
            else:
                indexes[label] = len(items)
                items.append(copy.deepcopy(entry))

    if existing is None and not items:
        return None

    new_text = serialize_json(items)
    validate_generated_json(new_text, str(path))
    changed = existing is None or items != existing
    old_text = serialize_json(existing) if existing is not None else None
    comments_lost = bool(existing_text and has_comments(existing_text))

    return FilePlan(
        label="tasks.json",
        path=path,
        old_text=old_text,
        new_text=new_text,
        changed=changed,
        comments_lost=comments_lost,
    )


def plan_snippets(config_dir: Path, zed_dir: Path) -> list[SnippetPlan]:
    source_dir = config_dir / "snippets"
    if not source_dir.is_dir():
        return []

    plans: list[SnippetPlan] = []
    for source in sorted(
        (
            path
            for path in source_dir.glob("*.json")
            if path.is_file()
        ),
        key=lambda path: path.name,
    ):
        try:
            raw = source.read_bytes()
            text = raw.decode("utf-8-sig")
        except OSError as exc:
            raise ConfigError(f"{source}: cannot read snippet: {exc}") from exc
        except UnicodeDecodeError as exc:
            raise ConfigError(f"{source}: snippet is not valid UTF-8: {exc}") from exc

        snippet = parse_jsonc(text, str(source))
        if not isinstance(snippet, dict):
            raise ConfigError(f"{source}: snippet file must contain a JSON object")

        dest = zed_dir / "snippets" / source.name
        old_bytes: bytes | None = None
        if dest.exists():
            if not dest.is_file():
                raise ConfigError(f"{dest}: snippet target is not a regular file")
            try:
                old_bytes = dest.read_bytes()
            except OSError as exc:
                raise ConfigError(f"{dest}: cannot read snippet target: {exc}") from exc

        plans.append(
            SnippetPlan(
                source=source,
                dest=dest,
                old_bytes=old_bytes,
                new_bytes=raw,
                changed=old_bytes is None or old_bytes != raw,
            )
        )

    return plans


def atomic_write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(file_descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        mode = 0o644
        if path.exists():
            mode = stat.S_IMODE(path.stat().st_mode)
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, path)
    except BaseException:
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
        raise


def atomic_write_text(path: Path, text: str) -> None:
    atomic_write_bytes(path, text.encode("utf-8"))


def print_diff(label: str, old_text: str | None, new_text: str) -> None:
    from_file = "/dev/null" if old_text is None else f"a/{label}"
    old_lines = [] if old_text is None else old_text.splitlines()
    new_lines = new_text.splitlines()
    diff = difflib.unified_diff(
        old_lines,
        new_lines,
        fromfile=from_file,
        tofile=f"b/{label}",
        lineterm="",
    )
    print("\n".join(diff))


def decode_for_diff(data: bytes | None) -> str:
    if data is None:
        return ""
    return data.decode("utf-8", errors="replace")


def confirm_snippet_overwrite(path: Path) -> bool:
    print(f"Snippet target differs from the repository copy: {path}")
    if not sys.stdin.isatty():
        print(
            "  SKIP: no interactive terminal; re-run with --yes to overwrite "
            "this snippet."
        )
        return False
    try:
        answer = input("  Overwrite this snippet file? [y/N] ")
    except EOFError:
        print("  SKIP: no answer; not overwriting.")
        return False
    return answer.strip().lower() in {"y", "yes"}


def apply_plans(
    file_plans: list[FilePlan], snippet_plans: list[SnippetPlan], assume_yes: bool
) -> None:
    for plan in file_plans:
        if not plan.changed:
            continue
        if plan.comments_lost:
            print(
                f"WARNING: comments in {plan.path} will be lost when it is "
                "rewritten. Keep a backup before relying on the previous file.",
                file=sys.stderr,
            )
        atomic_write_text(plan.path, plan.new_text)
        print(f"APPLIED {plan.path}")

    for snippet_plan in snippet_plans:
        if not snippet_plan.changed:
            continue
        if snippet_plan.old_bytes is not None and not assume_yes:
            if not confirm_snippet_overwrite(snippet_plan.dest):
                print(f"SKIP {snippet_plan.dest} (existing file was not changed)")
                continue
        atomic_write_bytes(snippet_plan.dest, snippet_plan.new_bytes)
        action = "COPIED" if snippet_plan.old_bytes is None else "OVERWROTE"
        print(f"{action} {snippet_plan.dest}")


def count_fragments(config_dir: Path) -> int:
    total = 0
    for name in ("settings.d", "keymap.d", "tasks.d"):
        total += len(fragment_files(config_dir / name))
    snippets_dir = config_dir / "snippets"
    if snippets_dir.is_dir():
        total += sum(1 for path in snippets_dir.glob("*.json") if path.is_file())
    return total


def build_parser() -> argparse.ArgumentParser:
    repository_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description=(
            "Merge zed-fedora-ide config fragments into a Zed configuration "
            "directory. Reads JSONC; writes plain JSON atomically."
        )
    )
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=repository_root / "config",
        help="fragment source directory (default: repository config/)",
    )
    parser.add_argument(
        "--zed-dir",
        type=Path,
        default=Path.home() / ".config" / "zed",
        help="Zed configuration target (default: ~/.config/zed)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="print unified diffs and write nothing",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help="parse and validate inputs only; write nothing",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="overwrite changed snippet targets without prompting",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config_dir = args.config_dir.expanduser()
    zed_dir = args.zed_dir.expanduser()

    try:
        conflicts: list[Conflict] = []
        settings_plan = plan_settings(config_dir, zed_dir, conflicts)
        keymap_plan = plan_keymap(config_dir, zed_dir)
        tasks_plan = plan_tasks(config_dir, zed_dir, conflicts)
        snippet_plans = plan_snippets(config_dir, zed_dir)
    except ConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    file_plans = [
        plan for plan in (settings_plan, keymap_plan, tasks_plan) if plan is not None
    ]
    fragment_count = count_fragments(config_dir)

    if args.check:
        if fragment_count == 0:
            print("CHECK OK: no config fragments found.")
        else:
            print(
                f"CHECK OK: {fragment_count} fragment file(s) and existing "
                "Zed config parse cleanly; planned output is valid JSON."
            )
        return 0

    if fragment_count == 0:
        print("No config fragments found; nothing to do.")
        return 0

    print_conflicts(conflicts)

    if args.dry_run:
        printed = False
        for plan in file_plans:
            if plan.changed:
                print_diff(plan.label, plan.old_text, plan.new_text)
                printed = True
        for snippet_plan in snippet_plans:
            if snippet_plan.changed:
                print_diff(
                    f"snippets/{snippet_plan.dest.name}",
                    decode_for_diff(snippet_plan.old_bytes),
                    decode_for_diff(snippet_plan.new_bytes),
                )
                printed = True
        if not printed:
            print("No changes.")
        return 0

    try:
        apply_plans(file_plans, snippet_plans, args.yes)
    except ConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    changed_files = sum(1 for plan in file_plans if plan.changed)
    changed_snippets = sum(1 for plan in snippet_plans if plan.changed)
    if changed_files == 0 and changed_snippets == 0:
        print("No changes; existing Zed configuration was left untouched.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted.", file=sys.stderr)
        raise SystemExit(130)
