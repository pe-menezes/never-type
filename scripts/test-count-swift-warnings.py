#!/usr/bin/env python3
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("count-swift-warnings.py")


class WarningCounterTests(unittest.TestCase):
    def run_counter_bytes(self, data: bytes) -> subprocess.CompletedProcess[str]:
        with tempfile.NamedTemporaryFile(mode="wb") as log:
            log.write(data)
            log.flush()
            return subprocess.run(
                ["python3", str(SCRIPT), log.name],
                capture_output=True,
                text=True,
                check=False,
            )

    def run_counter(self, text: str) -> subprocess.CompletedProcess[str]:
        return self.run_counter_bytes(text.encode())

    def test_repeated_fingerprint_counts_once(self) -> None:
        header = "/repo/A.swift:1:2: warning: repeated\n"
        result = self.run_counter(header * 10)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "1\n")

    def test_different_messages_at_the_same_location_are_distinct(self) -> None:
        result = self.run_counter(
            "/repo/A.swift:1:2: warning: first\n"
            "/repo/A.swift:1:2: warning: second\n"
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "2\n")

    def test_relative_path_with_spaces_and_global_warning_count(self) -> None:
        result = self.run_counter(
            "    | warning: caret\n"
            "warning: global tool warning\n"
            "My Sources/A File.swift:3:4: warning: source warning\n"
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "2\n")

    def test_ansi_and_crlf_do_not_change_the_fingerprint(self) -> None:
        result = self.run_counter(
            "\x1b[33m/repo/A.swift:1:2: warning: colored\x1b[0m\r\n"
            "/repo/A.swift:1:2: warning: colored\n"
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "1\n")

    def test_global_warnings_deduplicate_by_message(self) -> None:
        result = self.run_counter(
            "warning: first\n"
            "warning: first\n"
            "warning: second\n"
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "2\n")

    def test_five_fingerprints_are_reported_for_the_workflow_limit(self) -> None:
        result = self.run_counter(
            "".join(f"/repo/F{i}.swift:1:1: warning: {i}\n" for i in range(5))
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "5\n")

    def test_empty_log_counts_zero(self) -> None:
        result = self.run_counter("")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "0\n")

    def test_missing_log_fails_closed(self) -> None:
        result = subprocess.run(
            ["python3", str(SCRIPT), "/path/that/does/not/exist"],
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)

    def test_invalid_utf8_fails_closed(self) -> None:
        result = self.run_counter_bytes(
            b"/repo/A.swift:1:1: warning: invalid \xff\n"
        )

        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
