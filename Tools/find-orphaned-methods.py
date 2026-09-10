#!/usr/bin/env python3
"""Report Objective-C methods that are defined but never called.

This exists because a refactor once dropped the notification dispatch that
was the only caller of two capture methods, and nothing failed: the code
still built, the observers were still registered, and the feature was simply
gone. A method with no call site anywhere is the signature of that mistake.
"""

import re
import subprocess
import sys
from pathlib import Path

# Methods whose caller is AppKit, Cocoa bindings or a nib rather than our code.
FRAMEWORK_CALLED = {"dealloc", "init", "viewDidLoad", "awakeFromNib", "nibName"}

# Upstream Skim code that was already unreferenced before Anchora's own work
# began. Left in place rather than deleted, so the fork stays close to Skim.
KNOWN_UPSTREAM_ORPHANS = {"handleSnapshotViewFrameChanged"}


def selectors_defined_in(path: Path) -> set[str]:
    return set(re.findall(r"^- \([^)]*\)\s*(\w+)", path.read_text(), re.M))


def main(paths: list[str]) -> int:
    project = subprocess.run("cat *.m *.h", shell=True, capture_output=True,
                             text=True, cwd=Path(__file__).parent.parent).stdout
    orphans: list[tuple[str, str]] = []
    for name in paths:
        path = Path(name)
        for selector in sorted(selectors_defined_in(path)):
            if selector in FRAMEWORK_CALLED or selector in KNOWN_UPSTREAM_ORPHANS:
                continue
            # A trailing ":" is part of a selector, so it must not end the
            # boundary; a trailing word character means a longer, different
            # name (showFoo vs showFooFromBar) and must not match.
            boundary = r"(?![\w])"
            uses = len(re.findall(r"(?<![-\w])" + re.escape(selector) + boundary, project))
            defs = len(re.findall(r"^- \([^)]*\)\s*" + re.escape(selector) + boundary, project, re.M))
            if uses <= defs:
                orphans.append((name, selector))

    for name, selector in orphans:
        print(f"{name}: -{selector} is defined but never called")
    if orphans:
        print(f"\n{len(orphans)} method(s) with no call site.")
        return 1
    print(f"No orphaned methods in {', '.join(paths)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["SKRightSideViewController.m"]))
