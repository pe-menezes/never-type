#!/usr/bin/env python3
"""Count unique canonical warning fingerprints in a build log."""

import argparse
import re
from pathlib import Path


ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
SOURCE_WARNING = re.compile(
    r"^(?P<path>.+\.swift):"
    r"(?P<line>[0-9]+):(?P<column>[0-9]+): warning: (?P<message>.+)$"
)
GLOBAL_WARNING = re.compile(r"^warning: (?P<message>.+)$")


def count_warning_fingerprints(log_path: Path) -> int:
    fingerprints: set[tuple[str, ...]] = set()

    with log_path.open(encoding="utf-8") as log:
        for raw_line in log:
            line = ANSI_ESCAPE.sub("", raw_line.rstrip("\r\n"))
            if match := SOURCE_WARNING.fullmatch(line):
                fingerprints.add(
                    (
                        "source",
                        match["path"],
                        match["line"],
                        match["column"],
                        match["message"],
                    )
                )
            elif match := GLOBAL_WARNING.fullmatch(line):
                fingerprints.add(("global", match["message"]))

    return len(fingerprints)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    print(count_warning_fingerprints(args.log))


if __name__ == "__main__":
    main()
