#!/usr/bin/env python3
"""Tests for lib/zed_config.py and its JSONC parser.

Run from the repository root:
    python3 config/templates/test/test_zed_config.py

The fixtures in this directory are parsed directly; every write goes to a
temporary directory. Nothing under ~/.config is touched.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "lib"))

import zed_config  # noqa: E402


def run_cli(
    config_dir: Path, zed_dir: Path, *extra: str
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(ROOT / "lib" / "zed_config.py"),
        "--config-dir",
        str(config_dir),
        "--zed-dir",
        str(zed_dir),
        *extra,
    ]
    return subprocess.run(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


EXISTING_SETTINGS = r"""{
  // Existing user settings for the merge test.
  "vim_mode": false,
  "autosave": "off",
  "theme": "One Dark",
  "languages": {
    "Rust": {
      "tab_size": 2,
    },
  },
}
"""

EXISTING_KEYMAP = r"""[
  // Existing user keymap.
  {
    "bindings": {
      "ctrl-right": "editor::SelectLargerSyntaxNode",
    },
  },
]
"""

EXISTING_TASKS = r"""[
  {
    "label": "My existing task",
    "command": "echo \"$ZED_WORKTREE_ROOT\"",
  },
]
"""


class JsoncParserTests(unittest.TestCase):
    def test_sample_file_with_comments_and_trailing_commas(self) -> None:
        data, text = zed_config.read_jsonc(HERE / "sample.jsonc")

        self.assertEqual(data["theme"], "One Dark")
        self.assertEqual(
            data["buffer_font_family"],
            'Example "Mono" /* not a comment */ // still a string',
        )
        self.assertEqual(data["buffer_font_size"], 16)
        self.assertEqual(data["languages"]["Python"]["tab_size"], 4)
        self.assertIn("/* A block comment", text)

    def test_comment_markers_inside_strings_are_kept(self) -> None:
        text = '{\n  "a": "http://x/*y*/", // line comment\n  "b": [1, 2,],\n}'
        data = zed_config.parse_jsonc(text, "inline")
        self.assertEqual(data, {"a": "http://x/*y*/", "b": [1, 2]})
        self.assertEqual(len(zed_config.strip_comments(text)), len(text))

    def test_unterminated_block_comment_is_rejected(self) -> None:
        with self.assertRaises(zed_config.ConfigError) as raised:
            zed_config.parse_jsonc('{"a": 1 /* never closed', "bad.json")
        self.assertIn("unterminated block comment", str(raised.exception))

    def test_unterminated_string_is_rejected(self) -> None:
        with self.assertRaises(zed_config.ConfigError) as raised:
            zed_config.parse_jsonc('{"a": "never closed}', "bad.json")
        self.assertIn("unterminated string", str(raised.exception))

    def test_invalid_json_reports_line_and_column(self) -> None:
        with self.assertRaises(zed_config.ConfigError) as raised:
            zed_config.parse_jsonc('{\n  "a": 1,\n  "b" 2\n}', "bad.json")
        message = str(raised.exception)
        self.assertIn("bad.json", message)
        self.assertIn("line 3", message)


class ConfigCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.base = Path(self.temporary_directory.name)

        self.zed_dir = self.base / "zed"
        self.zed_dir.mkdir()
        self.settings_path = self.zed_dir / "settings.json"
        self.keymap_path = self.zed_dir / "keymap.json"
        self.tasks_path = self.zed_dir / "tasks.json"
        self.snippet_path = self.zed_dir / "snippets" / "snippets.json"

        self.settings_path.write_text(EXISTING_SETTINGS, encoding="utf-8")
        self.keymap_path.write_text(EXISTING_KEYMAP, encoding="utf-8")
        self.tasks_path.write_text(EXISTING_TASKS, encoding="utf-8")

    def test_merge_apply(self) -> None:
        result = run_cli(HERE, self.zed_dir, "--yes")
        combined = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, combined)

        settings = json.loads(self.settings_path.read_text(encoding="utf-8"))
        self.assertFalse(settings["vim_mode"])
        self.assertEqual(settings["autosave"], "off")
        self.assertEqual(settings["theme"], "One Light")
        self.assertEqual(settings["buffer_font_size"], 17)
        self.assertEqual(settings["ui_font_size"], 14)
        self.assertEqual(
            settings["languages"]["Python"],
            {"tab_size": 4, "format_on_save": "on"},
        )
        self.assertEqual(settings["languages"]["Rust"]["tab_size"], 4)

        self.assertIn("CONFLICT theme", combined)
        self.assertIn("CONFLICT languages.Rust.tab_size", combined)
        self.assertIn("comments in", combined.lower())
        self.assertIn("backup", combined.lower())

        keymap = json.loads(self.keymap_path.read_text(encoding="utf-8"))
        self.assertEqual(len(keymap), 3)
        self.assertEqual(
            keymap[0]["bindings"]["ctrl-right"],
            "editor::SelectLargerSyntaxNode",
        )
        self.assertEqual(
            keymap[1]["bindings"]["ctrl-left"],
            "editor::SelectSmallerSyntaxNode",
        )
        self.assertEqual(keymap[2]["context"], "ProjectPanel && not_editing")

        tasks = json.loads(self.tasks_path.read_text(encoding="utf-8"))
        labels = [task["label"] for task in tasks]
        self.assertEqual(
            labels,
            ["My existing task", "Echo current file", "List project files"],
        )
        echo_task = tasks[1]
        self.assertIn("$ZED_RELATIVE_FILE", echo_task["command"])

        self.assertTrue(self.snippet_path.is_file())
        self.assertEqual(
            self.snippet_path.read_bytes(),
            (HERE / "snippets" / "snippets.json").read_bytes(),
        )

    def test_second_run_is_idempotent(self) -> None:
        first = run_cli(HERE, self.zed_dir, "--yes")
        self.assertEqual(first.returncode, 0, first.stderr)

        before = {
            path: path.read_bytes()
            for path in (
                self.settings_path,
                self.keymap_path,
                self.tasks_path,
                self.snippet_path,
            )
        }

        second = run_cli(HERE, self.zed_dir, "--yes")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("No changes", second.stdout)
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content, f"{path} changed on rerun")

    def test_dry_run_writes_nothing(self) -> None:
        original_settings = self.settings_path.read_bytes()
        original_keymap = self.keymap_path.read_bytes()
        original_tasks = self.tasks_path.read_bytes()
        result = run_cli(HERE, self.zed_dir, "--dry-run", "--yes")
        combined = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, combined)

        self.assertEqual(self.settings_path.read_bytes(), original_settings)
        self.assertEqual(self.keymap_path.read_bytes(), original_keymap)
        self.assertEqual(self.tasks_path.read_bytes(), original_tasks)
        self.assertFalse(self.snippet_path.exists())
        self.assertIn("--- a/settings.json", result.stdout)
        self.assertIn("+++ b/settings.json", result.stdout)
        self.assertNotIn("APPLIED", result.stdout)

    def test_check_validates_without_creating_target(self) -> None:
        fresh_zed = self.base / "fresh-zed"
        result = run_cli(HERE, fresh_zed, "--check")
        combined = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, combined)
        self.assertIn("CHECK OK", result.stdout)
        self.assertFalse(fresh_zed.exists())

    def test_check_rejects_bad_fragment(self) -> None:
        config = self.base / "bad-config"
        (config / "settings.d").mkdir(parents=True)
        (config / "settings.d" / "bad.json").write_text(
            '{\n  "theme": "One Dark",\n  /* never closed\n}',
            encoding="utf-8",
        )
        result = run_cli(config, self.base / "fresh-zed", "--check")
        combined = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unterminated block comment", combined)

    def test_check_rejects_invalid_existing_settings(self) -> None:
        self.settings_path.write_text('{"theme": ', encoding="utf-8")
        result = run_cli(HERE, self.zed_dir, "--check")
        combined = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid JSONC", combined)

    def test_check_rejects_non_utf8_existing_settings(self) -> None:
        self.settings_path.write_bytes(b'{"theme": "\xff"}\n')
        result = run_cli(HERE, self.zed_dir, "--check")
        combined = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not valid UTF-8", combined)

    def test_changed_snippet_requires_confirmation(self) -> None:
        config = self.base / "snippet-config"
        shutil.copytree(HERE / "snippets", config / "snippets")

        snippet_dir = self.zed_dir / "snippets"
        snippet_dir.mkdir()
        changed = (
            '{"Changed": {"prefix": "changed", "body": ["changed"]}}\n'
        )
        self.snippet_path.write_text(changed, encoding="utf-8")

        skipped = run_cli(config, self.zed_dir)
        self.assertEqual(skipped.returncode, 0, skipped.stderr)
        self.assertEqual(
            self.snippet_path.read_text(encoding="utf-8"),
            changed,
        )
        self.assertIn("SKIP", skipped.stdout)

        overwritten = run_cli(config, self.zed_dir, "--yes")
        self.assertEqual(overwritten.returncode, 0, overwritten.stderr)
        self.assertEqual(
            self.snippet_path.read_bytes(),
            (HERE / "snippets" / "snippets.json").read_bytes(),
        )
        self.assertIn("OVERWROTE", overwritten.stdout)

    def test_no_fragments_is_a_noop(self) -> None:
        empty_config = self.base / "empty-config"
        empty_config.mkdir()
        fresh_zed = self.base / "noop-zed"

        result = run_cli(empty_config, fresh_zed)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No config fragments", result.stdout)
        self.assertFalse(fresh_zed.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
